import Foundation
import Testing
@testable import KairoUpdater

// F-0703：更新链路错误码契约（设计 §A.3）。
// 码表发布即公共契约，只增不改；跨模块的唯一性只能靠断言兜底。

struct UpdaterErrorCodeTests {
    @Test func rawValuesArePrefixedAndUnique() {
        let values = UpdaterErrorCode.allCases.map(\.rawValue)
        #expect(Set(values).count == values.count, "存在重复更新错误码：\(values)")
        for value in values {
            #expect(value.hasPrefix("updater_"), "更新错误码必须带 updater_ 前缀：\(value)")
            #expect(value == value.lowercased(), "码值必须全小写：\(value)")
            #expect(!value.contains(" "), "码值不得含空格：\(value)")
        }
    }

    @Test func manifestParseErrorsMapToTheirCodes() {
        #expect(UpdateManifest.ParseError.invalidJSON("x").code == .manifestInvalidJSON)
        #expect(UpdateManifest.ParseError.missingField("cdHash").code == .manifestMissingField)
        #expect(UpdateManifest.ParseError.unsupportedSchemaVersion(9).code == .manifestSchemaUnsupported)
        #expect(UpdateManifest.ParseError.wrongAppId("other").code == .manifestAppIDMismatch)
        #expect(UpdateManifest.ParseError.missingField("cdHash").parameters["field"] == "cdHash")
    }

    @Test func signatureAndChecksumErrorsMapToTheirCodes() {
        #expect(ManifestVerifier.VerificationError.invalidJSON.code == .manifestInvalidJSON)
        #expect(ManifestVerifier.VerificationError.missingSignature.code == .signatureMissing)
        #expect(ManifestVerifier.VerificationError.invalidPublicKey.code == .publicKeyInvalid)
        #expect(ManifestVerifier.VerificationError.invalidSignatureData.code == .signatureDataInvalid)
        #expect(ManifestVerifier.VerificationError.signatureMismatch.code == .signatureMismatch)
        #expect(UpdateChecksumError.readFailed("eof").code == .checksumReadFailed)
        #expect(UpdateChecksumError.mismatch.code == .checksumMismatch)
    }

    @Test func endpointNetworkAndInstallErrorsMapToTheirCodes() {
        #expect(UpdateEndpointPolicy.PolicyError.insecureScheme("http").code == .endpointScheme)
        #expect(UpdateEndpointPolicy.PolicyError.hostNotAllowed(nil).code == .endpointHost)
        #expect(UpdateEndpointPolicy.PolicyError.insecureScheme("http").parameters["scheme"] == "http")
        #expect(OTAHTTPError(statusCode: 503).code == .httpStatus)
        #expect(OTAHTTPError(statusCode: 503).parameters["status"] == "503")
        #expect(OTADownloadMoveError(detail: "disk").code == .downloadSaveFailed)
        #expect(InstallError.unzipFailed("bad").code == .unzipFailed)
        #expect(InstallError.appNotFound.code == .appNotFound)
        #expect(InstallError.scriptWriteFailed("ro").code == .scriptWriteFailed)
        #expect(InstallError.scriptLaunchFailed("exit").code == .scriptLaunchFailed)
        #expect(InstallError.launchPathMismatch.code == .launchPathMismatch)
    }

    @Test func productVerificationErrorsMapToTheirCodes() {
        #expect(AppProductVerifier.VerificationError.cannotCreateCode(-1).code == .codeCreateFailed)
        #expect(AppProductVerifier.VerificationError.cannotReadSigningInfo(-2).code == .signingInfoUnreadable)
        #expect(AppProductVerifier.VerificationError.missingCdHash.code == .cdhashMissing)
        #expect(AppProductVerifier.VerificationError.identifierMismatch("x").code == .identifierMismatch)
        #expect(
            AppProductVerifier.VerificationError.cdHashMismatch(expected: "a", actual: "b").code
                == .cdhashMismatch
        )
        #expect(AppProductVerifier.VerificationError.cannotCreateCode(-1).parameters["status"] == "-1")
    }

    /// F-0719：安装脚本的三个失败码（外观上「安装失败」但原因不同，面板文案分别渲染）。
    @Test func installScriptFailureCodesExist() {
        #expect(UpdaterErrorCode.installAppStillRunning.rawValue == "updater_install_app_still_running")
        #expect(UpdaterErrorCode.installBackupFailed.rawValue == "updater_install_backup_failed")
        #expect(UpdaterErrorCode.installReplaceFailed.rawValue == "updater_install_replace_failed")
        // 脚本稳定码（InstallResult.FailureReason）到错误码的映射由 UpdaterManager 测试覆盖。
        #expect(InstallResult.FailureReason.backupFailed.rawValue == "backup_failed")
        #expect(InstallResult.FailureReason.appNotQuitting.rawValue == "app_not_quitting")
    }

    @Test func managerFailureConversionKeepsCodeAndParameters() {
        let coded = UpdaterManager.failure(from: UpdateChecksumError.mismatch)
        #expect(coded.code == .checksumMismatch)

        let arbitrary = UpdaterManager.failure(from: URLError(.timedOut))
        #expect(arbitrary.code == .installFailed)
        #expect(arbitrary.parameters["detail"] != nil)

        let passthrough = UpdaterFailure(code: .checkFailed, parameters: ["ref": "X"])
        #expect(UpdaterManager.failure(from: passthrough) == passthrough)
    }
}
