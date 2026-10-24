import Foundation

/// 更新链路稳定错误码（F-0703 / 设计 §A.3）。文法 updater_<group>_<detail>，v0.9.0 起冻结，只增不改。
///
/// 为什么 KairoUpdater 不复用 KairoCore 的 KairoErrorCode：OTA 模块现状零依赖，
/// 绑进核心版本节奏会让「只改核心」变成「必须同步发 OTA」。两份码表各自保证唯一性，
/// 由 KairoUpdaterTests / KairoCoreTests 的去重断言兜底。
///
/// 码进结构，自然语言进更新面板（视图层按 code 查 Catalog）。参数（HTTP 状态码、
/// 字段名、OSStatus……）放 parameters，不拼回句子。
public enum UpdaterErrorCode: String, Codable, Hashable, Sendable, CaseIterable {
    // MARK: - 清单解析与验签（UpdateManifest / ManifestVerifier）

    case manifestInvalidJSON = "updater_manifest_invalid_json"
    case manifestMissingField = "updater_manifest_missing_field"
    case manifestSchemaUnsupported = "updater_manifest_schema_unsupported"
    case manifestAppIDMismatch = "updater_manifest_app_id_mismatch"
    case signatureMissing = "updater_signature_missing"
    case publicKeyInvalid = "updater_public_key_invalid"
    case signatureDataInvalid = "updater_signature_data_invalid"
    case signatureMismatch = "updater_signature_mismatch"

    // MARK: - 完整性（UpdateChecksum）

    case checksumReadFailed = "updater_checksum_read_failed"
    case checksumMismatch = "updater_checksum_mismatch"

    // MARK: - 端点策略（UpdateEndpointPolicy）

    case endpointScheme = "updater_endpoint_scheme"
    case endpointHost = "updater_endpoint_host"

    // MARK: - 网络（OTANetworkLayer）

    case httpStatus = "updater_http_status"
    case downloadSaveFailed = "updater_download_save_failed"

    // MARK: - 安装（InstallerSupport）

    case unzipFailed = "updater_unzip_failed"
    case appNotFound = "updater_app_not_found"
    case scriptWriteFailed = "updater_script_write_failed"
    case scriptLaunchFailed = "updater_script_launch_failed"
    case launchPathMismatch = "updater_launch_path_mismatch"

    // MARK: - 产物验签（AppProductVerifier）

    case codeCreateFailed = "updater_code_create_failed"
    case signingInfoUnreadable = "updater_signing_info_unreadable"
    case cdhashMissing = "updater_cdhash_missing"
    case identifierMismatch = "updater_identifier_mismatch"
    case cdhashMismatch = "updater_cdhash_mismatch"

    // MARK: - 状态机与清单取值（UpdaterManager）

    case downloadURLInvalid = "updater_download_url_invalid"
    case buildTimeInvalid = "updater_build_time_invalid"
    /// 检查更新失败（网络 / 未知错误）；诊断号 OTA-E-2001 放 parameters["ref"]。
    case checkFailed = "updater_check_failed"
    case versionUnparsable = "updater_version_unparsable"
    case minimumVersionUnmet = "updater_minimum_version_unmet"
    /// 上次安装结果文件不可读 / 无法解码。
    case installResultUnreadable = "updater_install_result_unreadable"
    /// 安装脚本回报失败或未知错误兜底。
    case installFailed = "updater_install_failed"
}

/// 可自述错误码的错误类型（Updater 内部各错误枚举统一实现）。
///
/// 有了它，状态机不必逐个 `if let` 识别错误类型：任何实现本协议的错误都能被
/// 折算成 `UpdaterFailure`，新增错误类型时只需让枚举 conform，不改状态机。
public protocol UpdaterCodedError {
    /// 稳定错误码。
    var code: UpdaterErrorCode { get }
    /// 文案参数（字段名、状态码、路径等）；键由渲染层约定，不含自然语言。
    var parameters: [String: String] { get }
}

/// 更新失败的结构化表示（替代 v0.8.5 的 failed(String) 中文整句）。
public struct UpdaterFailure: Error, Equatable, Sendable, CustomStringConvertible {
    public var code: UpdaterErrorCode
    public var parameters: [String: String]

    public init(code: UpdaterErrorCode, parameters: [String: String] = [:]) {
        self.code = code
        self.parameters = parameters
    }

    /// 日志用描述：码 + 参数，与语言无关。
    public var description: String {
        parameters.isEmpty
            ? code.rawValue
            : "\(code.rawValue) \(parameters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))"
    }
}
