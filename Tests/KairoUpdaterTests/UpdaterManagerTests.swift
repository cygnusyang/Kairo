import Foundation
import Testing
@testable import KairoUpdater

/// 状态机全迁移测试（协议注入 stub，不联网）。
@MainActor
@Suite("OTA 状态机")
struct UpdaterManagerTests {
    // MARK: - stubs

    private final class StubFetcher: ManifestFetching, @unchecked Sendable {
        var result: Result<Data, Error>
        init(result: Result<Data, Error>) { self.result = result }
        func fetchManifest(from url: URL) async throws -> Data {
            try result.get()
        }
    }

    private final class StubDownloader: DataDownloading, @unchecked Sendable {
        var archiveURL: URL
        var progressReported: [Double] = []
        init(archiveURL: URL) { self.archiveURL = archiveURL }
        func download(from url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
            progress(0.5)
            progressReported.append(0.5)
            return archiveURL
        }
    }

    private final class StubInstaller: Installing, @unchecked Sendable {
        var appURL: URL
        var performed = 0
        init(appURL: URL) { self.appURL = appURL }
        func prepare(downloadedArchive: URL) async throws -> URL { appURL }
        func perform(info: UpdateInfo, downloadedAppURL: URL, currentAppURL: URL) async throws {
            performed += 1
        }
    }

    private final class StubVerifier: ProductVerifying {
        func verifyApp(at url: URL, expectedCdHash: String) throws {}
    }

    // MARK: - 夹具

    private func makeManager(
        keys: (privateKeyBase64: String, publicKeyBase64: String),
        fetcher: ManifestFetching,
        downloader: DataDownloading,
        installer: Installing,
        currentVersion: String = "1.0.0",
        userDefaults: UserDefaults
    ) -> UpdaterManager {
        UpdaterManager(
            manifestURL: URL(string: "https://github.com/example/test/releases/latest/download/update-manifest.json")!,
            expectedAppId: "app.kairo.test",
            currentVersion: currentVersion,
            currentAppURL: URL(fileURLWithPath: "/Applications/Test.app"),
            publicKeyBase64: keys.publicKeyBase64,
            policy: UpdateEndpointPolicy(allowedHosts: ["github.com"]),
            fetcher: fetcher,
            downloader: downloader,
            installer: installer,
            verifier: StubVerifier(),
            userDefaults: userDefaults
        )
    }

    private func makeFixture(version: String = "1.1.0") throws -> (
        UpdaterManager, StubDownloader, StubInstaller, UserDefaults, URL
    ) {
        let keys = TestKeys.makeKeyPair()
        let suite = "kairo.updatertests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-ota-test-\(UUID().uuidString).zip")
        try Data("stub".utf8).write(to: archiveURL)

        let downloader = StubDownloader(archiveURL: archiveURL)
        let installer = StubInstaller(appURL: URL(fileURLWithPath: "/tmp/Test.app"))
        var dict = TestKeys.manifestDict(version: version)
        // 清单 sha256 必须与夹具 zip 真实一致（download() 会强制比对）
        dict["sha256"] = try UpdateChecksum.sha256Hex(of: archiveURL)
        let manager = makeManager(
            keys: keys,
            fetcher: StubFetcher(result: .success(try TestKeys.signedManifest(
                dict: dict,
                privateKeyBase64: keys.privateKeyBase64))),
            downloader: downloader,
            installer: installer,
            userDefaults: defaults)
        return (manager, downloader, installer, defaults, archiveURL)
    }

    // MARK: - 用例

    @Test func checkFindsUpdateAndDownloadsToConfirmedState() async throws {
        let (updater, downloader, installer, defaults, archive) = try makeFixture()
        defer { defaults.removePersistentDomain(forName: "kairo.updatertests") }

        await updater.check()
        guard case .updateAvailable(let info) = updater.state else {
            Issue.record("期望 updateAvailable，实际 \(updater.state)")
            return
        }
        #expect(info.version == "1.1.0")
        #expect(info.sha256 != nil)

        await updater.download()
        #expect(updater.state == .downloaded)
        #expect(downloader.progressReported.contains(0.5))

        await updater.install()
        #expect(updater.state == .installing)
        #expect(installer.performed == 1)
        _ = archive
    }

    @Test func sameVersionReportsUpToDate() async throws {
        let (updater, _, _, defaults, _) = try makeFixture(version: "1.0.0")
        defaults.removePersistentDomain(forName: "kairo.updatertests")
        await updater.check()
        #expect(updater.state == .upToDate)
    }

    @Test func belowMinimumFailsClosed() async throws {
        // 清单要求最低 2.0.0，当前 1.0.0 → 拒装
        let keys = TestKeys.makeKeyPair()
        let suite = "kairo.updatertests.min.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let signed = try TestKeys.signedManifest(
            dict: TestKeys.manifestDict(minimumVersion: "2.0.0"),
            privateKeyBase64: keys.privateKeyBase64)
        let manager = makeManager(
            keys: keys,
            fetcher: StubFetcher(result: .success(signed)),
            downloader: StubDownloader(archiveURL: URL(fileURLWithPath: "/dev/null")),
            installer: StubInstaller(appURL: URL(fileURLWithPath: "/tmp/Test.app")),
            userDefaults: defaults)
        await manager.check()
        guard case .failed(let failure) = manager.state else {
            Issue.record("期望 failed，实际 \(manager.state)")
            return
        }
        // F-0703：失败态只带码与参数，文案由更新面板渲染（不再断言中文串）。
        #expect(failure.code == .minimumVersionUnmet)
        #expect(failure.parameters["minimumVersion"] == "2.0.0")
        #expect(failure.parameters["currentVersion"] == "1.0.0")
    }

    @Test func networkFailureIsNotSilentlyUpToDate() async throws {
        let keys = TestKeys.makeKeyPair()
        let suite = "kairo.updatertests.net.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let manager = makeManager(
            keys: keys,
            fetcher: StubFetcher(result: .failure(URLError(.cannotConnectToHost))),
            downloader: StubDownloader(archiveURL: URL(fileURLWithPath: "/dev/null")),
            installer: StubInstaller(appURL: URL(fileURLWithPath: "/tmp/Test.app")),
            userDefaults: defaults)
        await manager.check()
        guard case .failed(let failure) = manager.state else {
            Issue.record("期望 failed，实际 \(manager.state)")
            return
        }
        #expect(failure.code == .checkFailed)
        // 诊断号随参数下发（日志与支持渠道沿用 OTA-E-2001）。
        #expect(failure.parameters["ref"] == UpdaterManager.checkFailureReference)
    }

    @Test func invalidSignatureFailsClosed() async throws {
        let keys = TestKeys.makeKeyPair()
        let suite = "kairo.updatertests.sig.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        // 无签名清单（仅公钥校验应失败）
        let unsigned = try ManifestVerifier.canonicalJSONData(TestKeys.manifestDict())
        let manager = makeManager(
            keys: keys,
            fetcher: StubFetcher(result: .success(unsigned)),
            downloader: StubDownloader(archiveURL: URL(fileURLWithPath: "/dev/null")),
            installer: StubInstaller(appURL: URL(fileURLWithPath: "/tmp/Test.app")),
            userDefaults: defaults)
        await manager.check()
        guard case .failed = manager.state else {
            Issue.record("期望 failed，实际 \(manager.state)")
            return
        }
    }

    @Test func skipVersionSuppressesPromptUntilNewer() async throws {
        let (updater, _, _, defaults, _) = try makeFixture(version: "1.1.0")
        defaults.removePersistentDomain(forName: "kairo.updatertests")
        await updater.check()
        updater.skipCurrentUpdate()
        #expect(updater.state == .upToDate)

        // 同版本再查仍静默
        await updater.check()
        #expect(updater.state == .upToDate)

        // 新版本重新提示（fixture 固定 1.1.0 → 新 fixture 版本 1.2.0 验证）
        let (updater2, _, _, defaults2, _) = try makeFixture(version: "1.2.0")
        defaults2.removePersistentDomain(forName: "kairo.updatertests")
        updater2.skipCurrentUpdate()
        await updater2.check()
        guard case .updateAvailable = updater2.state else {
            Issue.record("新版本应重新提示，实际 \(updater2.state)")
            return
        }
    }

    @Test func dismissResetsToIdle() async throws {
        let (updater, _, _, defaults, _) = try makeFixture()
        defaults.removePersistentDomain(forName: "kairo.updatertests")
        await updater.check()
        updater.dismiss()
        #expect(updater.state == .idle)
    }
}
