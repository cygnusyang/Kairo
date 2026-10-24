import Foundation
import Testing
@testable import KairoUpdater

/// 安装层：解压、脚本契约、清理守卫（真实 ditto/codesign，无网络）。
@Suite("OTA 安装层")
struct InstallerTests {
    @Test func prepareExtractsAppFromZip() async throws {
        // 构造最小 .app → ditto 打 zip → prepare 解压取回 .app
        let fixtureDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-ota-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: fixtureDir.appendingPathComponent("Test.app/Contents/MacOS"),
            withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(
            to: fixtureDir.appendingPathComponent("Test.app/Contents/MacOS/Test"))
        let zipURL = fixtureDir.appendingPathComponent("Test.zip")
        try InstallerScript.runProcess(
            "/usr/bin/ditto", args: ["-c", "-k", "--keepParent",
                                     fixtureDir.appendingPathComponent("Test.app").path, zipURL.path])
        defer { try? FileManager.default.removeItem(at: fixtureDir) }

        let installer = ZipAppInstaller()
        let app = try await installer.prepare(downloadedArchive: zipURL)
        #expect(app.pathExtension == "app")
        #expect(app.lastPathComponent == "Test.app")
        // 清理解压目录（前缀守卫）
        InstallerScript.cleanupFailedProductExtractionDir(of: app)
        #expect(!FileManager.default.fileExists(atPath: app.deletingLastPathComponent().path))
    }

    @Test func replacementScriptWaitsBacksUpReplacesAndReports() throws {
        // 脚本契约真机验证：当前 pid 用一个即将退出的 sleep 子进程替代——
        // 直接以「pid 已退出」路径验证 备份→替换→result 握手。
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-ota-script-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let currentApp = dir.appendingPathComponent("Current.app")
        let newApp = dir.appendingPathComponent("New.app")
        for (app, marker) in [(currentApp, "old"), (newApp, "new")] {
            try FileManager.default.createDirectory(
                at: app.appendingPathComponent("Contents/MacOS"),
                withIntermediateDirectories: true)
            try Data(marker.utf8).write(
                to: app.appendingPathComponent("Contents/MacOS/Runner"))
        }
        let backup = dir.appendingPathComponent("Kairo-123.app")
        let result = dir.appendingPathComponent("kairo-ota-result-test.json")
        let scriptPath = dir.appendingPathComponent("install.sh")
        // pid=1（launchd，永存活）改为已退出 pid：用 pid 999999（大概率不存在）→ 立即通过
        let script = InstallerScript.replacement(
            newAppPath: newApp.path, currentAppPath: currentApp.path,
            backupPath: backup.path, resultFilePath: result.path, pid: 999_999)
        try script.write(to: scriptPath, atomically: true, encoding: .utf8)

        try InstallerScript.runProcess("/bin/bash", args: [scriptPath.path])

        #expect(FileManager.default.fileExists(atPath: currentApp.appendingPathComponent("Contents/MacOS/Runner").path))
        #expect(try String(contentsOf: currentApp.appendingPathComponent("Contents/MacOS/Runner"), encoding: .utf8) == "new")
        #expect(FileManager.default.fileExists(atPath: backup.appendingPathComponent("Contents/MacOS/Runner").path))
        let decoded = try JSONDecoder().decode(
            InstallResult.self, from: try Data(contentsOf: result))
        // headless 环境 `open` 拉不起无 Info.plist 的夹具 App → 走「已替换但自动
        // 启动失败」回退分支（success=true, code=1）；核心契约（备份+替换+result
        // 握手）已由上面三个断言锁定。
        #expect(decoded.success)
        #expect(decoded.code == 1)
        // F-0719：结果 JSON 的 message 现在是稳定码（脚本不再写中文，更新面板按码渲染）。
        #expect(decoded.message == "relaunch_failed")
        #expect(decoded.reason == .relaunchFailed)
    }

    /// F-0719：脚本正文（会落盘到用户磁盘、并写进 result JSON）不得出现任何中文——
    /// 面板直接渲染 result 里的 message，中文会漏到英文界面。
    @Test func replacementScriptContainsNoNaturalLanguage() {
        let script = InstallerScript.replacement(
            newAppPath: "/tmp/New.app",
            currentAppPath: "/Applications/Kairo.app",
            backupPath: "/tmp/Kairo-123.app",
            resultFilePath: "/tmp/kairo-ota-result-1.json",
            pid: 42
        )
        let cjk = script.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }
        #expect(cjk.isEmpty, "替换脚本含中文：\(String(cjk))；脚本只允许写稳定码")

        for token in ["app_not_quitting", "backup_failed", "replace_failed", "relaunch_failed"] {
            #expect(script.contains(token), "脚本缺少失败码 \(token)")
        }
    }

    @Test func shapeGuardsFailClosed() {
        #expect(InstallerScript.isBackupShape("/tmp/Kairo-1712345678.app"))
        #expect(!InstallerScript.isBackupShape("/tmp/Other-1712345678.app"))
        #expect(!InstallerScript.isBackupShape("/tmp/Kairo-backup.txt"))
        #expect(InstallerScript.isResultShape("/tmp/kairo-ota-result-ABC.json"))
        #expect(!InstallerScript.isResultShape("/tmp/other-file.json"))
    }

    @Test func launchPathMismatchFailsFast() async throws {
        let keys = TestKeys.makeKeyPair()
        let suite = "kairo.updatertests.mismatch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var launched: [URL] = []
        let installer = ZipAppInstaller(
            userDefaults: defaults,
            runningAppURLProvider: { URL(fileURLWithPath: "/build/Test.app") },
            log: { _ in },
            launchScript: { url, _ in launched.append(url) })

        let info = try UpdateInfo(manifest: UpdateManifest.parse(
            try TestKeys.signedManifest(
                dict: TestKeys.manifestDict(), privateKeyBase64: keys.privateKeyBase64),
            expectedAppId: "app.kairo.test"))
        do {
            try await installer.perform(
                info: info,
                downloadedAppURL: URL(fileURLWithPath: "/tmp/kairo-ota-x/Test.app"),
                currentAppURL: URL(fileURLWithPath: "/Applications/Test.app"))
            Issue.record("期望 launchPathMismatch，实际未抛错")
        } catch let error as InstallError {
            #expect(error == .launchPathMismatch)
        }
        #expect(launched.isEmpty, "错位时不得启动脚本")
        #expect(defaults.string(forKey: ZipAppInstaller.pendingResultPathDefaultsKey) == nil,
                "错位时不得留下 pending 状态")
    }
}
