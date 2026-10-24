import Foundation
import Testing
import KairoCore
import KairoPresentation
@testable import KairoMacApp

/// 「另存为」验收判据（FR-FILE-SAVEAS-1…6）：
/// 文件名建议纯函数、命令注册表入口、跨路径导出与取消语义。
@MainActor
@Suite("另存为")
struct SaveAsTests {
    private func makeStore(seedsDemoData: Bool = false) -> WorkspaceStore {
        let suite = "kairo.apptests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return WorkspaceStore(defaults: defaults, seedsDemoData: seedsDemoData)
    }

    private func makeCatalog(
        _ store: WorkspaceStore,
        requestSaveAs: @escaping @MainActor () -> Void = {}
    ) -> [KairoCommand] {
        KairoCommandCatalog.make(
            store: store,
            requestOpen: {},
            requestSave: {},
            requestSaveAs: requestSaveAs
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-saveas-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func modificationDate(of url: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.modificationDate] as? Date)
    }

    /// 用独立会话重写磁盘文件，模拟其他进程的保存（与 WorkspaceStoreTests 同款写法）。
    private func rewriteExternally(_ url: URL, title: String) throws {
        Thread.sleep(forTimeInterval: 0.05)
        let writer = makeStore()
        writer.dispatch(.setProjectTitle(title))
        writer.save(to: url)
        #expect(writer.alertMessage == nil)
    }

    /// 模拟 `fileExporter` 在用户确认时把当前快照写入目标路径。
    private func writeExportedSnapshot(_ store: WorkspaceStore, to url: URL) throws {
        let project = Project()
        store.exportState.apply(to: project)
        try KairoFile.encode(project: project).write(to: url)
    }

    // MARK: - FR-FILE-SAVEAS-1：命令来自注册表

    @Test func fr_file_saveas_1_catalog_defines_command() throws {
        let commands = makeCatalog(makeStore())
        let saveAs = try #require(commands.first { $0.id == "file.saveAs" })
        #expect(saveAs.title == I18n.t("menu.file.save_as", "Save As…"))
        #expect(saveAs.group == .file)
        #expect(saveAs.shortcut?.label == "⇧⌘S")
        #expect(saveAs.aliases.contains(I18n.t("menu.file.save_as.alias", "Save a copy")))
        // 菜单与 ⌘K 面板消费同一注册表：面板搜索必须能找到。
        let alias = try #require(saveAs.aliases.first)
        #expect(CommandPalette.matching(saveAs.title, in: commands).contains { $0.id == "file.saveAs" })
        #expect(CommandPalette.matching(alias, in: commands).contains { $0.id == "file.saveAs" })
    }

    @Test func fr_file_saveas_1_action_invokes_injected_request() throws {
        let store = makeStore()
        var requests = 0
        let command = try #require(
            makeCatalog(store) { requests += 1 }.first { $0.id == "file.saveAs" }
        )
        command.action()
        #expect(requests == 1)
    }

    // MARK: - FR-FILE-SAVEAS-2：文件名建议

    @Test func fr_file_saveas_2_uses_current_filename() {
        let url = URL(fileURLWithPath: "/tmp/季度计划.kairo")
        #expect(
            SaveFilenameSuggestion.suggest(currentURL: url, title: "别的标题")
                == "季度计划.kairo"
        )
    }

    @Test func fr_file_saveas_2_derives_from_title() {
        #expect(
            SaveFilenameSuggestion.suggest(currentURL: nil, title: "季度 计划")
                == "季度 计划.kairo"
        )
    }

    @Test func fr_file_saveas_2_replaces_illegal_characters() {
        #expect(
            SaveFilenameSuggestion.suggest(currentURL: nil, title: "季度/计划:第一阶段\u{0007}")
                == "季度-计划-第一阶段.kairo"
        )
    }

    @Test func fr_file_saveas_2_trims_trailing_replacement_hyphen() {
        #expect(SaveFilenameSuggestion.suggest(currentURL: nil, title: "季度/") == "季度.kairo")
        #expect(SaveFilenameSuggestion.suggest(currentURL: nil, title: "季度 - ") == "季度.kairo")
    }

    @Test func fr_file_saveas_2_hidden_current_filename_falls_back_to_title() {
        for path in ["/tmp/.kairo", "/tmp/.hidden.kairo", "/tmp/.隐藏.kairo"] {
            let url = URL(fileURLWithPath: path)
            #expect(
                SaveFilenameSuggestion.suggest(currentURL: url, title: "项目甲")
                    == "项目甲.kairo"
            )
            #expect(
                SaveFilenameSuggestion.suggest(currentURL: url, title: "")
                    == SaveFilenameSuggestion.fallback
            )
        }
    }

    @Test func fr_file_saveas_2_caps_filename_at_200_utf8_bytes() {
        // 中文 3 字节 + emoji 4 字节：截断必须落在字符边界，保留 .kairo 后缀。
        let longTitle = String(repeating: "计", count: 80)
            + String(repeating: "🚀", count: 20)
        let fromTitle = SaveFilenameSuggestion.suggest(currentURL: nil, title: longTitle)
        #expect(fromTitle.utf8.count <= 200)
        #expect(fromTitle.hasSuffix(".kairo"))
        #expect(fromTitle == String(repeating: "计", count: 64) + ".kairo")
        #expect(!fromTitle.contains("\u{FFFD}"))

        let longURL = URL(fileURLWithPath: "/tmp/\(longTitle).kairo")
        let fromURL = SaveFilenameSuggestion.suggest(currentURL: longURL, title: "")
        #expect(fromURL.utf8.count <= 200)
        #expect(fromURL.hasSuffix(".kairo"))
        #expect(fromURL == String(repeating: "计", count: 64) + ".kairo")
    }

    @Test func fr_file_saveas_2_trims_spaces_and_dots() {
        #expect(
            SaveFilenameSuggestion.suggest(currentURL: nil, title: "  .路线图.  ")
                == "路线图.kairo"
        )
    }

    @Test func fr_file_saveas_2_keeps_single_kairo_suffix() {
        #expect(
            SaveFilenameSuggestion.suggest(currentURL: nil, title: "路线图.kairo")
                == "路线图.kairo"
        )
    }

    @Test func fr_file_saveas_2_falls_back_when_title_empty() {
        #expect(
            SaveFilenameSuggestion.suggest(currentURL: nil, title: "   ")
                == SaveFilenameSuggestion.fallback
        )
        #expect(SaveFilenameSuggestion.fallback == "project.kairo")
    }

    @Test func fr_file_saveas_2_falls_back_when_title_all_illegal() {
        #expect(
            SaveFilenameSuggestion.suggest(currentURL: nil, title: " /: ")
                == SaveFilenameSuggestion.fallback
        )
    }

    @Test func fr_file_saveas_2_store_suggests_filename() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = makeStore()
        #expect(store.suggestedSaveFilename == I18n.t("alert.project.default_title", "Untitled Project") + ".kairo")

        store.dispatch(.setProjectTitle("路线 / 图"))
        #expect(store.suggestedSaveFilename == "路线 - 图.kairo")

        let url = directory.appendingPathComponent("已有.kairo")
        store.save(to: url)
        #expect(store.suggestedSaveFilename == "已有.kairo")
    }

    /// 另存为写盘路径必须走 `KairoFile.encode`，新文件是当前最新格式版本。
    @Test func fr_file_saveas_2_new_file_uses_current_format_version() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("原始计划.kairo")
        let newURL = directory.appendingPathComponent("副本计划.kairo")

        let store = makeStore()
        store.save(to: originalURL)
        store.dispatch(.setProjectTitle("格式版本检查"))
        store.beginExport()
        try writeExportedSnapshot(store, to: newURL)
        store.rememberSaveURL(newURL)

        let data = try Data(contentsOf: newURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["formatVersion"] as? Int == KairoFile.currentFormatVersion)

        // 能被当前解码器重新打开。
        let reopened = try KairoFile.decode(from: data)
        #expect(reopened.metadata.title == "格式版本检查")

        // 与其他写盘路径（KairoFile.save）字节一致：同一编码器、无另写序列化。
        #expect(try KairoFile.encode(project: reopened) == data)
    }

    // MARK: - FR-FILE-SAVEAS-3：跨路径保存不改原文件

    @Test func fr_file_saveas_3_saves_to_new_path() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("原始计划.kairo")
        let newURL = directory.appendingPathComponent("副本计划.kairo")

        let store = makeStore()
        store.save(to: originalURL)
        let originalBytes = try Data(contentsOf: originalURL)
        let originalMtime = try modificationDate(of: originalURL)

        store.dispatch(.setProjectTitle("另存前修改"))
        store.beginExport()
        try writeExportedSnapshot(store, to: newURL)
        let expectedTitle = store.exportProject.metadata.title
        let expectedTaskCount = store.exportProject.tasks.count

        store.rememberSaveURL(newURL)

        let saved = try KairoFile.load(from: newURL)
        #expect(saved.metadata.title == expectedTitle)
        #expect(saved.tasks.count == expectedTaskCount)
        #expect(try Data(contentsOf: originalURL) == originalBytes)
        #expect(try modificationDate(of: originalURL) == originalMtime)
    }

    // MARK: - FR-FILE-SAVEAS-4：路径切换后的保存目标

    @Test func fr_file_saveas_4_points_project_url_and_clears_dirty() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("原始计划.kairo")
        let newURL = directory.appendingPathComponent("副本计划.kairo")

        let store = makeStore()
        store.save(to: originalURL)
        let originalBytes = try Data(contentsOf: originalURL)
        let originalMtime = try modificationDate(of: originalURL)

        store.dispatch(.setProjectTitle("另存前修改"))
        store.beginExport()
        try writeExportedSnapshot(store, to: newURL)
        store.rememberSaveURL(newURL)

        #expect(store.projectURL?.standardizedFileURL == newURL.standardizedFileURL)
        #expect(!store.hasUnsavedChanges)

        // 之后的常规保存只写新路径。
        let newBytesAfterSaveAs = try Data(contentsOf: newURL)
        store.dispatch(.setProjectTitle("另存后再修改"))
        store.save()

        #expect(try Data(contentsOf: newURL) != newBytesAfterSaveAs)
        #expect(try KairoFile.load(from: newURL).metadata.title == "另存后再修改")
        #expect(try Data(contentsOf: originalURL) == originalBytes)
        #expect(try modificationDate(of: originalURL) == originalMtime)
    }

    @Test func fr_file_saveas_4_external_change_to_old_path_is_ignored() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("原始计划.kairo")
        let newURL = directory.appendingPathComponent("副本计划.kairo")

        let store = makeStore()
        store.save(to: originalURL)
        store.beginExport()
        try writeExportedSnapshot(store, to: newURL)
        store.rememberSaveURL(newURL)
        store.clearNotice()
        let titleAfterSaveAs = store.exportProject.metadata.title

        // 模拟其他进程改写旧路径；监视目标已是新路径，不应触发横幅或重载。
        try rewriteExternally(originalURL, title: "旧文件被外部改写")
        store.checkExternalUpdate()

        #expect(!store.externalUpdatePending)
        #expect(store.notice?.hasPrefix("已载入外部更新") != true)
        #expect(store.projectURL?.standardizedFileURL == newURL.standardizedFileURL)
        #expect(store.exportProject.metadata.title == titleAfterSaveAs)
        #expect(try KairoFile.load(from: originalURL).metadata.title == "旧文件被外部改写")
    }

    // MARK: - FR-FILE-SAVEAS-5：面板期间的编辑进入新文件

    @Test func fr_file_saveas_5_confirms_latest_edits() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("原始计划.kairo")
        let newURL = directory.appendingPathComponent("副本计划.kairo")

        let store = makeStore()
        store.save(to: originalURL)

        store.beginExport()
        // 面板打开期间继续编辑；确认时写入的必须是编辑后的内容。
        store.dispatch(.setProjectTitle("面板打开期间的编辑"))
        try writeExportedSnapshot(store, to: newURL)
        store.rememberSaveURL(newURL)

        #expect(!store.hasUnsavedChanges)
        #expect(try KairoFile.load(from: newURL).metadata.title == "面板打开期间的编辑")
    }

    // MARK: - FR-FILE-SAVEAS-6：取消不改状态

    @Test func fr_file_saveas_6_cancel_preserves_state() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("原始计划.kairo")

        let store = makeStore()
        store.save(to: originalURL)
        let originalBytes = try Data(contentsOf: originalURL)
        let originalMtime = try modificationDate(of: originalURL)
        let originalTitle = store.exportProject.metadata.title

        // 两条不同的撤销点（创建任务 + 改标题），验证取消不清理撤销栈。
        store.dispatch(.createTask(parentID: nil, kind: .task))
        store.beginExport()
        store.dispatch(.setProjectTitle("面板中修改"))
        let taskCount = store.exportProject.tasks.count

        store.cancelExport()

        #expect(store.projectURL?.standardizedFileURL == originalURL.standardizedFileURL)
        #expect(store.hasUnsavedChanges)
        #expect(store.exportProject.metadata.title == "面板中修改")
        #expect(try Data(contentsOf: originalURL) == originalBytes)
        #expect(try modificationDate(of: originalURL) == originalMtime)

        store.dispatch(.undo)
        #expect(store.exportProject.metadata.title == originalTitle)
        #expect(store.exportProject.tasks.count == taskCount)
    }

    @Test func fr_file_saveas_6_export_failure_classification() {
        // 用户取消是正常路径，不弹错误；真实写入错误必须上报消息。
        #expect(ExportFailure.message(for: CocoaError(.userCancelled)) == nil)
        #expect(ExportFailure.message(for: CocoaError(.fileWriteNoPermission)) != nil)
    }

    @Test func fr_file_saveas_6_export_failure_keeps_url_and_reports() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("原始计划.kairo")
        let unwritableURL = directory
            .appendingPathComponent("不存在的目录", isDirectory: true)
            .appendingPathComponent("副本计划.kairo")

        let store = makeStore()
        store.save(to: originalURL)
        store.dispatch(.setProjectTitle("写入会失败"))
        store.beginExport()
        store.cancelExport()

        store.rememberSaveURL(unwritableURL)

        #expect(store.saveState == .failed)
        #expect(store.alertMessage != nil)
        #expect(store.projectURL?.standardizedFileURL == originalURL.standardizedFileURL)
        #expect(store.hasUnsavedChanges)
    }

    @Test func fr_file_saveas_6_cancel_forces_direct_write_branch() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalURL = directory.appendingPathComponent("原始计划.kairo")
        let newURL = directory.appendingPathComponent("副本计划.kairo")

        let store = makeStore()
        store.save(to: originalURL)
        store.dispatch(.setProjectTitle("取消后直接保存"))
        store.beginExport()
        store.cancelExport()

        // exportRevision 已清理：即便版本号未变，也不能误判导出快照最新。
        store.rememberSaveURL(newURL)

        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(store.projectURL?.standardizedFileURL == newURL.standardizedFileURL)
        #expect(!store.hasUnsavedChanges)
        #expect(try KairoFile.load(from: newURL).metadata.title == "取消后直接保存")
    }
}
