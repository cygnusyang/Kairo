// InstallerSupport.swift —— 安装脚本构造、结果握手与清理支撑。
// 移植自 COFFER OTA 的 OTAInstaller（通用化：Kairo 命名、detached bash 载体）。

import Foundation

/// 安装机制协议（注入点：测试用 stub；生产用 `ZipAppInstaller`）。
public protocol Installing {
    /// 解压下载的 zip 到临时目录，返回解压出的 .app URL。
    func prepare(downloadedArchive: URL) async throws -> URL
    /// 落盘替换脚本并脱离启动，随即返回（替换/回滚/relaunch 由脚本执行）。
    func perform(info: UpdateInfo, downloadedAppURL: URL, currentAppURL: URL) async throws
}

/// 安装显式错误（fail-closed：任何一步失败即呈现 failed）。
public enum InstallError: Error, UpdaterCodedError, Equatable {
    case unzipFailed(String)
    case appNotFound
    case scriptWriteFailed(String)
    case scriptLaunchFailed(String)
    /// 启动路径错位（运行中 App ≠ 安装目标）。
    case launchPathMismatch

    public var code: UpdaterErrorCode {
        switch self {
        case .unzipFailed: return .unzipFailed
        case .appNotFound: return .appNotFound
        case .scriptWriteFailed: return .scriptWriteFailed
        case .scriptLaunchFailed: return .scriptLaunchFailed
        case .launchPathMismatch: return .launchPathMismatch
        }
    }

    public var parameters: [String: String] {
        switch self {
        case .unzipFailed(let detail),
             .scriptWriteFailed(let detail),
             .scriptLaunchFailed(let detail):
            return ["detail": detail]
        case .appNotFound, .launchPathMismatch:
            return [:]
        }
    }
}

/// 脚本写回的结果文件（成功/失败 + 退出码 + 稳定码；重启后的 App 首启消费）。
///
/// `message` 自 F-0719 起只装**稳定码**（如 `backup_failed`），不再写自然语言：
/// 该 JSON 会被更新面板直接渲染，中文会漏到英文界面（06 §8 明确不可豁免）。
/// 字段名保留 `message` 是为了兼容旧版本脚本已写下的结果文件（旧值是中文字符串，
/// `reason` 解析为 nil，调用方只认退出码，文案一律不展示）。
public struct InstallResult: Codable, Equatable {
    /// 脚本失败/提示的稳定码（与 `message` 字段同值，语义化视图）。
    public enum FailureReason: String, Codable, CaseIterable, Sendable {
        case appNotQuitting = "app_not_quitting"
        case backupFailed = "backup_failed"
        case replaceFailed = "replace_failed"
        /// 已替换成功但 relaunch 失败（success = true）。
        case relaunchFailed = "relaunch_failed"
    }

    public let success: Bool
    public let code: Int
    /// 稳定码（旧版本脚本可能写中文，此时 `reason` 为 nil）。
    public let message: String

    public init(success: Bool, code: Int, message: String) {
        self.success = success
        self.code = code
        self.message = message
    }

    /// `message` 的语义化视图；未知取值（含 v0.8.5 的中文文案）为 nil。
    public var reason: FailureReason? { FailureReason(rawValue: message) }
}

/// 替换脚本构造与文件形状守卫（纯函数，可独立测试）。
public enum InstallerScript {
    /// 替换脚本：等当前进程退出（上限 60s）→ 备份 → 替换 → relaunch →
    /// 写 result JSON（成功/失败均写，App 首启消费）。单引号包裹所有路径，
    /// 防空格与特殊字符拆参。
    public static func replacement(
        newAppPath: String, currentAppPath: String, backupPath: String,
        resultFilePath: String, pid: Int32
    ) -> String {
        let q: (String) -> String = { "'\($0)'" }
        return """
        #!/bin/bash
        # Kairo OTA replacement script: written by the app and launched detached;
        # after the parent process exits it is supervised by launchd.
        # Result JSON carries stable codes only (no natural language) - F-0719.
        RESULT_FILE=\(q(resultFilePath))
        write_result() {
          printf '{"success":%s,"code":%d,"message":"%s"}\\n' "$2" "$1" "$3" > "$RESULT_FILE"
        }
        for i in $(seq 1 300); do
          kill -0 \(pid) 2>/dev/null || break
          sleep 0.2
        done
        if kill -0 \(pid) 2>/dev/null; then
          write_result 4 false "app_not_quitting"
          exit 1
        fi
        rm -rf \(q(backupPath))
        if ! mv \(q(currentAppPath)) \(q(backupPath)); then
          write_result 3 false "backup_failed"
          exit 1
        fi
        if ! cp -R \(q(newAppPath)) \(q(currentAppPath)); then
          mv \(q(backupPath)) \(q(currentAppPath)) 2>/dev/null
          write_result 2 false "replace_failed"
          exit 1
        fi
        if ! open \(q(currentAppPath)); then
          write_result 1 true "relaunch_failed"
          exit 0
        fi
        write_result 0 true ""
        exit 0
        """
    }

    /// 备份文件名形状校验：`Kairo-<stamp>.app`（与父目录前缀双守卫，fail-closed）。
    public static func isBackupShape(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name.hasPrefix("Kairo-") && name.hasSuffix(".app")
    }

    /// result 文件名形状校验：`kairo-ota-result-*.json`（fail-closed 不误删）。
    public static func isResultShape(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name.hasPrefix("kairo-ota-result-") && name.hasSuffix(".json")
    }

    /// install 失败路径 best-effort 清理解压目录。安全边界：父目录名必须匹配
    /// 自建的 `kairo-ota-*` 前缀才删（绝不误删非本场目录）；失败静默。
    public static func cleanupFailedProductExtractionDir(of downloadedAppURL: URL) {
        let dir = downloadedAppURL.deletingLastPathComponent()
        guard dir.lastPathComponent.hasPrefix("kairo-ota-") else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// 编码 result JSON（与脚本写入、App 首启读取同构；测试夹具复用）。
    public static func encodeResult(_ result: InstallResult) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(result)
    }

    /// 同步跑子进程（解压），非 0 退出抛错（stderr 并入错误）。
    static func runProcess(_ executable: String, args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let suffix = detail.isEmpty ? "" : "：\(detail)"
            throw NSError(
                domain: "ZipAppInstaller", code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "\(executable) 退出码 \(process.terminationStatus)\(suffix)"])
        }
    }
}
