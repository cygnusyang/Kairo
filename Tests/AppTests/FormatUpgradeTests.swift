import Foundation
import Testing
import KairoCommands
import KairoCore
import KairoPresentation
@testable import KairoMacApp

/// 会话与 UI 对「打开的是旧版格式」的感知（FR-KAIRO-FMT-1/2/5/6，App 侧）。
///
/// 当前格式为 v1，磁盘上不存在可迁移的更旧版本；旧版本场景用注入 loader
/// 返回 `sourceFormatVersion = current - 1` 的 `DecodedProject` 模拟，
/// KairoCore 端到端迁移由 KairoCoreTests 覆盖，待 v2 落地后改为真实旧文件。
@MainActor
@Suite("格式版本升级（App）")
struct FormatUpgradeTests {
    private func makeStore(
        projectLoader: @escaping @Sendable (URL) throws -> DecodedProject = {
            try KairoFile.read(from: $0)
        }
    ) -> WorkspaceStore {
        let suite = "kairo.apptests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return WorkspaceStore(defaults: defaults, projectLoader: projectLoader)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-format-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 写出一个当前版本的合法项目文件，供打开路径使用。
    private func writeProject(at url: URL, title: String) throws {
        let writer = makeStore()
        writer.dispatch(.setProjectTitle(title))
        writer.save(to: url)
        #expect(writer.alertMessage == nil)
    }

    /// 模拟旧版来源：项目内容来自真实文件，但声明上一版本。
    private func oldVersionLoader() -> @Sendable (URL) throws -> DecodedProject {
        { url in
            let decoded = try KairoFile.read(from: url)
            return DecodedProject(
                project: decoded.project,
                sourceFormatVersion: KairoFile.currentFormatVersion - 1
            )
        }
    }

    private func waitUntilLoaded(_ store: WorkspaceStore) async throws {
        // deadline 需留足余量：全量并行回归时，CPU 密集用例（如日宽性能套件）会
        // 长时间占用 MainActor，打开完成回调排在同一 actor 上被顺延执行；
        // 5s 墙钟会在负载高峰被排队时间耗尽而误报（isLoading 停留在 true）。
        let deadline = Date().addingTimeInterval(30)
        while store.isLoading && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(!store.isLoading)
    }

    private func openSimulatedOldVersion(_ url: URL) async throws -> WorkspaceStore {
        let store = makeStore(projectLoader: oldVersionLoader())
        store.openAsync(url: url)
        try await waitUntilLoaded(store)
        return store
    }

    private func formatVersion(in data: Data) throws -> Int {
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try #require(json["formatVersion"] as? Int)
    }

    private func fileFormatVersion(_ url: URL) throws -> Int {
        try formatVersion(in: Data(contentsOf: url))
    }

    // MARK: - FMT-1：当前版本不标记升级

    @Test func fr_kairo_fmt_1_current_version_is_not_flagged() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("current.kairo")
        try writeProject(at: url, title: "当前版本")

        let store = makeStore()
        #expect(store.open(url: url))

        #expect(!store.needsFormatUpgrade)
        #expect(store.notice?.contains("已升级") != true)
    }

    /// 打开失败按原因映射错误码：损坏/迁移失败为 file_unreadable，未来版本为 unsupported_format。
    @Test func fr_kairo_fmt_2_open_project_maps_error_codes() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let malformed = directory.appendingPathComponent("missing-version.kairo")
        try Data(#"{"project":{},"tasks":[]}"#.utf8).write(to: malformed)
        let malformedError = try #require(
            Self.openError(malformed)
        )
        #expect(malformedError.code == .fileUnreadable)
        #expect(malformedError.message.contains("formatVersion"))

        let future = directory.appendingPathComponent("future.kairo")
        try Data(#"{"formatVersion":999,"project":{},"tasks":[]}"#.utf8).write(to: future)
        let futureError = try #require(
            Self.openError(future)
        )
        #expect(futureError.code == .unsupportedFormat)
        #expect(futureError.message.contains("999"))

        let invalidJSON = directory.appendingPathComponent("not-json.kairo")
        try Data("not a kairo document".utf8).write(to: invalidJSON)
        let invalidJSONError = try #require(
            Self.openError(invalidJSON)
        )
        #expect(invalidJSONError.code == .fileUnreadable)
    }

    private static func openError(_ url: URL) -> SessionError? {
        do {
            _ = try KairoSession().openProject(at: url)
            return nil
        } catch let error as SessionError {
            return error
        } catch {
            return nil
        }
    }

    // MARK: - FMT-2：旧版本打开被标记，且不静默改写磁盘

    @Test func fr_kairo_fmt_2_old_version_is_flagged_on_open() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("old.kairo")
        try writeProject(at: url, title: "旧版项目")
        let bytesBeforeOpen = try Data(contentsOf: url)

        let store = try await openSimulatedOldVersion(url)

        #expect(store.needsFormatUpgrade)
        #expect(store.exportProject.metadata.title == "旧版项目")
        // 打开不写盘：升级只发生在保存/另存为。
        #expect(try Data(contentsOf: url) == bytesBeforeOpen)
        #expect(store.notice?.contains("已升级") != true)
    }

    // MARK: - FMT-5：保存后提示升级一次

    @Test func fr_kairo_fmt_5_save_after_upgrade_announces_once() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("old.kairo")
        try writeProject(at: url, title: "旧版项目")

        let store = try await openSimulatedOldVersion(url)
        #expect(store.needsFormatUpgrade)

        store.save()

        #expect(!store.needsFormatUpgrade)
        #expect(store.notice == I18n.t("alert.upgraded_to", "Upgraded to v%1$ld", KairoFile.currentFormatVersion))
        #expect(try fileFormatVersion(url) == KairoFile.currentFormatVersion)

        // 后续保存不再重复提示。
        store.clearNotice()
        store.dispatch(.setProjectTitle("再修改"))
        store.save()
        #expect(store.notice?.contains("已升级") != true)
        #expect(store.notice == nil)
    }

    // MARK: - FMT-6：另存为后提示升级

    @Test func fr_kairo_fmt_6_save_as_after_upgrade_announces() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("old.kairo")
        let newURL = directory.appendingPathComponent("upgraded.kairo")
        try writeProject(at: originalURL, title: "旧版项目")

        let store = try await openSimulatedOldVersion(originalURL)
        #expect(store.needsFormatUpgrade)

        store.beginExport()
        let project = Project()
        store.exportState.apply(to: project)
        let exportedData = try KairoFile.encode(project: project)
        // 断言生产导出编码（与 KairoDocument 同源）的版本，而非测试自写文件的回读。
        #expect(try formatVersion(in: exportedData) == KairoFile.currentFormatVersion)
        try exportedData.write(to: newURL)
        store.rememberSaveURL(newURL)

        #expect(!store.needsFormatUpgrade)
        #expect(
            store.notice == I18n.t(
                "alert.saved_as_upgraded",
                "Saved as a new file and upgraded to v%1$ld",
                KairoFile.currentFormatVersion
            )
        )
        #expect(store.projectURL?.standardizedFileURL == newURL.standardizedFileURL)
    }

    @Test func fr_kairo_fmt_6_save_as_fallback_write_announces_upgrade() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("old.kairo")
        let newURL = directory.appendingPathComponent("upgraded.kairo")
        try writeProject(at: originalURL, title: "旧版项目")

        let store = try await openSimulatedOldVersion(originalURL)
        #expect(store.needsFormatUpgrade)

        store.beginExport()
        // 面板打开期间继续编辑：导出快照过期，rememberSaveURL 走直接写盘分支。
        store.dispatch(.setProjectTitle("面板中修改"))
        store.rememberSaveURL(newURL)

        #expect(!store.needsFormatUpgrade)
        #expect(
            store.notice == I18n.t(
                "alert.saved_as_upgraded",
                "Saved as a new file and upgraded to v%1$ld",
                KairoFile.currentFormatVersion
            )
        )
        #expect(store.projectURL?.standardizedFileURL == newURL.standardizedFileURL)
        #expect(try fileFormatVersion(newURL) == KairoFile.currentFormatVersion)
    }

    // MARK: - 取消另存为 / 保存并打开

    @Test func fr_kairo_fmt_5_cancel_save_as_keeps_upgrade_flag() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("old.kairo")
        try writeProject(at: url, title: "旧版项目")

        let store = try await openSimulatedOldVersion(url)
        #expect(store.needsFormatUpgrade)

        store.beginExport()
        store.cancelExport()

        #expect(store.needsFormatUpgrade)
        #expect(store.notice?.contains("已升级") != true)
    }

    @Test func fr_kairo_fmt_5_save_and_open_keeps_upgrade_notice() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("old.kairo")
        let secondURL = directory.appendingPathComponent("second.kairo")
        try writeProject(at: originalURL, title: "旧版项目")
        try writeProject(at: secondURL, title: "第二个项目")

        // 仅第一个文件模拟旧版本；第二个文件按当前版本打开。
        let store = makeStore(projectLoader: { url in
            let decoded = try KairoFile.read(from: url)
            guard url.standardizedFileURL == originalURL.standardizedFileURL else {
                return decoded
            }
            return DecodedProject(
                project: decoded.project,
                sourceFormatVersion: KairoFile.currentFormatVersion - 1
            )
        })
        store.openAsync(url: originalURL)
        try await waitUntilLoaded(store)
        #expect(store.needsFormatUpgrade)

        store.dispatch(.setProjectTitle("未保存修改"))
        store.openAsync(url: secondURL)
        #expect(store.pendingOpenURL?.standardizedFileURL == secondURL.standardizedFileURL)

        store.saveAndOpenPending()
        try await waitUntilLoaded(store)

        // finishOpen 重置 notice 后，升级提示仍然可见。
        #expect(store.notice == I18n.t("alert.upgraded_to", "Upgraded to v%1$ld", KairoFile.currentFormatVersion))
        #expect(store.projectURL?.standardizedFileURL == secondURL.standardizedFileURL)
        #expect(!store.needsFormatUpgrade)
    }

    @Test func fr_kairo_fmt_5_save_and_open_load_failure_clears_pending_notice() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("old.kairo")
        let failedURL = directory.appendingPathComponent("missing.kairo")
        let thirdURL = directory.appendingPathComponent("third.kairo")
        try writeProject(at: originalURL, title: "旧版项目")
        try writeProject(at: thirdURL, title: "第三个项目")

        let store = makeStore(projectLoader: { url in
            if url.standardizedFileURL == failedURL.standardizedFileURL {
                throw CocoaError(.fileReadNoSuchFile)
            }
            let decoded = try KairoFile.read(from: url)
            guard url.standardizedFileURL == originalURL.standardizedFileURL else {
                return decoded
            }
            return DecodedProject(
                project: decoded.project,
                sourceFormatVersion: KairoFile.currentFormatVersion - 1
            )
        })
        store.openAsync(url: originalURL)
        try await waitUntilLoaded(store)
        #expect(store.needsFormatUpgrade)

        store.dispatch(.setProjectTitle("未保存修改"))
        store.openAsync(url: failedURL)
        #expect(store.pendingOpenURL?.standardizedFileURL == failedURL.standardizedFileURL)
        store.saveAndOpenPending()
        try await waitUntilLoaded(store)

        #expect(store.alertMessage != nil)
        #expect(store.projectURL?.standardizedFileURL == originalURL.standardizedFileURL)
        #expect(!store.needsFormatUpgrade)

        // 待恢复提示已随失败清理：下一次成功打开不显示上次的升级提示。
        store.alertMessage = nil
        store.openAsync(url: thirdURL)
        try await waitUntilLoaded(store)
        #expect(store.notice?.contains("已升级") != true)
        #expect(store.exportProject.metadata.title == "第三个项目")
    }

    @Test func fr_kairo_fmt_5_save_and_open_without_upgrade_has_no_upgrade_notice() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("first.kairo")
        let secondURL = directory.appendingPathComponent("second.kairo")
        try writeProject(at: firstURL, title: "第一个项目")
        try writeProject(at: secondURL, title: "第二个项目")

        let store = makeStore()
        #expect(store.open(url: firstURL))
        store.dispatch(.setProjectTitle("未保存修改"))
        store.openAsync(url: secondURL)
        #expect(store.pendingOpenURL?.standardizedFileURL == secondURL.standardizedFileURL)

        store.saveAndOpenPending()
        try await waitUntilLoaded(store)

        #expect(store.notice?.contains("已升级") != true)
        #expect(store.projectURL?.standardizedFileURL == secondURL.standardizedFileURL)
        #expect(!store.needsFormatUpgrade)
    }

    @Test func fr_kairo_fmt_5_save_and_open_merges_upgrade_notice_and_warning() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("old.kairo")
        let warningURL = directory.appendingPathComponent("warning.kairo")
        try writeProject(at: originalURL, title: "旧版项目")

        // 有子项但类型不是群组：载入时规范化并产生唯一一条 loadWarning。
        let warningProject = Project()
        warningProject.metadata.title = "带警告项目"
        let parent = TaskItem(title: "父任务", kind: .task)
        let child = TaskItem(title: "子任务", kind: .task, parentID: parent.id)
        warningProject.tasks = [parent, child]
        try KairoFile.save(warningProject, to: warningURL)

        let store = makeStore(projectLoader: { url in
            let decoded = try KairoFile.read(from: url)
            guard url.standardizedFileURL == originalURL.standardizedFileURL else {
                return decoded
            }
            return DecodedProject(
                project: decoded.project,
                sourceFormatVersion: KairoFile.currentFormatVersion - 1
            )
        })
        store.openAsync(url: originalURL)
        try await waitUntilLoaded(store)
        store.dispatch(.setProjectTitle("未保存修改"))
        store.openAsync(url: warningURL)

        store.saveAndOpenPending()
        try await waitUntilLoaded(store)

        let notice = try #require(store.notice)
        #expect(notice.contains("v\(KairoFile.currentFormatVersion)"), "合并后的提示必须保留升级说明")
        // 警告断言语义而非措辞（F-0705）：文案归 Catalog，裸跑 `swift test` 时按英文兜底渲染。
        let warning = try #require(store.loadWarnings.first)
        #expect(warning.code == .groupPromoted)
        #expect(warning.taskTitle == "父任务")
        #expect(notice.contains("父任务"), "合并后的提示必须带上警告指向的任务")
        #expect(!store.needsFormatUpgrade)
    }
}
