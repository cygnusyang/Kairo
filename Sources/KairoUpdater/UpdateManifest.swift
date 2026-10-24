// UpdateManifest.swift —— 更新清单 schema v1。
//
// 移植自 COFFER OTA（macos/Coffer/Updater/UpdateManifest.swift），通用化改造：
// `expectedAppId` 由硬编码常量改为 parse 入参（模块不再绑定具体 App）。
//
// 解析（Codable）+ 显式校验（schemaVersion / appId / 必需字段），全部失败
// 路径显式报错（拒装）。signature 为必需字段（验签在 ManifestVerifier）。
// sha256 为可选字段：存在且非空即须与下载 zip 字节一致（校验在
// UpdaterManager.download，见 UpdateChecksum.swift）；缺省或空串跳过
// （向后兼容旧清单）。字段随 canonical JSON 一并被签名覆盖。

import Foundation

/// 更新清单（schema v1）。
public struct UpdateManifest: Codable, Equatable {
    /// 当前识别的 schema 版本（恒 1，不识别即拒装）。
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let appId: String
    public let version: String
    public let minimumVersion: String
    /// RFC3339 构建时间（字符串原样参与 canonical）。
    public let buildTime: String
    public let downloadUrl: String
    /// 产物代码签名 CDHash（40 位 hex 小写，kSecCodeInfoUnique 语义）。
    public let cdHash: String
    public let securityCritical: Bool
    public let notes: String?
    /// 下载 zip 的 SHA256（可选：缺省/空串跳过校验，向后兼容旧清单）。
    public let sha256: String?
    /// base64 Ed25519 签名（canonical(除 signature 外全字段 JSON)）。
    public let signature: String

    /// 清单解析与合法性显式错误（fail-closed：任何不满足即拒装）。
    /// 清单解析失败（F-0703）：只暴露码与参数，文案由更新面板渲染。
    public enum ParseError: Error, UpdaterCodedError, Equatable {
        case invalidJSON(String)
        case missingField(String)
        case unsupportedSchemaVersion(Int)
        case wrongAppId(String)

        public var code: UpdaterErrorCode {
            switch self {
            case .invalidJSON: return .manifestInvalidJSON
            case .missingField: return .manifestMissingField
            case .unsupportedSchemaVersion: return .manifestSchemaUnsupported
            case .wrongAppId: return .manifestAppIDMismatch
            }
        }

        public var parameters: [String: String] {
            switch self {
            case .invalidJSON(let detail): return ["detail": detail]
            case .missingField(let key): return ["field": key]
            case .unsupportedSchemaVersion(let version): return ["schemaVersion": String(version)]
            case .wrongAppId(let appId): return ["appId": appId]
            }
        }
    }

    /// 解析并校验清单（fail-closed：非 JSON / 缺字段 / schema ≠ 1 / appId
    /// 不匹配一律抛错）。
    public static func parse(_ data: Data, expectedAppId: String) throws -> UpdateManifest {
        let manifest: UpdateManifest
        do {
            manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
        } catch let error as DecodingError {
            throw decodeError(from: error)
        } catch {
            throw ParseError.invalidJSON("\(error)")
        }
        guard manifest.schemaVersion == currentSchemaVersion else {
            throw ParseError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        guard manifest.appId == expectedAppId else {
            throw ParseError.wrongAppId(manifest.appId)
        }
        return manifest
    }

    /// 把 Codable 解码错误映射为缺字段/非法 JSON（保留字段名，便于定位）。
    private static func decodeError(from error: DecodingError) -> ParseError {
        switch error {
        case .keyNotFound(let key, _):
            return .missingField(key.stringValue)
        case .valueNotFound(let type, let context):
            let key = context.codingPath.first?.stringValue ?? "\(type)"
            return .missingField(key)
        case .typeMismatch(_, let context),
             .dataCorrupted(let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return .invalidJSON(path.isEmpty ? "\(error)" : "字段 \(path)")
        @unknown default:
            return .invalidJSON("\(error)")
        }
    }
}
