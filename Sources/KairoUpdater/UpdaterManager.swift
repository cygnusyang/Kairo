// UpdaterManager.swift —— OTA 状态机（模块公开接口）。
// 移植自 COFFER OTA 的 UpdaterManager，通用化改造：appId/公钥/feed/白名单/
// 日志全部经 init 注入；新增跳过版本支持。网络层与安装层经协议注入，测试用
// stub 驱动全部状态迁移，不真联网。

import Foundation
import os

/// 校验通过的更新信息（UI 展示用）。
public struct UpdateInfo: Equatable {
    public let version: String
    public let minimumVersion: String
    public let downloadUrl: URL
    public let cdHash: String
    /// 下载 zip 的 SHA256（可选；nil/空串 = 跳过校验，向后兼容旧清单）。
    public let sha256: String?
    public let buildTime: Date
    public let securityCritical: Bool
    public let notes: String?

    /// 从已通过解析/验签的清单构造；downloadUrl / buildTime 非法则显式报错
    ///（fail-closed，不静默降级）。
    public init(manifest: UpdateManifest) throws {
        guard let url = URL(string: manifest.downloadUrl) else {
            throw UpdateInfoError.invalidDownloadURL(manifest.downloadUrl)
        }
        guard let date = Self.parseRFC3339(manifest.buildTime) else {
            throw UpdateInfoError.invalidBuildTime(manifest.buildTime)
        }
        self.version = manifest.version
        self.minimumVersion = manifest.minimumVersion
        self.downloadUrl = url
        self.cdHash = manifest.cdHash
        self.sha256 = manifest.sha256
        self.buildTime = date
        self.securityCritical = manifest.securityCritical
        self.notes = manifest.notes
    }

    /// RFC3339 解析（与清单 `buildTime` 语义一致）。
    public static func parseRFC3339(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

/// UpdateInfo 构造的显式错误。
public enum UpdateInfoError: Error, UpdaterCodedError {
    case invalidDownloadURL(String)
    case invalidBuildTime(String)

    public var code: UpdaterErrorCode {
        switch self {
        case .invalidDownloadURL: return .downloadURLInvalid
        case .invalidBuildTime: return .buildTimeInvalid
        }
    }

    public var parameters: [String: String] {
        switch self {
        case .invalidDownloadURL(let url): return ["url": url]
        case .invalidBuildTime(let time): return ["buildTime": time]
        }
    }
}

/// Updater 状态机。
public enum UpdaterState: Equatable {
    /// 未检查
    case idle
    /// 检查中
    case checking
    /// 发现可更新
    case updateAvailable(UpdateInfo)
    /// 已是最新
    case upToDate
    /// 下载中（0...1 进度）
    case downloading(Double)
    /// 下载 + 验签完成，等待安装确认
    case downloaded
    /// 安装中（退出 + 替换 + relaunch）
    case installing
    /// 失败（码 + 参数；文案由更新面板按 code 渲染）
    case failed(UpdaterFailure)
}

/// OTA 状态机。零网络姿态：不做启动静默检查、不做定时后台检查——由 UI
/// 显式调 `check()`（自动检查策略由宿主 App 自行叠加）。
@MainActor
public final class UpdaterManager: ObservableObject {
    @Published public private(set) var state: UpdaterState = .idle

    private let manifestURL: URL
    private let expectedAppId: String
    private let currentVersion: String
    private let currentAppURL: URL
    private let publicKeyBase64: String
    private let policy: UpdateEndpointPolicy
    private let fetcher: ManifestFetching
    private let downloader: DataDownloading
    private let installer: Installing
    private let verifier: ProductVerifying
    private let userDefaults: UserDefaults
    /// 诊断日志（默认 os.log）。
    private let log: @Sendable (String) -> Void
    /// 跳过版本的持久化 key（仅严格更新版本才重新提示；securityCritical 禁跳）。
    private let skippedVersionKey: String

    /// 下载完成后的安装产物暂存（清单 info + 解压验签后的 App 路径）。
    /// `.downloaded` 态无关联值，install() 从本暂存消费；失败/dismiss/新 check 清空。
    private var pendingProduct: (info: UpdateInfo, appURL: URL)?

    public init(
        manifestURL: URL,
        expectedAppId: String,
        currentVersion: String,
        currentAppURL: URL,
        publicKeyBase64: String,
        policy: UpdateEndpointPolicy,
        fetcher: ManifestFetching,
        downloader: DataDownloading,
        installer: Installing,
        verifier: ProductVerifying,
        userDefaults: UserDefaults = .standard,
        skippedVersionKey: String = "kairo_ota_skipped_version",
        log: @escaping @Sendable (String) -> Void = ZipAppInstaller.defaultLogger
    ) {
        self.manifestURL = manifestURL
        self.expectedAppId = expectedAppId
        self.currentVersion = currentVersion
        self.currentAppURL = currentAppURL
        self.publicKeyBase64 = publicKeyBase64
        self.policy = policy
        self.fetcher = fetcher
        self.downloader = downloader
        self.installer = installer
        self.verifier = verifier
        self.userDefaults = userDefaults
        self.skippedVersionKey = skippedVersionKey
        self.log = log
    }

    /// 检查更新：拉清单 → HTTPS+白名单 → canonical 验签 → 版本比较 → 状态迁移。
    /// 网络失败 → `.failed`（错误码 OTA-E-2001，可重查；绝不静默归「已是最新」）；
    /// 验签失败 / 不匹配 → `.failed`（fail-closed，不静默）。
    public func check() async {
        guard !isInFlight else { return }
        pendingProduct = nil
        state = .checking
        do {
            try policy.validate(manifestURL)
            let data: Data
            do {
                data = try await fetcher.fetchManifest(from: manifestURL)
            } catch {
                log("清单拉取失败 url=\(manifestURL.absoluteString) error=\(error)")
                state = .failed(UpdaterFailure(
                    code: .checkFailed,
                    parameters: ["ref": Self.checkFailureReference]
                ))
                return
            }
            let manifest = try UpdateManifest.parse(data, expectedAppId: expectedAppId)
            _ = try ManifestVerifier.verify(manifestJSONData: data, publicKeyBase64: publicKeyBase64)
            let info = try UpdateInfo(manifest: manifest)
            // 纵深：下载地址也必须 https + 白名单（验签通过仍不例外）。
            try policy.validate(info.downloadUrl)
            resolveCheckOutcome(manifest: manifest, info: info)
        } catch {
            log("检查更新失败 error=\(error)")
            state = .failed(Self.failure(from: error))
        }
    }

    /// 仅下载：下载（进度）→ SHA256 校验 → 解压 → 验签 → downloaded，停在安装前。
    /// 安装一律经 .downloaded 态确认弹窗后调 install()——「退出+替换二进制」
    /// 动作确认纪律单点化。
    public func download() async {
        guard case .updateAvailable(let info) = state else { return }
        do {
            state = .downloading(0)
            let archive = try await downloader.download(from: info.downloadUrl) { progress in
                self.state = .downloading(progress)
            }
            // 下载落盘后、解压前校验 zip SHA256：清单 sha256 存在且非空即强制
            // 比对，不匹配 fail-closed 拒装；缺省/空串跳过（向后兼容旧清单）。
            if let expected = info.sha256, !expected.isEmpty {
                let actual = try UpdateChecksum.sha256Hex(of: archive)
                guard actual == expected.lowercased() else {
                    throw UpdateChecksumError.mismatch
                }
            }
            let extractedApp = try await installer.prepare(downloadedArchive: archive)
            try verifier.verifyApp(at: extractedApp, expectedCdHash: info.cdHash)
            pendingProduct = (info, extractedApp)
            state = .downloaded
        } catch {
            pendingProduct = nil
            log("下载/验签失败 error=\(error)")
            state = .failed(Self.failure(from: error))
        }
    }

    /// 安装更新：落盘替换脚本并 detached 启动 → installing。App 侧随即退出
    ///（脚本等退出后备份/替换/relaunch，结果经 result 文件在下次启动消费）。
    /// UI 唯一入口为 .downloaded 态确认弹窗；起点为 .updateAvailable 时先补 download()。
    public func install() async {
        if case .updateAvailable = state {
            await download()
        }
        guard case .downloaded = state, let product = pendingProduct else {
            return
        }
        do {
            state = .installing
            try await installer.perform(
                info: product.info, downloadedAppURL: product.appURL, currentAppURL: currentAppURL)
            // 成功路径：脚本完成替换并 relaunch，本进程即将退出；保持 .installing。
        } catch {
            pendingProduct = nil
            log("安装失败 error=\(error)")
            state = .failed(Self.failure(from: error))
        }
    }

    /// 用户跳过当前版本（securityCritical 版本禁跳；严格更新版本才重新提示）。
    public func skipCurrentUpdate() {
        guard case .updateAvailable(let info) = state, !info.securityCritical else { return }
        userDefaults.set(info.version, forKey: skippedVersionKey)
        state = .upToDate
    }

    /// 首启消费上次安装结果（宿主在启动早期调用；幂等）。成功：删备份 +
    /// 静默（.upToDate）；失败：呈现 failed（含退出码文案）。UserDefaults key
    /// 一次性消费后清除；result/备份仅在形状/父目录守卫通过时删除（fail-closed
    /// 不误删）；无 pending 则 no-op（不打扰正常启动）。
    public func consumePendingInstallResult() {
        guard let resultPath = userDefaults.string(
            forKey: ZipAppInstaller.pendingResultPathDefaultsKey) else { return }
        let resultURL = URL(fileURLWithPath: resultPath)
        let backupDir = userDefaults.string(forKey: ZipAppInstaller.pendingBackupDirDefaultsKey)
        defer {
            userDefaults.removeObject(forKey: ZipAppInstaller.pendingResultPathDefaultsKey)
            userDefaults.removeObject(forKey: ZipAppInstaller.pendingBackupPathDefaultsKey)
            userDefaults.removeObject(forKey: ZipAppInstaller.pendingBackupDirDefaultsKey)
            if let dir = backupDir,
               resultPath.hasPrefix(dir + "/"),
               InstallerScript.isResultShape(resultPath) {
                try? FileManager.default.removeItem(at: resultURL)
            }
        }
        guard let data = try? Data(contentsOf: resultURL),
              let result = try? JSONDecoder().decode(InstallResult.self, from: data) else {
            state = .failed(UpdaterFailure(code: .installResultUnreadable))
            return
        }
        guard result.success else {
            var parameters = ["exitCode": String(result.code)]
            if !result.message.isEmpty { parameters["detail"] = result.message }
            state = .failed(UpdaterFailure(code: .installFailed, parameters: parameters))
            return
        }
        if let backupPath = userDefaults.string(forKey: ZipAppInstaller.pendingBackupPathDefaultsKey),
           let dir = backupDir,
           backupPath.hasPrefix(dir + "/"),
           InstallerScript.isBackupShape(backupPath) {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: backupPath))
        }
        state = .upToDate
    }

    /// 关面板 / 清理失败态。
    public func dismiss() {
        pendingProduct = nil
        state = .idle
    }

    /// 进行中状态（不可重复 check / install）。
    private var isInFlight: Bool {
        switch state {
        case .checking, .downloading, .downloaded, .installing:
            return true
        case .idle, .upToDate, .updateAvailable, .failed:
            return false
        }
    }

    /// 版本比较 → 状态迁移（纯逻辑）。跳过的版本按「已是最新」呈现
    ///（securityCritical 例外，禁跳必显）。
    private func resolveCheckOutcome(manifest: UpdateManifest, info: UpdateInfo) {
        guard let order = VersionCompare.compare(currentVersion, manifest.version) else {
            state = .failed(UpdaterFailure(
                code: .versionUnparsable,
                parameters: ["version": manifest.version, "currentVersion": currentVersion]
            ))
            return
        }
        switch order {
        case .ascending:
            if VersionCompare.isBelow(currentVersion, minimum: manifest.minimumVersion) {
                state = .failed(UpdaterFailure(
                    code: .minimumVersionUnmet,
                    parameters: [
                        "currentVersion": currentVersion,
                        "minimumVersion": manifest.minimumVersion,
                    ]
                ))
                return
            }
            if !info.securityCritical, userDefaults.string(forKey: skippedVersionKey) == manifest.version {
                state = .upToDate
                return
            }
            state = .updateAvailable(info)
        case .equal, .descending:
            state = .upToDate
        }
    }

    /// 检查失败的诊断号（完整错误只进日志；界面按 code + 该诊断号出提示）。
    nonisolated public static let checkFailureReference = "OTA-E-2001"

    /// 任意错误 → 结构化失败（实现 UpdaterCodedError 的错误保留码与参数，其余兜底）。
    nonisolated public static func failure(from error: Error) -> UpdaterFailure {
        if let failure = error as? UpdaterFailure { return failure }
        if let coded = error as? any UpdaterCodedError {
            return UpdaterFailure(code: coded.code, parameters: coded.parameters)
        }
        return UpdaterFailure(code: .installFailed, parameters: ["detail": "\(error)"])
    }
}
