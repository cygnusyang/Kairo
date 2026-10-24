// AppProductVerifier.swift —— 下载产物代码签名验签（ad-hoc 适配版）。
//
// 移植自 COFFER OTA（macos/Coffer/Updater/SecCodeVerifier.swift），适配改造：
// Kairo 为 ad-hoc 签名（无 Apple 证书 TeamID、无 `anchor apple generic` DR），
// 三级验签收敛为两级：① bundle identifier 复核 ② kSecCodeInfoUnique CDHash
// 与清单比对（清单由发版流水线对实际产物提取并签名锚定，构成「合法签名但
// 非官方构建」防线）。
//
// 未来换发 Apple 开发者证书后，应在此加回 DR（anchor apple generic +
// TeamID）一级。

import Foundation
import Security

/// 产物验签协议（注入点：测试用 stub 驱动 install 状态机；生产用
/// `AppProductVerifier`）。
public protocol ProductVerifying {
    func verifyApp(at url: URL, expectedCdHash: String) throws
}

/// 生产验签：identifier 复核 + 清单 CDHash 比对。
public struct AppProductVerifier: ProductVerifying {
    /// 期望 bundle identifier（与清单 appId 同值）。
    public let expectedIdentifier: String

    public init(expectedIdentifier: String) {
        self.expectedIdentifier = expectedIdentifier
    }

    /// 验签显式错误（fail-closed：任何一级不过即拒装）。
    /// 产物验签失败（F-0703）：码 + 参数，文案由更新面板渲染。
    public enum VerificationError: Error, UpdaterCodedError {
        /// 无法基于路径创建静态代码对象（非 bundle / 不可读）。
        case cannotCreateCode(OSStatus)
        /// 无法读取签名信息。
        case cannotReadSigningInfo(OSStatus)
        /// 签名信息缺 `kSecCodeInfoUnique`。
        case missingCdHash
        /// bundle identifier 不匹配。
        case identifierMismatch(String)
        /// CDHash 不匹配（expected, actual）——「合法签名但非官方构建」防线。
        case cdHashMismatch(expected: String, actual: String)

        public var code: UpdaterErrorCode {
            switch self {
            case .cannotCreateCode: return .codeCreateFailed
            case .cannotReadSigningInfo: return .signingInfoUnreadable
            case .missingCdHash: return .cdhashMissing
            case .identifierMismatch: return .identifierMismatch
            case .cdHashMismatch: return .cdhashMismatch
            }
        }

        public var parameters: [String: String] {
            switch self {
            case .cannotCreateCode(let status), .cannotReadSigningInfo(let status):
                return ["status": String(status)]
            case .identifierMismatch(let identifier):
                return ["identifier": identifier]
            case .cdHashMismatch(let expected, let actual):
                return ["expected": expected, "actual": actual]
            case .missingCdHash:
                return [:]
            }
        }
    }

    /// 对 .app 做两级验签：① identifier 复核 ② kSecCodeInfoUnique 比对清单 cdHash。
    public func verifyApp(at url: URL, expectedCdHash: String) throws {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let code = staticCode else {
            throw VerificationError.cannotCreateCode(createStatus)
        }

        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard infoStatus == errSecSuccess, let dict = info as? [String: Any] else {
            throw VerificationError.cannotReadSigningInfo(infoStatus)
        }

        let identifier = dict[kSecCodeInfoIdentifier as String] as? String ?? ""
        guard identifier == expectedIdentifier else {
            throw VerificationError.identifierMismatch(identifier)
        }

        let actual = try Self.cdHashHex(of: url)
        guard actual.caseInsensitiveCompare(expectedCdHash) == .orderedSame else {
            throw VerificationError.cdHashMismatch(expected: expectedCdHash, actual: actual)
        }
    }

    /// 读取产物的 `kSecCodeInfoUnique`（CDHash，20 字节 sha256 截断），hex 小写。
    /// 与 `codesign -dv --verbose=4` 的 `CDHash=` 输出一致。
    public static func cdHashHex(of url: URL) throws -> String {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let code = staticCode else {
            throw VerificationError.cannotCreateCode(createStatus)
        }
        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard infoStatus == errSecSuccess, let dict = info as? [String: Any] else {
            throw VerificationError.cannotReadSigningInfo(infoStatus)
        }
        guard let unique = dict[kSecCodeInfoUnique as String] as? Data else {
            throw VerificationError.missingCdHash
        }
        return unique.map { String(format: "%02x", $0) }.joined()
    }
}
