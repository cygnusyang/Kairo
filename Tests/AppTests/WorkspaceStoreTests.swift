import Foundation
import Testing
import KairoCommands
import KairoCore
import KairoPresentation
@testable import KairoMacApp

/// 应用适配层交互测试：动作经会话生效、快照刷新、撤销、文件与命令注册表。
/// 视图画面由 `GUIRenderTests` 离屏渲染覆盖。
@MainActor
@Suite("WorkspaceStore 交互")
struct WorkspaceStoreTests {
    /// 每个测试使用独立偏好域，避免写入开发者真实配置。
    /// 既有用例沿用种子数据（seedsDemoData: true）；空启动相关用例显式传 false。
    private func makeStore() -> WorkspaceStore {
        makeStore(projectLoader: { try KairoFile.read(from: $0) })
    }

    private func makeStore(seedsDemoData: Bool) -> WorkspaceStore {
        makeStore(projectLoader: { try KairoFile.read(from: $0) }, seedsDemoData: seedsDemoData)
    }

    private func makeStore(
        projectLoader: @escaping @Sendable (URL) throws -> DecodedProject,
        seedsDemoData: Bool = true
    ) -> WorkspaceStore {
        let suite = "kairo.apptests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return WorkspaceStore(defaults: defaults, seedsDemoData: seedsDemoData, projectLoader: projectLoader)
    }

    private func makeCatalog(_ store: WorkspaceStore) -> [KairoCommand] {
        KairoCommandCatalog.make(
            store: store, requestOpen: {}, requestSave: {}, requestSaveAs: {}
        )
    }

    private func command(_ commands: [KairoCommand], _ id: String) throws -> KairoCommand {
        try #require(commands.first { $0.id == id })
    }

    private func rows(_ store: WorkspaceStore) -> [PlanRow] {
        store.snapshot.outline.rows
    }

    private func row(_ store: WorkspaceStore, _ title: String) throws -> PlanRow {
        try #require(rows(store).first { $0.title == title })
    }

    private func task(_ store: WorkspaceStore, _ title: String) throws -> TaskItem {
        try #require(store.exportProject.tasks.first { $0.title == title })
    }

    private func indexOf(_ store: WorkspaceStore, _ id: UUID) throws -> Int {
        try #require(store.exportProject.tasks.firstIndex { $0.id == id })
    }

    // MARK: - 初始状态

    // 默认启动 = 空项目（AC-1）：不灌示例数据。
    @Test func storeSeedsNoTasksByDefault() throws {
        let store = makeStore(seedsDemoData: false)
        #expect(rows(store).count == 0)
        #expect(store.viewState.mode == .plan)
        #expect(store.selection == nil)
        #expect(!rows(store).contains { $0.hasSchedule })

        let gantt = store.snapshot.gantt
        #expect(gantt.bars.isEmpty)
    }

    // 主动载入示例（AC-2）：文件 → 载入示例项目 后任务数为 10，且有排期。
    @Test func loadExampleFillsSeedData() throws {
        let store = makeStore(seedsDemoData: false)
        #expect(rows(store).count == 0)

        store.loadExampleProject()
        #expect(rows(store).count == 10)
        #expect(rows(store).contains { $0.hasSchedule })
        #expect(store.snapshot.gantt.bars.count > 0)
        #expect(!store.hasUnsavedChanges)
    }

    // 有未保存修改时载入示例需确认（AC-3）：先挂起等待选择；取消则数据不变。
    @Test func loadExampleConfirmsWhenDirty() throws {
        let store = makeStore(seedsDemoData: false)
        store.dispatch(.setProjectTitle("未保存标题"))
        #expect(store.hasUnsavedChanges)

        store.loadExampleProject()
        #expect(store.pendingLoadExample)
        #expect(rows(store).count == 0)
        #expect(store.exportProject.metadata.title == "未保存标题")

        store.cancelPendingLoadExample()
        #expect(!store.pendingLoadExample)
        #expect(rows(store).count == 0)
        #expect(store.exportProject.metadata.title == "未保存标题")

        store.loadExampleProject()
        #expect(store.pendingLoadExample)
        store.confirmPendingLoadExample()
        #expect(!store.pendingLoadExample)
        #expect(rows(store).count == 10)
    }

    @Test func schedulePlacesDependentTaskAfterPredecessor() throws {
        let store = makeStore()
        let backend = try row(store, "实现搜索后端")
        let review = try row(store, "Code Review 搜索模块")
        let backendFinish = try #require(backend.scheduledFinish)
        let reviewStart = try #require(review.scheduledStart)
        #expect(reviewStart >= backendFinish)
    }

    // MARK: - 命令注册表（菜单与 ⌘K 同源）

    @Test func catalogIsSingleSourceForMenuAndPalette() {
        let commands = makeCatalog(makeStore())
        // 24 条基线 + 日宽调节 3 条（加宽 / 收窄 / 重置，Sprint 6 / T3）
        // + 大纲列显隐 8 条（F-14-20：状态/违例/前置/开始/结束/持续/负责人/完成）。
        #expect(commands.count == 35)
        #expect(Set(commands.map(\.id)).count == commands.count)
        #expect(Set(commands.map(\.group)) == Set(KairoCommandGroup.allCases))
        #expect(commands.allSatisfy { !$0.title.isEmpty })
        #expect(commands.contains { $0.id == "palette.show" })
    }

    @Test func shortcutLabelsMatchMenuBindings() throws {
        let commands = makeCatalog(makeStore())
        #expect(try command(commands, "palette.show").shortcut?.label == "⌘K")
        #expect(try command(commands, "find.previous").shortcut?.label == "⇧⌘G")
        #expect(try command(commands, "outline.newSibling").shortcut?.label == "⌘↩")
        #expect(try command(commands, "view.plan").shortcut?.label == "⌥⌘1")
        #expect(try command(commands, "view.outline").shortcut?.label == "⌥⌘2")
        #expect(try command(commands, "view.focus").shortcut?.label == "⌥⌘L")
        #expect(try command(commands, "view.violations").shortcut?.label == "⌥⌘V")
        #expect(try command(commands, "view.today").shortcut?.label == "⌥⌘T")
        #expect(try command(commands, "view.criticalPath").shortcut == nil)
        #expect(try command(commands, "edit.undo").shortcut?.label == "⌘Z")
        #expect(try command(commands, "edit.redo").shortcut?.label == "⇧⌘Z")
    }

    @Test func undoRedoCommandsRouteThroughSession() throws {
        let store = makeStore()
        let commands = makeCatalog(store)
        let backend = try task(store, "实现搜索后端")

        store.dispatch(.delete(backend.id))
        #expect(!store.exportProject.tasks.contains { $0.id == backend.id })

        try command(commands, "edit.undo").action()
        #expect(store.exportProject.tasks.contains { $0.id == backend.id })

        try command(commands, "edit.redo").action()
        #expect(!store.exportProject.tasks.contains { $0.id == backend.id })
    }

    @Test func viewCatalogCommandsSwitchMode() throws {
        let store = makeStore()
        let commands = makeCatalog(store)

        try command(commands, "view.outline").action()
        #expect(store.viewState.mode == .outline)

        try command(commands, "view.plan").action()
        #expect(store.viewState.mode == .plan)
    }

    @Test func focusCommandFromOutlineEntersPlanMode() throws {
        let store = makeStore()
        let commands = makeCatalog(store)

        try command(commands, "view.outline").action()
        try command(commands, "view.focus").action()

        #expect(store.viewState.mode == .plan)
        #expect(store.viewState.chartFocused)
    }

    @Test func violationsCommandOpensInspectorTab() throws {
        let store = makeStore()
        try command(makeCatalog(store), "view.violations").action()
        #expect(store.viewState.inspectorVisible)
        #expect(store.viewState.inspectorTab == .violations)
        #expect(store.snapshot.inspector.tab == .violations)
    }

    @Test func paletteCommandOpensPaletteAndFiltersByAlias() throws {
        let store = makeStore()
        try command(makeCatalog(store), "palette.show").action()
        #expect(store.showCommandPalette)

        let commands = makeCatalog(store)
        // 别名是文案（随语言变），断言「按注册表里的别名能搜到该命令」而不是匹配某个中文串。
        let ganttAlias = try #require(try command(commands, "view.outline").aliases.first)
        #expect(CommandPalette.matching(ganttAlias, in: commands).map(\.id) == ["view.outline"])
        let planAlias = try #require(try command(commands, "view.plan").aliases.first)
        #expect(CommandPalette.matching(planAlias, in: commands).map(\.id) == ["view.plan"])
        #expect(CommandPalette.matching("  ", in: commands).count == commands.count)
        #expect(CommandPalette.matching("不存在的命令", in: commands).isEmpty)
    }

    @Test func findCommandReopensAndRefocusesEveryPress() throws {
        let store = makeStore()
        let show = try command(makeCatalog(store), "find.show")

        show.action()
        #expect(store.showFindBar)
        let firstToken = store.findFocusToken

        show.action()
        #expect(store.findFocusToken == firstToken + 1)
    }

    // MARK: - 大纲动作

    @Test func indentAndOutdentMoveTaskThroughSession() throws {
        let store = makeStore()
        let review = try task(store, "Code Review 搜索模块")
        let release = try task(store, "发布 v1.0")

        store.dispatch(.select(release.id))
        store.dispatch(.indent(release.id))

        #expect(try task(store, "发布 v1.0").parentID == review.id)
        #expect(try row(store, "发布 v1.0").depth == 1)

        store.dispatch(.outdent(release.id))

        let moved = try task(store, "发布 v1.0")
        #expect(moved.parentID == nil)
        #expect(try indexOf(store, moved.id) > indexOf(store, review.id))
    }

    @Test func dropTargetAppendsToGroupAndInsertsAfterSibling() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")
        let design = try task(store, "设计首页原型")

        store.dispatch(.createTask(parentID: nil, kind: .group))
        let groupID = try #require(store.selection)
        store.dispatch(.createTask(parentID: groupID, kind: .task))

        let intoGroup = try #require(store.moveTarget(draggedID: backend.id, onto: groupID))
        #expect(intoGroup.parentID == groupID)
        #expect(intoGroup.index == 1)
        store.dispatch(.move(backend.id, parentID: groupID, index: intoGroup.index))
        #expect(try task(store, "实现搜索后端").parentID == groupID)

        let afterSibling = try #require(store.moveTarget(
            draggedID: design.id,
            onto: groupID
        ))
        #expect(afterSibling.parentID == groupID)

        let anchorID = try task(store, "整理用户反馈").id
        let after = try #require(store.moveTarget(draggedID: design.id, onto: anchorID))
        store.dispatch(.move(design.id, parentID: after.parentID, index: after.index))

        let siblings = store.exportProject.tasks.filter { $0.parentID == nil }
        let anchorPosition = try #require(siblings.firstIndex { $0.id == anchorID })
        let designPosition = try #require(siblings.firstIndex { $0.id == design.id })
        #expect(designPosition == anchorPosition + 1)

        store.dispatch(.setFilter("搜索"))
        #expect(store.moveTarget(draggedID: design.id, onto: anchorID) == nil)
    }

    @Test func dropHoverAutoExpandsCollapsedGroup() async throws {
        let store = makeStore()
        store.dispatch(.createTask(parentID: nil, kind: .group))
        let groupID = try #require(store.selection)
        store.dispatch(.createTask(parentID: groupID, kind: .task))
        store.dispatch(.toggleExpanded(groupID))
        #expect(try !row(store, I18n.t("outline.new_group.title", "New Group")).isExpanded)

        // 注入 1ms 延迟：并行测试负载下 600ms 计时器可能长期得不到唤醒。
        // deadline 留足余量：CPU 密集用例（性能套件）会长时间垄断 MainActor，
        // 展开回调排在同一 actor 上被顺延；5s 墙钟在负载高峰会被排队时间耗尽。
        store.scheduleDropExpand(on: groupID, delayNanoseconds: 1_000_000)
        let deadline = Date().addingTimeInterval(30)
        while try !row(store, I18n.t("outline.new_group.title", "New Group")).isExpanded && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(try row(store, I18n.t("outline.new_group.title", "New Group")).isExpanded)
    }

    @Test func dropExitCancelsPendingExpand() async throws {
        let store = makeStore()
        store.dispatch(.createTask(parentID: nil, kind: .group))
        let groupID = try #require(store.selection)
        store.dispatch(.toggleExpanded(groupID))
        #expect(try !row(store, I18n.t("outline.new_group.title", "New Group")).isExpanded)

        store.scheduleDropExpand(on: groupID)
        store.cancelDropExpand()
        try await Task.sleep(nanoseconds: 800_000_000)

        #expect(try !row(store, I18n.t("outline.new_group.title", "New Group")).isExpanded)
    }

    @Test func dropExitOnAnotherRowKeepsPendingExpand() async throws {
        let store = makeStore()
        store.dispatch(.setExpanded([]))
        store.dispatch(.createTask(parentID: nil, kind: .group))
        let group = try #require(store.selection)
        store.dispatch(.createTask(parentID: nil, kind: .group))
        let other = try #require(store.selection)
        store.dispatch(.setExpanded([]))

        store.scheduleDropExpand(on: group, delayNanoseconds: 1_000_000)
        // 另一行的 dropExited 不得取消本行计时。
        store.cancelDropExpand(on: other)
        let deadline = Date().addingTimeInterval(30)
        while !store.viewState.expandedTaskIDs.contains(group) && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(store.viewState.expandedTaskIDs.contains(group))
    }

    @Test func dropTargetRejectsSelf() {
        let store = makeStore()
        let backend = store.snapshot.outline.rows[0]
        #expect(store.moveTarget(draggedID: backend.id, onto: backend.id) == nil)
    }

    @Test func createSiblingInsertsAfterSelectionAndSelectsIt() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")

        store.dispatch(.select(backend.id))
        store.dispatch(.createSibling(after: backend.id))

        let newID = try #require(store.selection)
        let created = try #require(store.exportProject.tasks.first { $0.id == newID })
        #expect(created.title == I18n.t("outline.new_task.title", "New Task"))
        #expect(created.parentID == nil)
        #expect(try indexOf(store, newID) == indexOf(store, backend.id) + 1)
        #expect(rows(store).contains { $0.id == newID })
    }

    @Test func createTaskUsesExplicitParentAndSelectsIt() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")

        store.dispatch(.createTask(parentID: backend.id, kind: .task))

        let newID = try #require(store.selection)
        let created = try #require(store.exportProject.tasks.first { $0.id == newID })
        #expect(created.parentID == backend.id)
        #expect(created.title == I18n.t("outline.new_task.title", "New Task"))
        #expect(try row(store, created.title).depth == 1)
    }

    @Test func groupDeleteRequiresConfirmationThenRemovesSubtree() throws {
        let store = makeStore()
        store.dispatch(.select(nil))
        store.dispatch(.createTask(parentID: nil, kind: .group))
        let groupID = try #require(store.selection)

        store.dispatch(.createTask(parentID: groupID, kind: .task))
        let childID = try #require(store.selection)

        store.requestDelete(id: groupID)
        let pending = try #require(store.pendingDeletion)
        #expect(pending.taskID == groupID)
        #expect(pending.affectedCount == 2)

        store.dispatch(.select(childID))
        store.confirmPendingDeletion()

        #expect(!store.exportProject.tasks.contains { $0.id == groupID })
        #expect(!store.exportProject.tasks.contains { $0.id == childID })
        #expect(store.pendingDeletion == nil)
        #expect(store.selection == nil)
    }

    @Test func addingChildPromotesParentAndDeleteCascades() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")
        #expect(backend.kind == .task)

        store.dispatch(.createTask(parentID: backend.id, kind: .task))
        let childID = try #require(store.selection)

        #expect(try task(store, "实现搜索后端").kind == .group)
        #expect(try row(store, "实现搜索后端").kind == .group)

        store.requestDelete(id: backend.id)
        let pending = try #require(store.pendingDeletion)
        #expect(pending.affectedCount == 2)

        store.confirmPendingDeletion()
        #expect(!store.exportProject.tasks.contains { $0.id == backend.id })
        #expect(!store.exportProject.tasks.contains { $0.id == childID })
        #expect(!store.exportProject.tasks.contains { $0.parentID == backend.id })
    }

    @Test func deletingLeafTaskClearsSelection() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")
        store.dispatch(.select(backend.id))

        store.dispatch(.delete(backend.id))

        #expect(!store.exportProject.tasks.contains { $0.id == backend.id })
        #expect(store.selection == nil)
    }

    // MARK: - 字段更新与派生

    @Test func progressAndStatusRefreshSnapshot() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")

        store.dispatch(.setProgress(backend.id, 0.25))
        #expect(try row(store, "实现搜索后端").progress == 0.25)

        store.dispatch(.setStatus(backend.id, .done))
        let done = try row(store, "实现搜索后端")
        #expect(done.status == .done)
        #expect(done.progress == 1)
    }

    @Test func dependencyCycleIsRejectedWithAlert() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")
        let review = try task(store, "Code Review 搜索模块")

        // 种子数据中 review 已是 backend 的后继；反向添加会成环。
        store.dispatch(.addDependency(
            taskID: backend.id,
            predecessorID: review.id,
            type: .fs,
            lagDays: 0
        ))

        #expect(store.alertMessage != nil)
        #expect(try task(store, "实现搜索后端").dependencies.isEmpty)
    }

    @Test func predecessorCandidatesExcludeSelfAndExisting() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")
        let review = try task(store, "Code Review 搜索模块")

        let candidates = Set(store.predecessorCandidates(for: review.id).map(\.id))
        #expect(!candidates.contains(review.id))
        #expect(!candidates.contains(backend.id))
        #expect(!candidates.isEmpty)
    }

    @Test func filterWithNoMatchesProducesEmptyState() {
        let store = makeStore()
        store.dispatch(.setFilter("zzz-nothing-matches"))

        #expect(rows(store).isEmpty)
        #expect(store.snapshot.outline.emptyReason == .noMatches)
    }

    // MARK: - 撤销 / 重做

    @Test func consecutiveRenamesMergeIntoOneUndoStep() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")
        let original = backend.title

        store.dispatch(.rename(backend.id, "第一次改名"))
        store.dispatch(.rename(backend.id, "第二次改名"))
        #expect(try task(store, "第二次改名").title == "第二次改名")

        store.dispatch(.undo)
        #expect(try task(store, original).title == original)

        store.dispatch(.redo)
        #expect(try task(store, "第二次改名").title == "第二次改名")
    }

    @Test func undoRestoresDeletedTask() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")

        store.dispatch(.delete(backend.id))
        #expect(!store.exportProject.tasks.contains { $0.id == backend.id })

        store.dispatch(.undo)
        #expect(store.exportProject.tasks.contains { $0.id == backend.id })
    }

    // MARK: - 检查器与揭示

    @Test func inspectorLockKeepsFrozenTaskWhileSelectionMoves() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")
        let review = try task(store, "Code Review 搜索模块")

        store.dispatch(.select(backend.id))
        store.dispatch(.setInspectorLocked(true))
        store.dispatch(.select(review.id))

        #expect(store.inspectorSelectionDrift)
        guard case .task(let inspector) = store.snapshot.inspector.content else {
            Issue.record("锁定后检查器应停留在任务页")
            return
        }
        #expect(inspector.taskID == backend.id)
        #expect(store.snapshot.statusBar.selectionSummary == "Code Review 搜索模块")
    }

    @Test func revealExpandsCollapsedAncestors() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")

        store.dispatch(.createTask(parentID: backend.id, kind: .task))
        let childID = try #require(store.selection)

        store.dispatch(.toggleExpanded(backend.id))
        #expect(!rows(store).contains { $0.id == childID })

        store.dispatch(.reveal(childID))
        #expect(store.selection == childID)
        #expect(rows(store).contains { $0.id == childID })
    }

    @Test func revealMissingTaskClearsSelectionAndNotifies() {
        let store = makeStore()
        store.dispatch(.select(nil))
        store.dispatch(.reveal(UUID()))

        #expect(store.selection == nil)
        #expect(store.notice == I18n.t("alert.task_deleted", "Task deleted"))
        guard case .project = store.snapshot.inspector.content else {
            Issue.record("目标缺失后检查器应回到项目页")
            return
        }
    }

    // MARK: - 文件

    @Test func saveThenOpenRoundTripsProject() throws {
        let store = makeStore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("roundtrip.kairo")

        store.save(to: url)
        #expect(store.alertMessage == nil)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let reopened = makeStore()
        reopened.open(url: url)
        #expect(reopened.alertMessage == nil)
        #expect(reopened.exportProject.tasks.count == store.exportProject.tasks.count)
        #expect(reopened.projectURL?.standardizedFileURL == url.standardizedFileURL)
    }

    @Test func dirtyOpenWaitsForUserChoice() async throws {
        let store = makeStore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-dirty-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.kairo")
        let second = directory.appendingPathComponent("second.kairo")

        store.save(to: first)
        store.dispatch(.setProjectTitle("未保存标题"))
        #expect(store.hasUnsavedChanges)

        let writer = makeStore()
        writer.dispatch(.setProjectTitle("另一个项目"))
        writer.save(to: second)

        store.openAsync(url: second)
        #expect(store.pendingOpenURL?.standardizedFileURL == second.standardizedFileURL)
        #expect(store.exportProject.metadata.title == "未保存标题")

        store.cancelPendingOpen()
        #expect(store.pendingOpenURL == nil)
        #expect(store.exportProject.metadata.title == "未保存标题")

        store.openAsync(url: second)
        store.discardChangesAndOpenPending()
        // 30s：CI 慢机 + 并行负载下打开完成回调可能被顺延，2s 会误报。
        for _ in 0..<3000 where store.isLoading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(store.pendingOpenURL == nil)
        #expect(store.exportProject.metadata.title == "另一个项目")
        #expect(!store.hasUnsavedChanges)
    }

    @Test func editsDuringAsyncOpenArePreserved() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-open-race-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("remote.kairo")

        let writer = makeStore()
        writer.dispatch(.setProjectTitle("磁盘项目"))
        writer.save(to: url)

        // 受控加载：先阻塞解码，测试在载入窗口内编辑旧项目，再放行。
        let gate = DispatchSemaphore(value: 0)
        let store = makeStore(projectLoader: { url in
            gate.wait()
            return try KairoFile.read(from: url)
        })
        store.openAsync(url: url)
        store.dispatch(.setProjectTitle("载入期间编辑"))
        gate.signal()

        let deadline = Date().addingTimeInterval(30)
        while store.isLoading && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(!store.isLoading)
        #expect(store.pendingOpenURL?.standardizedFileURL == url.standardizedFileURL)
        #expect(store.exportProject.metadata.title == "载入期间编辑")
    }

    @Test func openWhileLoadingIsReportedInsteadOfSilentlyDropped() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-open-busy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.kairo")
        let second = directory.appendingPathComponent("second.kairo")

        let writer = makeStore()
        writer.dispatch(.setProjectTitle("第一个项目"))
        writer.save(to: first)
        writer.dispatch(.setProjectTitle("第二个项目"))
        writer.save(to: second)

        let gate = DispatchSemaphore(value: 0)
        let store = makeStore(projectLoader: { url in
            gate.wait()
            return try KairoFile.read(from: url)
        })
        store.openAsync(url: first)
        #expect(store.isLoading)

        store.openAsync(url: second)
        #expect(store.notice == I18n.t("alert.loading_in_progress", "A project is still loading; try opening again in a moment"))
        #expect(store.pendingOpenURL == nil)

        gate.signal()
        let deadline = Date().addingTimeInterval(30)
        while store.isLoading && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(store.exportProject.metadata.title == "第一个项目")
    }

    @Test func adoptingExportedFileDoesNotRewriteDiskFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("exported.kairo")

        let store = makeStore()
        store.save(to: url)
        let original = try Data(contentsOf: url)
        store.dispatch(.setProjectTitle("导出前修改"))
        #expect(store.hasUnsavedChanges)
        // 生产路径：面板打开时记录版本；导出完成后内容仍是最新，只回填路径。
        store.beginExport()

        store.rememberSaveURL(url)

        #expect(!store.hasUnsavedChanges)
        #expect(store.projectURL?.standardizedFileURL == url.standardizedFileURL)
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func exportDuringEditFallsBackToDirectSave() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-export-stale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("exported.kairo")

        let store = makeStore()
        store.save(to: url)
        let original = try Data(contentsOf: url)
        store.beginExport()
        // 面板打开期间继续编辑：导出器写的快照已过期，完成时应以内存为准重写。
        store.dispatch(.setProjectTitle("面板打开后修改"))
        #expect(store.hasUnsavedChanges)

        store.rememberSaveURL(url)

        #expect(!store.hasUnsavedChanges)
        #expect(try Data(contentsOf: url) != original)
        let reloaded = makeStore()
        reloaded.open(url: url)
        #expect(reloaded.exportProject.metadata.title == "面板打开后修改")
    }

    @Test func fieldEditorUndoIsInertWithoutKeyWindow() {
        #expect(!FieldEditorUndo.perform(redo: false))
        #expect(!FieldEditorUndo.perform(redo: true))
    }

    @Test func unrulyExternalFileIsNotRetriedRepeatedly() throws {
        let store = makeStore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-broken-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("broken.kairo")

        store.save(to: url)
        try Data("not a kairo file".utf8).write(to: url)

        store.checkExternalUpdate()
        #expect(store.alertMessage != nil)
        store.alertMessage = nil

        store.checkExternalUpdate()
        #expect(store.alertMessage == nil)
    }

    @Test func selectingElsewhereRestoresTemporarilySuspendedFilter() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")
        store.dispatch(.setFilter("发布"))
        #expect(store.viewState.filterText == "发布")

        store.dispatch(.reveal(backend.id))
        #expect(store.viewState.filterText.isEmpty)

        let other = try task(store, "发布 v1.0")
        store.dispatch(.select(other.id))
        #expect(store.viewState.filterText == "发布")
    }

    // MARK: - 视图偏好持久化

    @Test func openAsyncLoadsProjectAndClearsLoadingState() async throws {
        let store = makeStore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-async-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("async.kairo")

        store.save(to: url)
        #expect(store.alertMessage == nil)

        let reopened = makeStore()
        reopened.openAsync(url: url)
        #expect(reopened.isLoading)

        for _ in 0..<3000 where reopened.isLoading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(!reopened.isLoading)
        #expect(!reopened.showsLoadingSkeleton)
        #expect(reopened.alertMessage == nil)
        #expect(reopened.projectURL?.standardizedFileURL == url.standardizedFileURL)
        #expect(reopened.exportProject.tasks.count == store.exportProject.tasks.count)
    }

    @Test func viewPreferencesPersistAcrossStoresButModeDoesNot() {
        let suite = "kairo.apptests.preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = WorkspaceStore(defaults: defaults)
        first.dispatch(.setMode(.outline))
        first.dispatch(.setOutlineWidth(480))
        first.dispatch(.setOutlineVisible(false))
        first.dispatch(.setZoom(.day))
        first.dispatch(.setInspectorWidth(360))
        first.dispatch(.setInspectorTab(.violations))
        first.dispatch(.setExpanded([]))

        let second = WorkspaceStore(defaults: defaults)
        #expect(second.viewState.mode == .plan)
        #expect(second.viewState.outlineWidth == 480)
        #expect(!second.viewState.outlineVisible)
        #expect(second.viewState.zoom == .day)
        #expect(second.viewState.inspectorWidth == 360)
        #expect(second.viewState.inspectorTab == .violations)
        #expect(second.viewState.expandedTaskIDs.isEmpty)

        second.dispatch(.setOutlineVisible(true))
        #expect(second.viewState.outlineVisible)
    }

    @Test func hidingOutlineGivesCanvasFullWidth() {
        let store = makeStore()

        store.dispatch(.setOutlineVisible(false))

        #expect(!store.viewState.outlineVisible)
        // 大纲隐藏后画布占满主区：快照甘特窗口按全宽视口生成。
        #expect(store.snapshot.gantt.bars.count == store.snapshot.outline.rows.count)
    }

    @Test func outlineColumnsScaleWithWidth() {
        // 600pt 基准：不压缩。
        let base = OutlineColumnLayout(
            columns: OutlineColumn.visibleColumns(outlineWidth: 600),
            totalWidth: 600,
            focused: false
        )
        #expect(base.width(of: .assignee) == 76)

        // 收窄到 360pt：固定列按 0.6 下限压缩，标题吃剩余宽度。
        let narrow = OutlineColumnLayout(
            columns: OutlineColumn.visibleColumns(outlineWidth: 360),
            totalWidth: 360,
            focused: false
        )
        #expect(narrow.width(of: .status) == 18 * 0.6)
        let fixedSum = narrow.columns
            .filter { $0 != .title }
            .reduce(0.0) { $0 + narrow.width(of: $1) }
        #expect(abs(narrow.width(of: .title) - (360 - fixedSum)) < 0.001)
        #expect(narrow.width(of: .title) >= 120)

        // 聚焦标签栏不压缩。
        let focused = OutlineColumnLayout(
            columns: [.status, .violation, .title],
            totalWidth: 180,
            focused: true
        )
        #expect(focused.width(of: .status) == 18)
    }

    // MARK: - 前置列

    @Test func predecessorColumnSetsDependencyByIDPrefix() throws {
        let store = makeStore()
        let backend = try task(store, "搭建 CI 流水线")
        let frontend = try task(store, "实现搜索后端")

        store.dispatch(.setPredecessors(frontend.id, "\(String(backend.id.uuidString.prefix(4))):ss:1"))

        let dependencies = try #require(
            store.exportProject.tasks.first { $0.id == frontend.id }
        ).dependencies
        #expect(dependencies.count == 1)
        #expect(dependencies[0].predecessorID == backend.id)
        #expect(dependencies[0].type == .ss)
        #expect(dependencies[0].lagDays == 1)
        // US-E4-01-C4：前置列以大纲编号形式展示（搭建 CI 流水线 = 编号 8）。
        let row = try row(store, "实现搜索后端")
        #expect(row.predecessorsText.hasPrefix("8:"))
    }

    @Test func predecessorColumnAcceptsOutlineNumber() throws {
        let store = makeStore()
        let backend = try task(store, "搭建 CI 流水线") // 编号 8
        let frontend = try task(store, "实现搜索后端") // 编号 1

        // US-E4-01-C1：纯数字大纲编号。
        store.dispatch(.setPredecessors(frontend.id, "8"))
        var dependencies = try #require(
            store.exportProject.tasks.first { $0.id == frontend.id }
        ).dependencies
        #expect(dependencies.map(\.predecessorID) == [backend.id])

        // US-E4-01-C2：编号 + 依赖规格后缀。
        store.dispatch(.setPredecessors(frontend.id, "8:ss:1"))
        dependencies = try #require(
            store.exportProject.tasks.first { $0.id == frontend.id }
        ).dependencies
        #expect(dependencies.count == 1)
        #expect(dependencies[0].predecessorID == backend.id)
        #expect(dependencies[0].type == .ss)
        #expect(dependencies[0].lagDays == 1)
    }

    @Test func predecessorColumnAcceptsNestedOutlineNumber() throws {
        let store = makeStore()
        let review = try task(store, "Code Review 搜索模块")
        _ = try task(store, "实现搜索后端") // 占位保持 spec 大纲编号为 10
        let spec = try task(store, "撰写技术方案文档") // 编号 10

        // 把 review 缩进为 backend 子项 → 大纲编号 1.1。
        store.dispatch(.select(review.id))
        store.dispatch(.indent(review.id))

        store.dispatch(.setPredecessors(spec.id, "1.1"))
        let dependencies = try #require(
            store.exportProject.tasks.first { $0.id == spec.id }
        ).dependencies
        #expect(dependencies.map(\.predecessorID) == [review.id])
    }

    @Test func predecessorColumnMixesOutlineNumberAndIDPrefix() throws {
        let store = makeStore()
        let backend = try task(store, "搭建 CI 流水线") // 编号 8
        let design = try task(store, "设计首页原型") // 编号 4
        let frontend = try task(store, "实现搜索后端")

        // US-E4-01-C3：同一输入中编号与 ID 前缀混用（顿号分隔）。
        store.dispatch(.setPredecessors(
            frontend.id, "8、\(String(design.id.uuidString.prefix(4)))"
        ))
        let dependencies = try #require(
            store.exportProject.tasks.first { $0.id == frontend.id }
        ).dependencies
        #expect(Set(dependencies.map(\.predecessorID)) == [backend.id, design.id])
    }

    @Test func predecessorColumnReportsHiddenOrUnknownNumber() throws {
        let store = makeStore()
        let frontend = try task(store, "实现搜索后端")
        let review = try task(store, "Code Review 搜索模块")
        let backend = try task(store, "实现搜索后端")

        // 不存在的编号 → 提示可能被折叠或筛选隐藏。
        store.dispatch(.setPredecessors(frontend.id, "99"))
        #expect(store.alertMessage == I18n.t(
            "error.dependency.predecessor_hidden",
            "Predecessor not found: %1$@ (the task may be collapsed or filtered out)",
            "99"
        ))
        store.alertMessage = nil

        // 折叠群组后其子任务编号不可见 → 同样提示。
        store.dispatch(.select(review.id))
        store.dispatch(.indent(review.id))
        store.dispatch(.toggleExpanded(backend.id))
        store.dispatch(.setPredecessors(backend.id, "1.1"))
        #expect(store.alertMessage == I18n.t(
            "error.dependency.predecessor_hidden",
            "Predecessor not found: %1$@ (the task may be collapsed or filtered out)",
            "1.1"
        ))
    }

    @Test func predecessorColumnReplacesWholeSet() throws {
        let store = makeStore()
        let first = try task(store, "搭建 CI 流水线")
        let second = try task(store, "设计首页原型")
        let target = try task(store, "实现搜索后端")

        store.dispatch(.setPredecessors(target.id, String(first.id.uuidString.prefix(4))))
        store.dispatch(.setPredecessors(target.id, "\(String(second.id.uuidString.prefix(4))):ff"))

        let dependencies = try #require(
            store.exportProject.tasks.first { $0.id == target.id }
        ).dependencies
        #expect(dependencies.count == 1)
        #expect(dependencies[0].predecessorID == second.id)
        #expect(dependencies[0].type == .ff)
    }

    @Test func predecessorColumnClearsWhenEmpty() throws {
        let store = makeStore()
        let backend = try task(store, "搭建 CI 流水线")
        let frontend = try task(store, "实现搜索后端")

        store.dispatch(.setPredecessors(frontend.id, String(backend.id.uuidString.prefix(4))))
        store.dispatch(.setPredecessors(frontend.id, "  "))

        let dependencies = try #require(
            store.exportProject.tasks.first { $0.id == frontend.id }
        ).dependencies
        #expect(dependencies.isEmpty)
    }

    @Test func predecessorColumnRejectsCycleAndUnknownID() throws {
        let store = makeStore()
        let backend = try task(store, "搭建 CI 流水线")
        let frontend = try task(store, "实现搜索后端")

        store.dispatch(.setPredecessors(frontend.id, String(backend.id.uuidString.prefix(4))))
        #expect(store.alertMessage == nil)

        // 成环：后继反过来指向前驱。
        store.dispatch(.setPredecessors(backend.id, String(frontend.id.uuidString.prefix(4))))
        #expect(store.alertMessage == I18n.t(
            "error.dependency.cycle",
            "Adding this dependency would form a cycle: %1$@",
            String(frontend.id.uuidString.prefix(4))
        ))
        store.alertMessage = nil
        let unchanged = try #require(
            store.exportProject.tasks.first { $0.id == backend.id }
        ).dependencies
        #expect(unchanged.isEmpty)

        // 未知 ID 与自依赖。
        store.dispatch(.setPredecessors(frontend.id, "ZZZZ"))
        #expect(store.alertMessage == I18n.t(
            "error.dependency.predecessor_not_found",
            "Predecessor not found: %1$@",
            "ZZZZ"
        ))
        store.alertMessage = nil
        store.dispatch(.setPredecessors(frontend.id, String(frontend.id.uuidString.prefix(4))))
        #expect(store.alertMessage == I18n.t("error.dependency.self", "A task cannot depend on itself"))
    }

    // MARK: - 外部更新

    @Test func externalChangeWithUnsavedEditsShowsBanner() throws {
        let store = makeStore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-external-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("external.kairo")

        store.save(to: url)
        store.dispatch(.createTask(parentID: nil, kind: .task))
        #expect(store.hasUnsavedChanges)

        try rewriteExternally(url, title: "外部标题")
        store.checkExternalUpdate()

        #expect(store.externalUpdatePending)
        #expect(store.exportProject.metadata.title == I18n.t("alert.project.default_title", "Untitled Project"))

        store.dispatch(.keepLocal)
        #expect(!store.externalUpdatePending)
        #expect(store.hasUnsavedChanges)
    }

    @Test func externalChangeWithoutLocalEditsReloadsAutomatically() throws {
        let store = makeStore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-external-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("external.kairo")

        store.save(to: url)
        #expect(!store.hasUnsavedChanges)

        try rewriteExternally(url, title: "外部标题")
        store.checkExternalUpdate()

        #expect(!store.externalUpdatePending)
        #expect(store.exportProject.metadata.title == "外部标题")
        let mtime = try #require(
            try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        )
        #expect(store.notice == I18n.t(
            "alert.external_update_loaded",
            "External update loaded at %1$@",
            Display.time(mtime)
        ))
    }

    /// 用独立会话重写磁盘文件，模拟其他进程的保存。
    private func rewriteExternally(_ url: URL, title: String) throws {
        Thread.sleep(forTimeInterval: 0.05)
        let writer = makeStore()
        writer.dispatch(.setProjectTitle(title))
        writer.save(to: url)
        #expect(writer.alertMessage == nil)
    }

    // MARK: - 大纲列宽 / 列显隐（F-14-20）

    /// 独立偏好域（同域可跨 store 复用，用于偏好往返与容错解码）。
    private func makePreferencesDefaults() -> UserDefaults {
        let suite = "kairo.apptests.outlinecolumns.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// 直接写入偏好 JSON：模拟旧版本数据 / 损坏数据。
    private func writePreferences(_ json: String, to defaults: UserDefaults) {
        defaults.set(Data(json.utf8), forKey: WorkspaceStore.preferencesKey)
    }

    /// 列宽写入按 `widthRange` 夹取：图标列 10–60、序号 18–80、文本列 24–320；边界值原样保留。
    @Test func setOutlineColumnWidthClampsToPerColumnRange() {
        let store = makeStore(seedsDemoData: false)

        #expect(store.viewState.outlineColumnWidths.isEmpty)

        store.dispatch(.setOutlineColumnWidth(.start, 500))
        #expect(store.viewState.outlineColumnWidths["start"] == 320)

        store.dispatch(.setOutlineColumnWidth(.start, 1))
        #expect(store.viewState.outlineColumnWidths["start"] == 24)

        store.dispatch(.setOutlineColumnWidth(.start, 320))
        #expect(store.viewState.outlineColumnWidths["start"] == 320, "上界本身不夹取")

        // 窄图标列：状态/违例上限 60、下限 10（覆盖 0.6 压缩宽）。
        store.dispatch(.setOutlineColumnWidth(.status, 500))
        #expect(store.viewState.outlineColumnWidths["status"] == 60)
        store.dispatch(.setOutlineColumnWidth(.status, 0))
        #expect(store.viewState.outlineColumnWidths["status"] == 10)
        store.dispatch(.setOutlineColumnWidth(.violation, -5))
        #expect(store.viewState.outlineColumnWidths["violation"] == 10)

        // 序号列：18–80（默认 30 与压缩宽 18 都在区间内）。
        store.dispatch(.setOutlineColumnWidth(.number, 500))
        #expect(store.viewState.outlineColumnWidths["number"] == 80)

        // 文本列（前置/开始/结束/持续/负责人/完成）共用 24–320。
        store.dispatch(.setOutlineColumnWidth(.duration, 10))
        #expect(store.viewState.outlineColumnWidths["duration"] == 24)
    }

    /// `nil` 与非有限值都表示「回落默认宽」：删除覆盖值，不留 NaN/∞ 给布局。
    @Test func setOutlineColumnWidthNilOrNonFiniteClearsOverride() {
        let store = makeStore(seedsDemoData: false)

        store.dispatch(.setOutlineColumnWidth(.start, 140))
        #expect(store.viewState.outlineColumnWidths["start"] == 140)
        store.dispatch(.setOutlineColumnWidth(.start, nil))
        #expect(store.viewState.outlineColumnWidths["start"] == nil, "nil = 双击手柄复位，删除覆盖值")

        store.dispatch(.setOutlineColumnWidth(.finish, 150))
        store.dispatch(.setOutlineColumnWidth(.finish, Double.nan))
        #expect(store.viewState.outlineColumnWidths["finish"] == nil, "NaN 无法夹取，按复位处理")

        store.dispatch(.setOutlineColumnWidth(.duration, 100))
        store.dispatch(.setOutlineColumnWidth(.duration, Double.infinity))
        #expect(store.viewState.outlineColumnWidths["duration"] == nil, "∞ 无法夹取，按复位处理")
    }

    /// 列宽/显隐是视图偏好：与大纲整体宽度一致，不进撤销栈、不把项目标记为已修改。
    @Test func outlineColumnActionsDoNotPushUndoPoints() {
        let store = makeStore(seedsDemoData: false)
        let depthBefore = store.undoDepthForTesting
        let dirtyBefore = store.hasUnsavedChanges

        store.dispatch(.setOutlineColumnWidth(.start, 140))
        #expect(store.viewState.outlineColumnWidths["start"] == 140)
        #expect(store.undoDepthForTesting == depthBefore, "列宽写入不产生撤销点")

        store.dispatch(.toggleOutlineColumn(.start))
        #expect(store.viewState.hiddenOutlineColumns == ["start"])
        #expect(store.undoDepthForTesting == depthBefore, "列显隐不产生撤销点")

        store.dispatch(.setOutlineColumnWidth(.start, nil))
        #expect(store.undoDepthForTesting == depthBefore, "复位不产生撤销点")
        #expect(store.hasUnsavedChanges == dirtyBefore, "视图偏好不得把项目标记为已修改")
    }

    /// 弹性列（任务说明）不接受宽度覆盖：布局恒按余量计算，写入只会留下死状态。
    @Test func setOutlineColumnWidthRejectsFlexibleTitleColumn() {
        let store = makeStore(seedsDemoData: false)
        store.dispatch(.setOutlineColumnWidth(.title, 200))
        #expect(store.viewState.outlineColumnWidths["title"] == nil, "弹性列宽度请求应被拒绝")
    }

    /// `toggleOutlineColumn` 切换可配置列；序号/任务说明固定显示，请求被直接拒绝。
    @Test func toggleOutlineColumnFlipsHiddenAndRejectsFixedColumns() {
        let store = makeStore(seedsDemoData: false)
        #expect(store.viewState.hiddenOutlineColumns.isEmpty)

        store.dispatch(.toggleOutlineColumn(.start))
        #expect(store.viewState.hiddenOutlineColumns == ["start"])
        store.dispatch(.toggleOutlineColumn(.start))
        #expect(store.viewState.hiddenOutlineColumns.isEmpty, "再次切换恢复显示")

        // 多列互不影响。
        store.dispatch(.toggleOutlineColumn(.predecessors))
        store.dispatch(.toggleOutlineColumn(.progress))
        #expect(store.viewState.hiddenOutlineColumns == ["predecessors", "progress"])
        store.dispatch(.toggleOutlineColumn(.predecessors))
        #expect(store.viewState.hiddenOutlineColumns == ["progress"])

        // 固定列：无效果（不改状态）。
        store.dispatch(.toggleOutlineColumn(.number))
        store.dispatch(.toggleOutlineColumn(.title))
        #expect(store.viewState.hiddenOutlineColumns == ["progress"], "序号/任务说明不得被隐藏")
    }

    /// 隐藏偏好下发到快照列集合（视图与 Presenter 同源）：固定列忽略隐藏，可配置列生效。
    @Test func snapshotColumnsFollowHiddenPreferences() {
        let store = makeStore()
        #expect(store.viewState.outlineWidth == 600, "默认大纲宽度下所有列均可显示")
        #expect(store.snapshot.outline.columns.contains(.start))
        #expect(store.snapshot.outline.columns.contains(.number))

        store.dispatch(.toggleOutlineColumn(.start))
        #expect(!store.snapshot.outline.columns.contains(.start))
        #expect(store.snapshot.outline.columns.contains(.finish), "隐藏只影响被切换那一列")
        #expect(store.snapshot.outline.columns.contains(.number), "序号固定显示")

        store.dispatch(.toggleOutlineColumn(.number))
        #expect(store.snapshot.outline.columns.contains(.number), "隐藏序号请求被忽略")

        store.dispatch(.toggleOutlineColumn(.start))
        #expect(store.snapshot.outline.columns.contains(.start), "取消隐藏后恢复")
    }

    /// 「显示/隐藏X列」命令（视图菜单）与表头右键菜单同源：动作落到同一个 toggle。
    @Test func outlineColumnCommandsToggleFromCatalog() throws {
        let store = makeStore(seedsDemoData: false)
        let commands = makeCatalog(store)

        #expect(try command(commands, "view.outlineColumn.start").title == I18n.t(
            "menu.view.outline_column",
            "Show/Hide %1$@ Column",
            Display.outlineColumnTitle(.start)
        ))
        #expect(!commands.contains { $0.id == "view.outlineColumn.number" }, "固定列不出现在显隐命令里")
        #expect(!commands.contains { $0.id == "view.outlineColumn.title" }, "固定列不出现在显隐命令里")

        try command(commands, "view.outlineColumn.start").action()
        #expect(store.viewState.hiddenOutlineColumns == ["start"])

        try command(commands, "view.outlineColumn.start").action()
        #expect(store.viewState.hiddenOutlineColumns.isEmpty)
    }

    /// 偏好往返：新 store 读回同一组列宽与隐藏列。
    @Test func outlineColumnPreferencesRoundTripThroughDefaults() {
        let defaults = makePreferencesDefaults()
        let first = WorkspaceStore(defaults: defaults, seedsDemoData: false)
        first.dispatch(.setOutlineColumnWidth(.start, 140))
        first.dispatch(.setOutlineColumnWidth(.assignee, 200))
        first.dispatch(.toggleOutlineColumn(.predecessors))
        #expect(first.viewState.hiddenOutlineColumns == ["predecessors"])

        let second = WorkspaceStore(defaults: defaults, seedsDemoData: false)
        #expect(second.viewState.outlineColumnWidths == ["start": 140, "assignee": 200])
        #expect(second.viewState.hiddenOutlineColumns == ["predecessors"])
        // 读回的偏好进入生效列集合（不只是字段回填）。
        #expect(!second.snapshot.outline.columns.contains(.predecessors))

        // 复位后落盘同样生效：空覆盖写 nil，新 store 回到默认宽。
        second.dispatch(.setOutlineColumnWidth(.start, nil))
        let third = WorkspaceStore(defaults: defaults, seedsDemoData: false)
        #expect(third.viewState.outlineColumnWidths == ["assignee": 200])
    }

    /// `outlineColumnWidths` 类型不符（`"x"`）：该字段整体回落空覆盖，不牵连其它偏好。
    @Test func corruptedOutlineColumnWidthsFallBackWithoutTouchingOtherPreferences() {
        let defaults = makePreferencesDefaults()
        writePreferences(
            """
            {
              "outlineWidth": 480,
              "outlineVisible": true,
              "expandedTaskIDs": [],
              "zoom": "day",
              "usesFitZoom": false,
              "inspectorWidth": 360,
              "inspectorTab": "violations",
              "outlineColumnWidths": {"start": "x"},
              "hiddenOutlineColumns": ["predecessors"]
            }
            """,
            to: defaults
        )

        let store = WorkspaceStore(defaults: defaults, seedsDemoData: false)
        #expect(store.viewState.outlineColumnWidths.isEmpty, "非法宽度字典整字段回落")
        // 同一条 JSON 的其余字段（含另一个新字段）完整保留。
        #expect(store.viewState.hiddenOutlineColumns == ["predecessors"])
        #expect(store.viewState.outlineWidth == 480)
        #expect(store.viewState.zoom == .day)
        #expect(store.viewState.inspectorWidth == 360)
        #expect(store.viewState.inspectorTab == .violations)
    }

    /// 越界/未知列的持久化宽度逐项丢弃，合法项保留（D-016 逐字段容错）。
    @Test func outOfRangePersistedColumnWidthsAreDropped() {
        let defaults = makePreferencesDefaults()
        writePreferences(
            """
            {
              "outlineWidth": 480,
              "outlineColumnWidths": {"start": 500, "finish": 90, "status": 18, "bogus": 100},
              "hiddenOutlineColumns": []
            }
            """,
            to: defaults
        )

        let store = WorkspaceStore(defaults: defaults, seedsDemoData: false)
        // 500 越界（start 区间 40–320）→ 丢弃；bogus 未知列 → 丢弃；合法项保留原值。
        #expect(store.viewState.outlineColumnWidths == ["finish": 90, "status": 18])
        #expect(store.viewState.outlineWidth == 480)
    }

    /// 持久化的隐藏列：未知 rawValue 与固定列（序号/任务说明）在载入时被过滤。
    @Test func persistedHiddenColumnsDropUnknownAndFixedColumns() {
        let defaults = makePreferencesDefaults()
        writePreferences(
            """
            {
              "outlineWidth": 480,
              "outlineColumnWidths": {},
              "hiddenOutlineColumns": ["start", "number", "title", "bogus"]
            }
            """,
            to: defaults
        )

        let store = WorkspaceStore(defaults: defaults, seedsDemoData: false)
        #expect(store.viewState.hiddenOutlineColumns == ["start"])
        #expect(store.viewState.outlineWidth == 480)
    }

    /// 旧偏好 JSON 不含两个新键：载入为「无覆盖、无隐藏」，其余偏好照旧。
    @Test func legacyPreferencesWithoutOutlineColumnKeysStillLoad() {
        let defaults = makePreferencesDefaults()
        writePreferences(
            """
            {
              "outlineWidth": 480,
              "outlineVisible": true,
              "expandedTaskIDs": [],
              "zoom": "week",
              "usesFitZoom": true,
              "inspectorWidth": 320,
              "inspectorTab": "inspector"
            }
            """,
            to: defaults
        )

        let store = WorkspaceStore(defaults: defaults, seedsDemoData: false)
        #expect(store.viewState.outlineColumnWidths.isEmpty)
        #expect(store.viewState.hiddenOutlineColumns.isEmpty)
        #expect(store.viewState.outlineWidth == 480)
        #expect(store.viewState.inspectorWidth == 320)
        #expect(store.viewState.usesFitZoom)
    }
}
