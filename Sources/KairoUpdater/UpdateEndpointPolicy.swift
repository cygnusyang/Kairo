// OTAEndpointPolicy.swift —— 更新期零网络豁免的应用层白名单。
//
// 移植自 COFFER OTA（macos/Coffer/Updater/OTAEndpointPolicy.swift），通用化改造：
// host 白名单由类型常量改为实例配置（struct 携带自家 host 集合）。
//
// URL 层：只允许连白名单 host 且强制 HTTPS。纯逻辑，供
// OTANetworkSession（请求前校验 + challenge 兜底）与 UpdaterManager.check
//（downloadUrl 纵深校验）共用。

import Foundation

/// 更新端点白名单策略（强制 HTTPS + host 白名单，fail-closed）。
public struct UpdateEndpointPolicy {
    /// 白名单端点 host 集合（发布查询 / 下载重定向源 / Release asset CDN）。
    public let allowedHosts: Set<String>

    public init(allowedHosts: Set<String>) {
        self.allowedHosts = allowedHosts
    }

    /// 显式错误（fail-closed：非白名单一律拒绝，不静默降级）。
    public enum PolicyError: Error, UpdaterCodedError {
        /// 非 https（强制 HTTPS）。
        case insecureScheme(String)
        /// host 不在白名单（nil = 无 host 的 URL）。
        case hostNotAllowed(String?)

        public var code: UpdaterErrorCode {
            switch self {
            case .insecureScheme: return .endpointScheme
            case .hostNotAllowed: return .endpointHost
            }
        }

        public var parameters: [String: String] {
            switch self {
            case .insecureScheme(let scheme): return ["scheme": scheme]
            case .hostNotAllowed(let host): return ["host": host ?? ""]
            }
        }
    }

    /// host 是否在白名单（纯函数）。host 大小写不敏感（DNS/URL 语义），
    /// 统一小写比较。
    public func isAllowedHost(_ host: String) -> Bool {
        allowedHosts.contains(host.lowercased())
    }

    /// URL 是否放行：强制 https + host ∈ 白名单（纯函数）。
    public func isAllowedURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host else {
            return false
        }
        return isAllowedHost(host)
    }

    /// 校验并抛错（fail-closed）；不通过即拒绝发起连接。
    public func validate(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https" else {
            throw PolicyError.insecureScheme(url.scheme ?? "（无 scheme）")
        }
        guard let host = url.host, isAllowedHost(host) else {
            throw PolicyError.hostNotAllowed(url.host)
        }
    }
}
