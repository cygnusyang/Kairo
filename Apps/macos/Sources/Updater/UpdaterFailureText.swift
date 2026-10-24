import Foundation
import KairoUpdater

/// 更新失败文案的视图层渲染（F-0705 / 设计 §A.3）。
///
/// `KairoUpdater` 只出稳定码与参数，`errorDescription` 已删除；文案在这里按
/// `update.error.<code>` 查 Catalog，参数用 `parameters` 里的原值，不回拼自然语言。
enum UpdaterFailureText {
    static func text(_ failure: UpdaterFailure) -> String {
        switch failure.code {
        case .manifestInvalidJSON:
            return I18n.t("update.error.manifest_invalid_json", "Update manifest is malformed: %1$@", param(failure, "detail"))
        case .manifestMissingField:
            return I18n.t("update.error.manifest_missing_field", "Update manifest is missing a required field: %1$@.", param(failure, "field"))
        case .manifestSchemaUnsupported:
            return I18n.t("update.error.manifest_schema_unsupported", "Update manifest schema version %1$@ is not supported; installation refused.", param(failure, "schemaVersion"))
        case .manifestAppIDMismatch:
            return I18n.t("update.error.manifest_app_id_mismatch", "Update manifest appId “%1$@” does not match this app; installation refused.", param(failure, "appId"))
        case .signatureMissing:
            return I18n.t("update.error.signature_missing", "Update manifest has no signature; refused.")
        case .publicKeyInvalid:
            return I18n.t("update.error.public_key_invalid", "The update signing public key is invalid.")
        case .signatureDataInvalid:
            return I18n.t("update.error.signature_data_invalid", "The update manifest signature data is invalid.")
        case .signatureMismatch:
            return I18n.t("update.error.signature_mismatch", "Update manifest signature verification failed; installation refused.")
        case .checksumReadFailed:
            return I18n.t("update.error.checksum_read_failed", "Download integrity check failed: cannot read the downloaded file (%1$@).", param(failure, "detail"))
        case .checksumMismatch:
            return I18n.t("update.error.checksum_mismatch", "Download integrity check failed (SHA256 mismatch); installation refused.")
        case .endpointScheme:
            return I18n.t("update.error.endpoint_scheme", "Update requests must use HTTPS (current scheme is %1$@).", param(failure, "scheme"))
        case .endpointHost:
            return I18n.t("update.error.endpoint_host", "Update endpoint %1$@ is not allowlisted; connection refused.", param(failure, "host"))
        case .httpStatus:
            return I18n.t("update.error.http_status", "The update server returned HTTP %1$@.", param(failure, "status"))
        case .downloadSaveFailed:
            return I18n.t("update.error.download_save_failed", "Failed to save the downloaded package: %1$@", param(failure, "detail"))
        case .unzipFailed:
            return I18n.t("update.error.unzip_failed", "Failed to unzip the update package: %1$@", param(failure, "detail"))
        case .appNotFound:
            return I18n.t("update.error.app_not_found", "No .app found in the update package; installation refused.")
        case .scriptWriteFailed:
            return I18n.t("update.error.script_write_failed", "Failed to write the install script: %1$@", param(failure, "detail"))
        case .scriptLaunchFailed:
            return I18n.t("update.error.script_launch_failed", "Failed to launch the install script: %1$@", param(failure, "detail"))
        case .launchPathMismatch:
            return I18n.t(
                "update.error.launch_path_mismatch",
                "The running app is not the copy installed in Applications; run the update from Applications."
            )
        case .codeCreateFailed:
            return I18n.t("update.error.code_create_failed", "Cannot read the signing information of the app to install (OSStatus %1$@).", param(failure, "status"))
        case .signingInfoUnreadable:
            return I18n.t("update.error.signing_info_unreadable", "Cannot read the app signing information (OSStatus %1$@).", param(failure, "status"))
        case .cdhashMissing:
            return I18n.t("update.error.cdhash_missing", "The app signing information has no CDHash; installation refused.")
        case .identifierMismatch:
            return I18n.t("update.error.identifier_mismatch", "App identifier “%1$@” does not match the expected value; installation refused.", param(failure, "identifier"))
        case .cdhashMismatch:
            return I18n.t("update.error.cdhash_mismatch", "The app CDHash does not match the update manifest; installation refused (possibly an unofficial build).")
        case .downloadURLInvalid:
            return I18n.t("update.error.download_url_invalid", "The update manifest download URL is invalid: %1$@.", param(failure, "url"))
        case .buildTimeInvalid:
            return I18n.t("update.error.build_time_invalid", "The update manifest build time is invalid: %1$@.", param(failure, "buildTime"))
        case .checkFailed:
            return I18n.t("update.error.check_failed", "Update check failed (%1$@); try again later.", param(failure, "ref"))
        case .versionUnparsable:
            return I18n.t(
                "update.error.version_unparsable",
                "Cannot compare versions: manifest %1$@, current %2$@.",
                param(failure, "version"),
                param(failure, "currentVersion")
            )
        case .minimumVersionUnmet:
            return I18n.t(
                "update.error.minimum_version_unmet",
                "Current version %1$@ is below the minimum supported version %2$@; download the new version manually.",
                param(failure, "currentVersion"),
                param(failure, "minimumVersion")
            )
        case .installResultUnreadable:
            return I18n.t("update.error.install_result_unreadable", "The previous update result could not be read and was ignored.")
        case .installFailed:
            return I18n.t(
                "update.error.install_failed",
                "The previous update failed (exit code %1$@): %2$@",
                param(failure, "exitCode"),
                param(failure, "detail")
            )
        }
    }

    /// 参数缺失时的兜底文案（参数不进自然语言拼接，缺失只影响占位处）。
    private static func param(_ failure: UpdaterFailure, _ key: String) -> String {
        failure.parameters[key] ?? I18n.t("update.error.unknown_detail", "unknown cause")
    }
}
