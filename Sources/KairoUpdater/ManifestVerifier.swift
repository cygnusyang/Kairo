// ManifestVerifier.swift —— 清单 canonical JSON + Ed25519 验签。
//
// 移植自 COFFER OTA（macos/Coffer/Updater/ManifestVerifier.swift），通用化改造：
// 公钥不硬编码在模块内，改为调用方注入（各 App 把自家公钥常量放在应用侧配置）。
//
// canonical JSON 约定（关键契约）：被签名内容 = 去除 `signature` 字段后的
// JSON，序列化 = JSONSerialization + `.sortedKeys` + `.withoutEscapingSlashes`
// （无缩进）。签名侧（CI 工具 sign_update_manifest）与验签侧（本文件）用同一
// canonicalJSONData 函数保证字节一致。

import Foundation
import CryptoKit

/// 清单验签（纯逻辑，可独立测试）。
public enum ManifestVerifier {
    /// 验签显式错误（fail-closed：任何失败即拒装）。
    /// 验签失败（F-0703）：码 + 参数，文案由更新面板渲染。
    public enum VerificationError: Error, UpdaterCodedError {
        /// 清单非 JSON / 结构损坏。
        case invalidJSON
        /// 缺 `signature` 字段。
        case missingSignature
        /// 公钥 base64 非法或不是合法 Ed25519 公钥。
        case invalidPublicKey
        /// 签名 base64 非法。
        case invalidSignatureData
        /// Ed25519 验签不通过（清单被篡改 / 非官方签名）。
        case signatureMismatch

        public var code: UpdaterErrorCode {
            switch self {
            case .invalidJSON: return .manifestInvalidJSON
            case .missingSignature: return .signatureMissing
            case .invalidPublicKey: return .publicKeyInvalid
            case .invalidSignatureData: return .signatureDataInvalid
            case .signatureMismatch: return .signatureMismatch
            }
        }

        public var parameters: [String: String] { [:] }
    }

    /// canonical JSON（双侧同实现）：sortedKeys + withoutEscapingSlashes，
    /// 无缩进。CI 签名工具与 App 验签侧共用此函数保证字节一致。
    public static func canonicalJSONData(_ dict: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: dict,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    /// 对完整清单 JSON 做验签：解析 dict → 取 signature → canonical(去 signature)
    /// → Ed25519 verify。任何一步失败即抛错（fail-closed）。
    ///
    /// - Parameters:
    ///   - data: 完整清单 JSON 字节（含 signature 字段）。
    ///   - publicKeyBase64: 验证公钥（base64，Ed25519 raw 32 字节）。
    /// - Returns: 验签是否通过（true）。
    /// - Throws: `VerificationError`。
    public static func verify(manifestJSONData data: Data, publicKeyBase64: String) throws -> Bool {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              var dict = raw as? [String: Any] else {
            throw VerificationError.invalidJSON
        }
        guard let signatureBase64 = dict["signature"] as? String, !signatureBase64.isEmpty else {
            throw VerificationError.missingSignature
        }
        dict.removeValue(forKey: "signature")
        let canonical = try canonicalJSONData(dict)

        guard let publicKeyData = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            throw VerificationError.invalidPublicKey
        }
        guard let signature = Data(base64Encoded: signatureBase64) else {
            throw VerificationError.invalidSignatureData
        }
        guard publicKey.isValidSignature(signature, for: canonical) else {
            throw VerificationError.signatureMismatch
        }
        return true
    }

    /// 对 canonical JSON 签名（供 CI 签名工具与测试复用，与验签侧同 base）。
    public static func sign(canonicalDict dict: [String: Any], privateKeyBase64: String) throws -> String {
        var signingDict = dict
        signingDict.removeValue(forKey: "signature")
        let canonical = try canonicalJSONData(signingDict)
        guard let keyData = Data(base64Encoded: privateKeyBase64),
              let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
            throw VerificationError.invalidPublicKey
        }
        guard let signature = try? privateKey.signature(for: canonical) else {
            throw VerificationError.invalidSignatureData
        }
        return signature.base64EncodedString()
    }
}
