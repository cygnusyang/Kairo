import AppKit
import Foundation
import SwiftUI
import KairoCommands
import KairoCore
import KairoPresentation

/// 应用适配层（ADR-013）：持有会话、视图状态与撤销栈，输出平台中立快照。
///
/// 所有变更经 `KairoSession`；视图只发 `WorkspaceAction`，不读写 `Project`。
@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var snapshot: WorkspaceSnapshot
    @Published private(set) var viewState: WorkspaceViewState
    @Published private(set) var viewport: WorkspaceViewport
    @Published private(set) var saveState: SaveState = .saved
    /// 上次载入产生的警告（语义）：文案由视图按码渲染，Store 不拼自然语言（F-0705）。
    @Published private(set) var loadWarnings: [LoadWarning] = []
    /// 错误提示（会话拒绝、文件读写失败）。
    @Published var alertMessage: String?
    /// 非模态提示（揭示结果、保存失败等）。
    @Published private(set) var notice: String?

    // 壳层共享状态（命令面板 / 查找栏由命令注册表驱动）。
    @Published var showCommandPalette = false
    @Published var showFindBar = false
    @Published var findFocusToken = 0
    @Published var filterBarVisible = true

    @ObservedObject private(set) var find = FindModel()

    /// 锁定检查器时冻结的任务；删除后保留快照用于提示。
    @Published private(set) var lockedTaskID: UUID?
    @Published private(set) var lockedTaskTitle: String?

    /// 删除确认（群组或含子项的任务）。
    struct PendingDeletion: Identifiable {
        var id: UUID { taskID }
        var taskID: UUID
        var title: String
        var affectedCount: Int
    }

    @Published var pendingDeletion: PendingDeletion?

    /// 打开的磁盘文件早于当前格式；保存/另存为后升级并清除（FR-KAIRO-FMT）。
    @Published private(set) var needsFormatUpgrade = false
    /// 磁盘文件已被外部修改且本地存在未保存修改。
    @Published private(set) var externalUpdatePending = false
    /// 有待打开的项目，但当前项目存在未保存修改；等待用户选择保存/丢弃/取消。
    @Published private(set) var pendingOpenURL: URL?
    /// 异步打开进行中；超过 150ms 才显示骨架屏，避免闪烁。
    @Published private(set) var isLoading = false
    @Published private(set) var showsLoadingSkeleton = false

    /// 被「揭示目标」临时挂起的筛选文本。
    private var suspendedFilterText: String?

    private let session: KairoSession
    private let calendar: Calendar
    private let defaults: UserDefaults
    /// 项目文件解码入口；测试可注入受控加载以覆盖载入期间的编辑竞争。
    private let projectLoader: @Sendable (URL) throws -> DecodedProject
    private var monitorTimer: Timer?
    private var knownDiskMtime: Date?
    private var pendingExternalMtime: Date?
    private var acknowledgedMtime: Date?
    /// 外部文件读取失败时的 mtime；相同版本不重复重试与弹窗。
    private var failedExternalMtime: Date?
    private var loadingToken: UUID?
    private var dropExpandTask: Task<Void, Never>?
    private var dropExpandTargetID: UUID?
    /// 打开另存为面板时的会话版本；用于判断导出期间是否又有新修改。
    private var exportRevision: UInt64?
    /// 「保存并打开」触发的升级提示；finishOpen 重置 notice 后恢复一次。
    private var pendingUpgradeNoticeAfterOpen: String?

    /// 文件导出的值快照：随每次刷新更新，避免 SwiftUI body 每次求值都重建。
    private(set) var exportState = ProjectState(
        metadata: ProjectMetadata(), tasks: [], resources: []
    )

    /// 视图偏好在 `UserDefaults` 中的键名；测试按此键读写偏好 JSON。
    static let preferencesKey = "kairo.workspace.preferences.v1"
    // 时刻（外部更新提示）判定为展示格式：走 `Display.time`（本地化），不在这里固定 `HH:mm`（F-0712）。

    /// 持久化的视图偏好；视图模式与筛选不写入（启动固定计划模式）。
    /// 逐字段容错解码（D-016）：任一字段缺失/类型不符只回落该字段默认值，
    /// 不再整体解码失败导致全部偏好回落。
    private struct StoredPreferences: Codable {
        var outlineWidth: Double
        var outlineVisible: Bool?
        var expandedTaskIDs: [UUID]
        var zoom: GanttZoom
        var usesFitZoom: Bool
        /// 自定义日宽（点/天）；旧数据缺省时为 nil，回落档位默认宽度。
        var customDayWidth: Double?
        var windowStart: Date?
        var inspectorWidth: Double
        var inspectorTab: InspectorTab
        /// 大纲列宽覆盖（键 = 列 rawValue）；旧数据缺省时为 nil，全部列用默认宽。
        var outlineColumnWidths: [String: Double]?
        /// 隐藏的大纲列（列 rawValue）；旧数据缺省时为 nil，全部列显示。
        var hiddenOutlineColumns: [String]?

        /// 字段默认值 = `WorkspaceViewState()` 初值（与新建会话一致）。
        init(
            outlineWidth: Double,
            outlineVisible: Bool?,
            expandedTaskIDs: [UUID],
            zoom: GanttZoom,
            usesFitZoom: Bool,
            customDayWidth: Double?,
            windowStart: Date?,
            inspectorWidth: Double,
            inspectorTab: InspectorTab,
            outlineColumnWidths: [String: Double]?,
            hiddenOutlineColumns: [String]?
        ) {
            self.outlineWidth = outlineWidth
            self.outlineVisible = outlineVisible
            self.expandedTaskIDs = expandedTaskIDs
            self.zoom = zoom
            self.usesFitZoom = usesFitZoom
            self.customDayWidth = customDayWidth
            self.windowStart = windowStart
            self.inspectorWidth = inspectorWidth
            self.inspectorTab = inspectorTab
            self.outlineColumnWidths = outlineColumnWidths
            self.hiddenOutlineColumns = hiddenOutlineColumns
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // decodeIfPresent：字段缺失 → 默认值；类型不符（typeMismatch）也按
            // 缺失处理（该字段回落，其余保留）——不让单字段污染整个偏好。
            outlineWidth = (try? container.decodeIfPresent(Double.self, forKey: .outlineWidth))
                ?? WorkspaceViewState().outlineWidth
            outlineVisible = try? container.decodeIfPresent(Bool.self, forKey: .outlineVisible)
            expandedTaskIDs = (try? container.decodeIfPresent([UUID].self, forKey: .expandedTaskIDs))
                ?? []
            zoom = (try? container.decodeIfPresent(GanttZoom.self, forKey: .zoom))
                ?? WorkspaceViewState().zoom
            usesFitZoom = (try? container.decodeIfPresent(Bool.self, forKey: .usesFitZoom))
                ?? WorkspaceViewState().usesFitZoom
            customDayWidth = try? container.decodeIfPresent(Double.self, forKey: .customDayWidth)
            windowStart = try? container.decodeIfPresent(Date.self, forKey: .windowStart)
            inspectorWidth = (try? container.decodeIfPresent(Double.self, forKey: .inspectorWidth))
                ?? WorkspaceViewState().inspectorWidth
            inspectorTab = (try? container.decodeIfPresent(InspectorTab.self, forKey: .inspectorTab))
                ?? WorkspaceViewState().inspectorTab
            outlineColumnWidths = try? container.decodeIfPresent(
                [String: Double].self, forKey: .outlineColumnWidths
            )
            hiddenOutlineColumns = try? container.decodeIfPresent(
                [String].self, forKey: .hiddenOutlineColumns
            )
        }
    }

    private struct UndoEntry {
        var state: ProjectState
        var selectedTaskID: UUID?
        var expandedTaskIDs: Set<UUID>
    }

    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []
    private var lastMergeKey: String?
    private var lastMergeAt: Date = .distantPast

    // MARK: - 初始化

    init(
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        seedsDemoData: Bool = false,
        projectLoader: @escaping @Sendable (URL) throws -> DecodedProject = {
            try KairoFile.read(from: $0)
        }
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        self.calendar = calendar
        self.defaults = defaults
        self.projectLoader = projectLoader

        let session = KairoSession()
        self.session = session
        _ = try? session.createProject(title: I18n.t("alert.project.default_title", "Untitled Project"))
        // AC-1：默认空启动不灌示例数据；seedsDemoData 供测试与旧行为显式启用。
        if seedsDemoData {
            Self.seed(SeedData.makeProject(), into: session)
        }

        let stored = Self.loadPreferences(from: defaults)
        var state = WorkspaceViewState()
        state.expandedTaskIDs = stored.map { Set($0.expandedTaskIDs) }
            ?? Self.allParentIDs(in: session.project?.tasks ?? [])
        if let stored {
            state.outlineWidth = stored.outlineWidth
            if let outlineVisible = stored.outlineVisible {
                state.outlineVisible = outlineVisible
            }
            state.zoom = stored.zoom
            state.usesFitZoom = stored.usesFitZoom
            state.windowStart = stored.windowStart
            state.inspectorWidth = stored.inspectorWidth
            state.inspectorTab = stored.inspectorTab
            // 列宽/显隐（F-14-20）：未知列与越界宽度静默丢弃，不牵连其余偏好（D-016）。
            state.outlineColumnWidths = Self.loadedColumnWidths(stored.outlineColumnWidths)
            state.hiddenOutlineColumns = Self.loadedHiddenColumns(stored.hiddenOutlineColumns)
        }
        // 自定义日宽：载入时归一化（夹取 + 取整 0.1，与写入口径一致，D-012），
        // 并与「适合项目」互斥（自定义优先）。
        if let custom = stored?.customDayWidth.map(Self.committedDayWidth) {
            state.customDayWidth = custom
            state.usesFitZoom = false
        }
        self.viewState = state
        let viewport = WorkspaceViewport(canvasWidth: 760, canvasHeight: 640)
        self.viewport = viewport
        let initialState = (try? session.snapshot())
            ?? ProjectState(metadata: ProjectMetadata(), tasks: [], resources: [])
        self.exportState = initialState
        self.snapshot = Self.makeSnapshot(
            state: initialState,
            session: session,
            viewState: state,
            viewport: viewport,
            saveState: .saved,
            calendar: calendar,
            now: now
        )
        self.saveState = session.hasUnsavedChanges ? .unsaved : .saved

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkExternalUpdate()
            }
        }
        // 菜单跟踪、窗口缩放与滚动期间仍检测外部更新。
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    deinit {
        monitorTimer?.invalidate()
    }

    // MARK: - 派生

    /// 测试观测缝（@testable 消费）：暴露会话以断言缓存行为（如 D-014 排期计数）。
    var sessionForTesting: KairoSession { session }

    /// 测试观测缝（@testable 消费）：撤销栈深度，用于断言被拒绝的动作不产生撤销点。
    var undoDepthForTesting: Int { undoStack.count }

    var projectURL: URL? { session.projectURL }
    var hasUnsavedChanges: Bool { session.hasUnsavedChanges }
    var selection: UUID? { viewState.selectedTaskID }

    /// 仅深链解析等主线程内部逻辑使用；视图不得读取。
    var exportProject: Project { session.project ?? Project() }

    /// 文件导出的值快照在 `refresh()` 中更新；FileDocument 可能在后台线程编码，不得传活模型。

    /// 锁定选择发生漂移（真实选择与锁定任务不同）。
    var inspectorSelectionDrift: Bool {
        viewState.inspectorLocked
            && lockedTaskID != nil
            && viewState.selectedTaskID != lockedTaskID
    }

    var selectedTaskTitle: String? {
        guard let id = viewState.selectedTaskID else { return nil }
        return session.project?.tasksByID[id]?.title
    }

    // MARK: - 刷新

    func refresh(now: Date = Date()) {
        if saveState != .failed {
            saveState = session.hasUnsavedChanges ? .unsaved : .saved
        }
        let state = (try? session.snapshot())
            ?? ProjectState(metadata: ProjectMetadata(), tasks: [], resources: [])
        exportState = state
        snapshot = Self.makeSnapshot(
            state: state,
            session: session,
            viewState: inspectorState(for: viewState),
            viewport: viewport,
            saveState: saveState,
            calendar: calendar,
            now: now
        )
        // 锁定时检查器使用冻结任务；状态栏仍显示真实选择。
        if viewState.inspectorLocked, let title = selectedTaskTitle {
            snapshot.statusBar.selectionSummary = title
        }
        savePreferences()
    }

    private func inspectorState(for state: WorkspaceViewState) -> WorkspaceViewState {
        guard state.inspectorLocked, let lockedTaskID else { return state }
        var copy = state
        copy.selectedTaskID = lockedTaskID
        return copy
    }

    private static func makeSnapshot(
        state: ProjectState,
        session: KairoSession,
        viewState: WorkspaceViewState,
        viewport: WorkspaceViewport,
        saveState: SaveState,
        calendar: Calendar,
        now: Date
    ) -> WorkspaceSnapshot {
        // 排期走会话缓存（D-014）：只有任务/元数据写操作会置空缓存，
        // 纯视图动作（日宽调整、面板开合等）命中缓存不重算排期。
        let schedule = (try? session.scheduleOrCompute()) ?? session.lastSchedule
        let violations = schedule.map {
            ViolationEngine.check(result: $0, tasks: state.tasks)
        } ?? []
        return WorkspacePresenter.make(
            state: state,
            schedule: schedule,
            violations: violations,
            viewState: viewState,
            viewport: viewport,
            calendar: calendar,
            locale: Locale.current, // TODO(F-0706): 由语言设置注入
            now: now,
            saveState: saveState
        )
    }

    // MARK: - 视图状态

    func setViewport(canvasWidth: Double, canvasHeight: Double) {
        let width = max(canvasWidth, 1)
        let height = max(canvasHeight, 1)
        guard abs(width - viewport.canvasWidth) > 0.5
                || abs(height - viewport.canvasHeight) > 0.5 else { return }
        viewport = WorkspaceViewport(canvasWidth: width, canvasHeight: height)
        refresh()
    }

    func clearNotice() {
        notice = nil
    }

    // MARK: - 动作路由

    func dispatch(_ action: WorkspaceAction) {
        switch action {
        case .select(let id):
            restoreSuspendedFilterIfNeeded(selecting: id)
            if id != viewState.highlightedTaskID {
                viewState.highlightedTaskID = nil
            }
            viewState.selectedTaskID = id
            refresh()

        case .reveal(let id):
            reveal(id)

        case .highlight(let id):
            viewState.highlightedTaskID = id
            refresh()

        case .copyTaskLink(let id):
            copyTaskLink(id)

        case .toggleExpanded(let id):
            mutateView {
                if $0.expandedTaskIDs.contains(id) {
                    $0.expandedTaskIDs.remove(id)
                } else {
                    $0.expandedTaskIDs.insert(id)
                }
            }

        case .setExpanded(let ids):
            mutateView { $0.expandedTaskIDs = ids }

        case .setMode(let mode):
            mutateView {
                $0.mode = mode
                if mode == .outline { $0.chartFocused = false }
            }

        case .toggleChartFocus:
            mutateView {
                if $0.mode == .outline {
                    $0.mode = .plan
                    $0.chartFocused = true
                } else {
                    $0.chartFocused.toggle()
                }
            }

        case .setZoom(let zoom):
            // 预设档位与自定义日宽互斥：选预设即回落默认宽度。
            mutateView {
                $0.zoom = zoom
                $0.usesFitZoom = false
                $0.customDayWidth = nil
            }

        case .setFitZoom(let enabled):
            // fit 与自定义互斥（最后写入者胜）：开启 fit 即清空自定义。
            mutateView {
                $0.usesFitZoom = enabled
                if enabled {
                    $0.windowStart = nil
                    $0.customDayWidth = nil
                }
            }

        case .setCustomDayWidth(let width):
            // 手动调宽度自动退出「适合项目」；越界值在此夹取，提交值取整到 0.1。
            mutateView {
                $0.customDayWidth = Self.committedDayWidth(width)
                $0.usesFitZoom = false
            }

        case .nudgeCustomDayWidth(let delta):
            // 基准 = 当前生效日宽（fit 模式下取 fit 宽度），结果再夹取并取整到 0.1。
            let base = snapshot.gantt.dayWidth
            mutateView {
                $0.customDayWidth = Self.committedDayWidth(base + delta)
                $0.usesFitZoom = false
            }

        case .clearCustomDayWidth:
            // 清除自定义：回落到当前档位默认宽度（fit 开启时回落到 fit 宽度）。
            mutateView {
                $0.customDayWidth = nil
            }

        case .panWindow(let date):
            mutateView {
                $0.windowStart = calendar.startOfDay(for: date)
                $0.usesFitZoom = false
            }

        case .goToToday:
            mutateView {
                let today = calendar.startOfDay(for: Date())
                $0.windowStart = today.addingTimeInterval(-7 * 86_400)
                $0.usesFitZoom = false
            }

        case .setFilter(let text):
            suspendedFilterText = nil
            mutateView {
                $0.filterText = text
                $0.revealStatus = nil
            }

        case .toggleCriticalPath:
            mutateView { $0.showCriticalPath.toggle() }

        case .toggleBarLabels:
            mutateView { $0.showBarLabels.toggle() }

        case .setInspectorVisible(let visible):
            mutateView {
                $0.inspectorVisible = visible
                if !visible { $0.inspectorLocked = false }
            }
            if !visible {
                lockedTaskID = nil
                lockedTaskTitle = nil
            }

        case .setInspectorTab(let tab):
            mutateView {
                $0.inspectorTab = tab
                $0.inspectorVisible = true
            }

        case .setInspectorLocked(let locked):
            if locked {
                lockedTaskID = viewState.selectedTaskID
                lockedTaskTitle = selectedTaskTitle
            } else {
                lockedTaskID = nil
                lockedTaskTitle = nil
            }
            mutateView { $0.inspectorLocked = locked }

        case .setInspectorWidth(let width):
            mutateView { $0.inspectorWidth = min(max(width, 280), 420) }

        case .setOutlineVisible(let visible):
            mutateView { $0.outlineVisible = visible }

        case .setOutlineWidth(let width):
            mutateView { $0.outlineWidth = min(max(width, 320), 640) }

        case .setOutlineColumnWidth(let column, let width):
            setOutlineColumnWidth(column, width)

        case .toggleOutlineColumn(let column):
            toggleOutlineColumn(column)

        case .createTask(let parentID, let kind):
            createTask(kind: kind, parentID: parentID)

        case .createSibling(let id):
            createSibling(after: id)

        case .rename(let id, let title):
            update(id: id, mergeKey: "rename-\(id)") {
                var patch = TaskPatch()
                patch.title = title
                try self.session.updateTask(id: id, patch: patch)
            }

        case .setPriority(let id, let priority):
            update(id: id, mergeKey: "priority-\(id)") {
                var patch = TaskPatch()
                patch.priority = priority
                try self.session.updateTask(id: id, patch: patch)
            }

        case .setNotes(let id, let notes):
            update(id: id, mergeKey: "notes-\(id)") {
                var patch = TaskPatch()
                patch.notes = notes
                try self.session.updateTask(id: id, patch: patch)
            }

        case .setStatus(let id, let status):
            update(id: id, mergeKey: "status-\(id)") {
                try self.session.statusUpdate(id: id, status: status)
            }

        case .setProgress(let id, let progress):
            update(id: id, mergeKey: "progress-\(id)") {
                try self.session.statusUpdate(id: id, progress: min(max(progress, 0), 1))
            }

        case .setDueDate(let id, let date):
            update(id: id, mergeKey: "due-\(id)") {
                var patch = TaskPatch()
                patch.dueDate = date.map(FieldPatch.set) ?? .clear
                try self.session.updateTask(id: id, patch: patch)
            }

        case .setAssignee(let id, let name):
            update(id: id, mergeKey: "assignee-\(id)") {
                var patch = TaskPatch()
                patch.assignee = name.map(FieldPatch.set) ?? .clear
                try self.session.updateTask(id: id, patch: patch)
            }

        case .setDuration(let id, let days):
            update(id: id, mergeKey: "duration-\(id)") {
                var patch = TaskPatch()
                patch.durationDays = days.map(FieldPatch.set) ?? .clear
                try self.session.updateTask(id: id, patch: patch)
            }

        case .setTaskStart(let id, let date):
            // 日粒度归一落在 Store（AC-S8-01 / M-6）：画布、CLI、内联等其它入口不再各自归一，
            // 系统日历是唯一口径来源，文件里不出现带时分秒的 startDate。
            update(id: id, mergeKey: "task-start-\(id)") {
                var patch = TaskPatch()
                patch.startDate = date.map {
                    FieldPatch.set(ScheduleDateMath.startOfDay($0, calendar: self.calendar))
                } ?? .clear
                try self.session.updateTask(id: id, patch: patch)
            }

        case .setTaskFinish(let id, let finish, let start):
            // 「结束」只折算持续时间；两重校验都在 update 之前，任一失败不写库、不产生撤销点。
            // ① 起点必须仍是当前排期起点：快照渲染到点击之间排期可能已被撤销/重做、画布拖拽、
            //    ALAP 重算或外部文件合并改写，用陈旧起点折算会把持续时间算错并静默落到别的结束日。
            guard let currentStart = currentScheduleStart(for: id),
                  ScheduleDateMath.dayOffset(from: currentStart, to: start, calendar: calendar) == 0 else {
                alertMessage = I18n.t("alert.schedule_changed", "The schedule changed; pick the finish date again")
                return
            }
            // ② 结束是排他端点，必须晚于起点。
            guard let duration = ScheduleDateMath.durationDays(start: start, finish: finish) else {
                alertMessage = I18n.t("alert.finish_after_start", "The finish date must be later than the start date")
                return
            }
            update(id: id, mergeKey: "task-finish-\(id)") {
                var patch = TaskPatch()
                patch.durationDays = .set(duration)
                try self.session.updateTask(id: id, patch: patch)
            }

        case .canvasEditSchedule(let id, let startDate, let durationDays):
            // F-14-09 画布拖拽：同一 mergeKey 在连续节流提交间合并为一步撤销。
            // move 只带 startDate；resize 右端只带 durationDays；resize 左端两者都带。
            let mergeKey = durationDays == nil ? "canvas-move-\(id)" : "canvas-resize-\(id)"
            update(id: id, mergeKey: mergeKey) {
                var patch = TaskPatch()
                if let startDate { patch.startDate = .set(startDate) }
                if let durationDays { patch.durationDays = .set(durationDays) }
                try self.session.updateTask(id: id, patch: patch)
            }

        case .move(let id, let parentID, let index):
            update(id: id, mergeKey: nil) {
                try self.session.moveTask(id: id, toParent: parentID, at: index)
            }

        case .indent(let id):
            pushUndo(mergeKey: nil)
            do {
                _ = try session.indentTask(id: id)
                // 新父级自动展开，缩进后的任务不消失。
                if let parent = session.project?.tasksByID[id]?.parentID {
                    viewState.expandedTaskIDs.insert(parent)
                }
            } catch {
                report(error)
            }
            refresh()

        case .outdent(let id):
            update(id: id, mergeKey: nil) {
                _ = try self.session.outdentTask(id: id)
            }

        case .delete(let id):
            delete(id: id)

        case .addDependency(let taskID, let predecessorID, let type, let lagDays):
            update(id: taskID, mergeKey: nil) {
                try self.session.addDependency(
                    to: taskID, predecessorID: predecessorID, type: type, lagDays: lagDays
                )
            }

        case .removeDependency(let taskID, let predecessorID):
            update(id: taskID, mergeKey: nil) {
                try self.session.removeDependency(from: taskID, predecessorID: predecessorID)
            }

        case .setPredecessors(let taskID, let raw):
            setPredecessors(taskID: taskID, raw: raw)

        case .setProjectTitle(let title):
            mutateProject(mergeKey: "project-title") {
                try self.session.updateProjectMetadata(title: title)
            }

        case .setProjectStart(let date):
            mutateProject(mergeKey: "project-start") {
                try self.session.updateProjectMetadata(
                    projectStart: date.map(FieldPatch.set) ?? .clear
                )
            }

        case .setProjectEnd(let date):
            mutateProject(mergeKey: "project-end") {
                try self.session.updateProjectMetadata(
                    projectEnd: date.map(FieldPatch.set) ?? .clear
                )
            }

        case .setProjectDirection(let direction):
            mutateProject(mergeKey: nil) {
                try self.session.updateProjectMetadata(direction: direction)
            }

        case .undo:
            undo()

        case .redo:
            redo()

        case .save:
            save()

        case .reloadExternal:
            reloadExternal()

        case .keepLocal:
            acknowledgedMtime = pendingExternalMtime
            pendingExternalMtime = nil
            externalUpdatePending = false
            notice = I18n.t("alert.kept_local", "Kept the local version")
        }
    }

    // MARK: - 变更辅助

    /// 提交自定义日宽：先夹取到合法区间，再取整到 0.1。
    ///
    /// 取整放在动作层，保证落盘偏好与状态栏读数一致（核心 `GanttScale.clampDayWidth`
    /// 只做夹取、不做取整，保持核心接受调用方给定的精度）。
    private static func committedDayWidth(_ width: Double) -> Double {
        let clamped = GanttScale.clampDayWidth(width)
        return (clamped * 10).rounded() / 10
    }

    /// 列宽覆盖（F-14-20）：`nil` 删除该列覆盖值（回落默认宽），非 `nil` 夹取后写入。
    ///
    /// 非有限值（NaN/∞）无法夹取，按复位处理，不留越界值给布局。
    /// 列宽是视图偏好，显隐集合不受影响，也不产生撤销点。
    /// 列宽（F-14-20）：应用级视图偏好，与 `.setOutlineWidth` 一致**不进撤销栈**
    /// （撤销栈只存项目快照，记一步空撤销只会清空 redo 且无法真正回滚列宽）。
    private func setOutlineColumnWidth(_ column: OutlineColumn, _ width: Double?) {
        // 弹性列（任务说明）不吃覆盖值：布局恒按余量计算，写入只会留下永不生效的死状态。
        guard OutlineColumnPreferences.isResizable(column) else { return }
        mutateView { state in
            guard let width, width.isFinite else {
                state.outlineColumnWidths.removeValue(forKey: column.rawValue)
                return
            }
            let range = OutlineColumnPreferences.widthRange(for: column)
            state.outlineColumnWidths[column.rawValue] = min(max(width, range.lowerBound), range.upperBound)
        }
    }

    /// 列显隐（F-14-20）：序号/任务说明固定显示，请求直接忽略（不产生撤销点、不改状态）。
    ///
    /// 纯视图偏好，与大纲整体宽度一致：走 `mutateView` 而非 `update`，不进撤销栈。
    private func toggleOutlineColumn(_ column: OutlineColumn) {
        guard !OutlineColumnPreferences.alwaysVisible.contains(column) else { return }
        mutateView { state in
            if state.hiddenOutlineColumns.contains(column.rawValue) {
                state.hiddenOutlineColumns.remove(column.rawValue)
            } else {
                state.hiddenOutlineColumns.insert(column.rawValue)
            }
        }
    }

    private func mutateView(_ change: (inout WorkspaceViewState) -> Void) {
        change(&viewState)
        refresh()
    }

    /// 任务当前排期起点：优先排期结果；未排期（群组/环/无安排）回落到 `startDate` 意图。
    ///
    /// 「结束」字段的折算口径（视图传 `scheduledStart ?? startDate`）在这里复核，
    /// 保证落库的持续时间与用户看到的起点同源。
    private func currentScheduleStart(for id: UUID) -> Date? {
        if let result = try? session.scheduleOrCompute(),
           result.hasSchedule(for: id),
           let scheduled = result.scheduled(id) {
            return scheduled.scheduledStart
        }
        return session.project?.tasksByID[id]?.startDate
    }

    /// 记录撤销点；相同 `mergeKey` 在 500ms 内合并为一步。
    private func pushUndo(mergeKey: String?) {
        let now = Date()
        if let mergeKey, mergeKey == lastMergeKey, now.timeIntervalSince(lastMergeAt) < 0.5,
           !undoStack.isEmpty {
            lastMergeAt = now
            return
        }
        if let state = try? session.snapshot() {
            undoStack.append(UndoEntry(
                state: state,
                selectedTaskID: viewState.selectedTaskID,
                expandedTaskIDs: viewState.expandedTaskIDs
            ))
            if undoStack.count > 50 { undoStack.removeFirst(undoStack.count - 50) }
            redoStack.removeAll()
        }
        lastMergeKey = mergeKey
        lastMergeAt = now
    }

    private func update(
        id: UUID,
        mergeKey: String?,
        _ body: () throws -> Void
    ) {
        pushUndo(mergeKey: mergeKey)
        do {
            try body()
        } catch {
            report(error)
        }
        refresh()
    }

    /// 「前置」列输入 → 依赖集合整体替换（对齐 OmniPlan 的前置任务编辑）。
    ///
    /// 流程：解析 `ID[:类型[:延隔]]` → 前缀解析为 UUID → 值副本上预校验（自依赖、
    /// 成环、重复）→ 求与现有依赖的差集 → 经会话应用；任何一步失败只提示不改数据。
    private func setPredecessors(taskID: UUID, raw: String) {
        let specs = raw
            // 分隔符含半角逗号、空格与表意逗号（U+3001）；用码位写法避开硬编码中文扫描。
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\u{3001}" })
            .filter { !$0.isEmpty }
        guard !specs.isEmpty else {
            clearPredecessors(taskID: taskID)
            return
        }

        // 当前可见行的大纲编号 → 任务 ID（US-E4-01-C1）；折叠/筛选隐藏的行不在其中。
        let outlineNumberByID = Dictionary(
            uniqueKeysWithValues: snapshot.outline.rows.map { ($0.outlineNumber, $0.id) }
        )

        var targets: [UUID: TaskDependency] = [:]
        for spec in specs {
            let parts = spec.split(separator: ":", omittingEmptySubsequences: false)
            guard let idPart = parts.first, !idPart.isEmpty else {
                alertMessage = I18n.t("error.dependency.predecessor_invalid", "Unrecognized predecessor: %1$@", String(spec))
                return
            }
            let type = parts.count > 1 && !parts[1].isEmpty
                ? parts[1].lowercased() : "fs"
            guard let depType = TaskDependency.DependencyType(rawValue: type) else {
                alertMessage = I18n.t("error.dependency.type_invalid", "Unrecognized dependency type: %1$@ (expected fs/ff/ss/sf)", String(spec))
                return
            }
            let lag = parts.count > 2 && !parts[2].isEmpty ? (Double(parts[2]) ?? 0) : 0
            if parts.count > 2, Double(parts[2]) == nil {
                alertMessage = I18n.t("error.dependency.lag_invalid", "Unrecognized lag: %1$@", String(spec))
                return
            }

            let tasks = session.project?.tasks ?? []
            let resolved: UUID
            if idPart.contains(".") || (idPart.allSatisfy(\.isNumber) && idPart.count < 4) {
                // 大纲编号引用（US-E4-01-C1）：含点或 <4 位纯数字按当前可见编号精确匹配；
                // 被折叠/筛选隐藏的任务报 C3 提示，数据不变。
                guard let id = outlineNumberByID[String(idPart)] else {
                    alertMessage = I18n.t("error.dependency.predecessor_hidden", "Predecessor not found: %1$@ (the task may be collapsed or filtered out)", String(idPart))
                    return
                }
                resolved = id
            } else if let id = UUID(uuidString: String(idPart)) {
                resolved = id
            } else {
                // ID 前缀匹配（US-E4-01-C2 混用路径）：≥4 位纯数字先按前缀，失败再回退大纲编号。
                let matches = tasks.filter {
                    $0.id.uuidString.lowercased().hasPrefix(idPart.lowercased())
                }
                if matches.count == 1 {
                    resolved = matches[0].id
                } else if idPart.allSatisfy(\.isNumber) {
                    guard let id = outlineNumberByID[String(idPart)] else {
                        alertMessage = I18n.t("error.dependency.predecessor_hidden", "Predecessor not found: %1$@ (the task may be collapsed or filtered out)", String(idPart))
                        return
                    }
                    resolved = id
                } else {
                    alertMessage = matches.count > 1
                        ? I18n.t("error.dependency.predecessor_ambiguous", "Predecessor ID is not unique: %1$@", String(idPart))
                        : I18n.t("error.dependency.predecessor_not_found", "Predecessor not found: %1$@", String(idPart))
                    return
                }
            }
            if resolved == taskID {
                alertMessage = I18n.t("error.dependency.self", "A task cannot depend on itself")
                return
            }
            let dep = TaskDependency(predecessorID: resolved, type: depType, lagDays: lag)
            if targets[resolved] != nil {
                alertMessage = I18n.t("error.dependency.duplicate", "Duplicate predecessor: %1$@", String(idPart))
                return
            }
            targets[resolved] = dep
        }

        // 值副本上预校验最终集合，避免会话出现「删了一半」的中间态。
        var draft = session.project?.tasks ?? []
        guard let index = draft.firstIndex(where: { $0.id == taskID }) else { return }
        let current = draft[index].dependencies
        var removals: [UUID] = []
        var additions: [TaskDependency] = []
        for dep in current where targets[dep.predecessorID] == nil {
            removals.append(dep.predecessorID)
        }
        for (predecessorID, dep) in targets {
            if let existing = current.first(where: { $0.predecessorID == predecessorID }) {
                if existing.type != dep.type || existing.lagDays != dep.lagDays {
                    removals.append(predecessorID)
                    additions.append(dep)
                }
            } else {
                additions.append(dep)
            }
        }
        for id in removals {
            guard case .success(let updated) = DependencyEditing.remove(
                predecessorID: id, from: taskID, in: draft
            ) else { continue }
            draft = updated
        }
        for dep in additions {
            switch DependencyEditing.add(dep, to: taskID, in: draft) {
            case .success(let updated):
                draft = updated
            case .failure(let error):
                alertMessage = Self.dependencyError(error, id: dep.predecessorID)
                return
            }
        }

        update(id: taskID, mergeKey: nil) {
            for id in removals {
                try self.session.removeDependency(from: taskID, predecessorID: id)
            }
            for dep in additions {
                try self.session.addDependency(
                    to: taskID, predecessorID: dep.predecessorID,
                    type: dep.type, lagDays: dep.lagDays
                )
            }
        }
    }

    /// 清空前置依赖（输入为空时）。
    private func clearPredecessors(taskID: UUID) {
        let current = session.project?.tasks.first { $0.id == taskID }?.dependencies ?? []
        guard !current.isEmpty else { return }
        update(id: taskID, mergeKey: nil) {
            for dep in current {
                try self.session.removeDependency(from: taskID, predecessorID: dep.predecessorID)
            }
        }
    }

    private static func dependencyError(_ error: DependencyEditing.EditError, id: UUID) -> String {
        switch error {
        case .cycle: return I18n.t("error.dependency.cycle", "Adding this dependency would form a cycle: %1$@", String(id.uuidString.prefix(4)))
        case .selfDependency: return I18n.t("error.dependency.self", "A task cannot depend on itself")
        case .predecessorNotFound, .taskNotFound: return I18n.t("error.task.not_found", "Task not found: %1$@", String(id.uuidString.prefix(4)))
        }
    }

    private func mutateProject(mergeKey: String?, _ body: () throws -> Void) {
        pushUndo(mergeKey: mergeKey)
        do {
            try body()
        } catch {
            report(error)
        }
        refresh()
    }

    private func createTask(kind: TaskKind, parentID: UUID?) {
        let title: String
        switch kind {
        case .task: title = I18n.t("outline.new_task.title", "New Task")
        case .group: title = I18n.t("outline.new_group.title", "New Group")
        case .milestone: title = I18n.t("outline.new_milestone.title", "New Milestone")
        }
        let parent = parentID ?? insertionParent()
        pushUndo(mergeKey: nil)
        do {
            let id = try session.addTask(title: title, kind: kind, parentID: parent)
            viewState.selectedTaskID = id
            if let parent { viewState.expandedTaskIDs.insert(parent) }
        } catch {
            report(error)
        }
        refresh()
    }

    /// 在指定任务之后插入同级任务（`⌘↩` 与右键菜单）。
    private func createSibling(after id: UUID) {
        guard let project = session.project,
              let task = project.tasksByID[id] else {
            createTask(kind: .task, parentID: insertionParent())
            return
        }
        let parent = task.parentID
        let siblings = project.tasks.filter { $0.parentID == parent }
        let index = (siblings.firstIndex { $0.id == id } ?? siblings.count - 1) + 1
        pushUndo(mergeKey: nil)
        do {
            let newID = try session.addTask(title: I18n.t("outline.new_task.title", "New Task"), kind: .task, parentID: parent)
            try session.moveTask(id: newID, toParent: parent, at: index)
            viewState.selectedTaskID = newID
            if let parent { viewState.expandedTaskIDs.insert(parent) }
        } catch {
            report(error)
        }
        refresh()
    }

    private func insertionParent() -> UUID? {
        guard let id = viewState.selectedTaskID,
              let task = session.project?.tasksByID[id] else { return nil }
        return task.kind == .group ? id : task.parentID
    }

    /// 依赖选择器条目（不含模型细节，视图不读 `Project`）。
    struct TaskChoice: Identifiable, Hashable {
        var id: UUID
        var title: String
    }

    /// 可作为前驱的候选：排除自身、后代与已有前驱。
    func predecessorCandidates(for taskID: UUID) -> [TaskChoice] {
        guard let project = session.project,
              let task = project.tasksByID[taskID] else { return [] }
        let excluded = OutlineEditor.subtreeIDs(of: taskID, in: project.tasks)
        let existing = Set(task.dependencies.map(\.predecessorID))
        return project.tasks
            .filter { !excluded.contains($0.id) && !existing.contains($0.id) }
            .map { TaskChoice(id: $0.id, title: $0.title) }
    }

    // MARK: - 拖拽重排

    struct MoveTarget: Equatable {
        var parentID: UUID?
        var index: Int
    }

    /// 筛选激活时禁用拖拽重排（计划 §3.4）。
    var allowsDragReorder: Bool {
        viewState.filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 拖到群组行 → 成为最后一个子项；拖到普通行 → 插到其后作为同级。
    ///
    /// 索引按 `OutlineMoving` 的语义计算：移除被拖子树之后的位置。
    func moveTarget(draggedID: UUID, onto targetID: UUID) -> MoveTarget? {
        guard allowsDragReorder,
              draggedID != targetID,
              let project = session.project else { return nil }
        let movingIDs = OutlineEditor.subtreeIDs(of: draggedID, in: project.tasks)
        guard !movingIDs.isEmpty, !movingIDs.contains(targetID) else { return nil }
        let remaining = project.tasks.filter { !movingIDs.contains($0.id) }
        guard let target = remaining.first(where: { $0.id == targetID }) else { return nil }
        if target.kind == .group {
            let index = remaining.filter { $0.parentID == targetID }.count
            return MoveTarget(parentID: targetID, index: index)
        }
        let siblings = remaining.filter { $0.parentID == target.parentID }
        guard let position = siblings.firstIndex(where: { $0.id == targetID }) else {
            return nil
        }
        return MoveTarget(parentID: target.parentID, index: position + 1)
    }

    /// 悬停 600ms 自动展开收合的群组（拖拽重排）；延迟可注入供测试缩短。
    func scheduleDropExpand(on id: UUID, delayNanoseconds: UInt64 = 600_000_000) {
        cancelDropExpand()
        guard let task = session.project?.tasksByID[id],
              task.kind == .group,
              !viewState.expandedTaskIDs.contains(id) else { return }
        dropExpandTargetID = id
        dropExpandTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.viewState.expandedTaskIDs.insert(id)
            self.dropExpandTask = nil
            self.dropExpandTargetID = nil
            self.refresh()
        }
    }

    /// 只取消指定行的待展开计时；其他行的 `dropExited` 不得取消本行。
    func cancelDropExpand(on id: UUID? = nil) {
        if let id, dropExpandTargetID != id { return }
        dropExpandTask?.cancel()
        dropExpandTask = nil
        dropExpandTargetID = nil
    }

    /// 删除入口：叶子任务直接删除；有子项的任务一律确认后级联删除。
    func requestDelete(id: UUID) {
        guard let project = session.project, let task = project.tasksByID[id] else { return }
        let hasChildren = project.tasks.contains { $0.parentID == id }
        if task.kind == .group || hasChildren {
            let affected = OutlineEditor.subtreeIDs(of: id, in: project.tasks).count
            pendingDeletion = PendingDeletion(
                taskID: id, title: task.title, affectedCount: affected
            )
        } else {
            dispatch(.delete(id))
        }
    }

    func confirmPendingDeletion() {
        guard let pending = pendingDeletion else { return }
        pendingDeletion = nil
        dispatch(.delete(pending.taskID))
    }

    private func delete(id: UUID) {
        // 删除后子树已不存在，受影响的 id 必须在删除前计算。
        let removed = session.project.map {
            OutlineEditor.subtreeIDs(of: id, in: $0.tasks)
        } ?? [id]
        pushUndo(mergeKey: nil)
        do {
            _ = try session.deleteTaskCascade(id: id)
            removeFromViewSelection(removed: removed)
        } catch {
            report(error)
        }
        refresh()
    }

    private func removeFromViewSelection(removed: Set<UUID>) {
        if let selected = viewState.selectedTaskID, removed.contains(selected) {
            viewState.selectedTaskID = nil
        }
        if let locked = lockedTaskID, removed.contains(locked) {
            // 保留标题快照，提示「任务已删除」。
            lockedTaskID = nil
            lockedTaskTitle = lockedTaskTitle ?? I18n.t("outline.task.generic", "Task")
        }
        viewState.expandedTaskIDs.subtract(removed)
    }

    // MARK: - 撤销 / 重做

    private func undo() {
        guard let entry = undoStack.popLast() else {
            notice = I18n.t("alert.undo.empty", "Nothing to undo")
            return
        }
        guard let current = try? session.snapshot() else { return }
        redoStack.append(UndoEntry(
            state: current,
            selectedTaskID: viewState.selectedTaskID,
            expandedTaskIDs: viewState.expandedTaskIDs
        ))
        apply(entry)
    }

    private func redo() {
        guard let entry = redoStack.popLast() else {
            notice = I18n.t("alert.redo.empty", "Nothing to redo")
            return
        }
        guard let current = try? session.snapshot() else { return }
        undoStack.append(UndoEntry(
            state: current,
            selectedTaskID: viewState.selectedTaskID,
            expandedTaskIDs: viewState.expandedTaskIDs
        ))
        apply(entry)
    }

    private func apply(_ entry: UndoEntry) {
        do {
            try session.restore(entry.state)
        } catch {
            report(error)
        }
        let existing = Set(entry.state.tasks.map(\.id))
        viewState.selectedTaskID = entry.selectedTaskID.flatMap {
            existing.contains($0) ? $0 : nil
        }
        viewState.expandedTaskIDs = entry.expandedTaskIDs.filter { existing.contains($0) }
        if let locked = lockedTaskID, !existing.contains(locked) { lockedTaskID = nil }
        lastMergeKey = nil
        refresh()
    }

    // MARK: - 揭示目标

    /// 「临时显示」只在被揭示任务保持选中时有效；选择移到别处即恢复原筛选。
    private func restoreSuspendedFilterIfNeeded(selecting id: UUID?) {
        guard let text = suspendedFilterText else { return }
        guard id != viewState.highlightedTaskID else { return }
        suspendedFilterText = nil
        viewState.filterText = text
    }

    /// 展开祖先、必要时临时清除筛选、选中目标；不切换检查器页签。
    func reveal(_ id: UUID) {
        guard let project = session.project else { return }
        guard let task = project.tasksByID[id] else {
            viewState.selectedTaskID = nil
            viewState.highlightedTaskID = nil
            viewState.revealStatus = .missing
            notice = I18n.t("alert.task_deleted", "Task deleted")
            refresh()
            return
        }

        var ancestors: Set<UUID> = []
        var parent = task.parentID
        var hops = 0
        while let current = parent, project.tasksByID[current] != nil, hops <= project.tasks.count {
            ancestors.insert(current)
            parent = project.tasksByID[current]?.parentID
            hops += 1
        }
        viewState.expandedTaskIDs.formUnion(ancestors)

        var status = RevealStatus.visible
        let clauses = AIFilterTranslator.translate(viewState.filterText)
        if !clauses.isEmpty {
            let matched = Set(AIFilterTranslator.apply(clauses: clauses, to: project.tasks).map(\.id))
            if !matched.contains(id) {
                suspendedFilterText = viewState.filterText
                viewState.filterText = ""
                status = .temporarilyShown
            }
        }
        viewState.selectedTaskID = id
        viewState.highlightedTaskID = id
        viewState.revealStatus = status
        switch status {
        case .visible:
            notice = nil
        case .temporarilyShown:
            notice = I18n.t("alert.task_hidden_by_filter", "“%1$@” was hidden by the filter and is now shown temporarily", task.title)
        case .missing:
            break
        }
        refresh()
    }

    // MARK: - 文件

    /// 有待载入的示例项目，但当前项目存在未保存修改；等待用户选择丢弃并载入 / 取消。
    /// 与 `pendingOpenURL` 同款确认流程（AC-3），由视图弹确认对话框。
    @Published private(set) var pendingLoadExample = false

    /// 「文件 → 载入示例项目」（AC-2/AC-3）：无未保存修改时直接用示例数据重建项目内容
    /// （不写磁盘、不自动保存）；有未保存修改时先确认，避免静默丢弃工作。
    func loadExampleProject() {
        guard !session.hasUnsavedChanges else {
            pendingLoadExample = true
            return
        }
        loadExampleNow()
    }

    func cancelPendingLoadExample() {
        pendingLoadExample = false
    }

    func confirmPendingLoadExample() {
        guard pendingLoadExample else { return }
        pendingLoadExample = false
        loadExampleNow()
    }

    /// 载入示例等同「新建示例」：重置为空项目（projectURL 置 nil）再填入示例内容。
    private func loadExampleNow() {
        _ = try? session.createProject(title: I18n.t("alert.project.default_title", "Untitled Project"))
        Self.seed(SeedData.makeProject(), into: session)
        resetViewStateForLoadedProject()
        undoStack.removeAll()
        redoStack.removeAll()
        pendingDeletion = nil
        saveState = .saved
        needsFormatUpgrade = session.needsFormatUpgrade
        notice = I18n.t("alert.example_loaded", "Example project loaded")
        refresh()
    }

    /// 把示例项目内容灌入当前会话项目（不写磁盘；供 init 种子与载入示例共用）。
    /// 静态：init 属性初始化前即可调用。
    private static func seed(_ seed: Project, into session: KairoSession) {
        guard let project = session.project else { return }
        project.metadata.projectStart = seed.metadata.projectStart
        project.metadata.projectEnd = seed.metadata.projectEnd
        project.metadata.direction = seed.metadata.direction
        for task in seed.tasks { project.add(task) }
    }

    @discardableResult
    func open(url: URL) -> Bool {
        do {
            _ = try session.openProject(at: url)
            finishOpen()
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// 文件选择器入口：有未保存修改时先询问，避免静默丢弃工作。
    func openAsync(url: URL) {
        guard !isLoading else {
            // 早退不进入 finishOpen；清理待恢复的升级提示，避免残留到下一次打开。
            pendingUpgradeNoticeAfterOpen = nil
            notice = I18n.t("alert.loading_in_progress", "A project is still loading; try opening again in a moment")
            return
        }
        guard !session.hasUnsavedChanges else {
            pendingOpenURL = url
            return
        }
        startOpenAsync(url: url)
    }

    var canSavePendingOpen: Bool {
        pendingOpenURL != nil && session.projectURL != nil
    }

    func cancelPendingOpen() {
        pendingOpenURL = nil
    }

    func discardChangesAndOpenPending() {
        guard let url = pendingOpenURL else { return }
        pendingOpenURL = nil
        startOpenAsync(url: url)
    }

    func saveAndOpenPending() {
        guard pendingOpenURL != nil else { return }
        let wasUpgrade = session.needsFormatUpgrade
        save()
        guard saveState != .failed else { return }
        if wasUpgrade {
            // finishOpen 会用载入警告重置 notice；升级提示需跨过这次打开保留。
            pendingUpgradeNoticeAfterOpen = I18n.t("alert.upgraded_to", "Upgraded to v%1$ld", KairoFile.currentFormatVersion)
        }
        discardChangesAndOpenPending()
    }

    /// 后台解码，主线程接管；超过 150ms 显示骨架屏。
    private func startOpenAsync(url: URL) {
        guard !isLoading else { return }
        // 载入期间用户仍可编辑旧项目；接管前核对版本，避免静默覆盖新改动。
        let revisionAtStart = session.revision
        let token = UUID()
        loadingToken = token
        isLoading = true
        showsLoadingSkeleton = false

        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard isLoading, loadingToken == token else { return }
            showsLoadingSkeleton = true
        }

        let accessing = url.startAccessingSecurityScopedResource()
        let loader = projectLoader
        Task { [weak self] in
            let loaded: Result<DecodedProject, Error> = await Task.detached(priority: .userInitiated) {
                Result { try loader(url) }
            }.value
            if accessing { url.stopAccessingSecurityScopedResource() }
            guard let self, self.loadingToken == token else { return }
            switch loaded {
            case .success(let decoded) where self.session.revision == revisionAtStart:
                self.session.adoptProject(
                    decoded.project, from: url, formatVersion: decoded.sourceFormatVersion
                )
                self.finishOpen()
            case .success:
                // 载入期间有新编辑：保留当前内容，重新进入保存/丢弃/取消确认。
                self.pendingUpgradeNoticeAfterOpen = nil
                self.pendingOpenURL = url
                self.notice = I18n.t("alert.changed_while_loading", "The project changed while loading; local content was kept. Confirm opening again.")
            case .failure(let error):
                self.pendingUpgradeNoticeAfterOpen = nil
                self.report(error)
            }
            self.isLoading = false
            self.showsLoadingSkeleton = false
            self.loadingToken = nil
        }
    }

    private func finishOpen() {
        loadWarnings = session.loadWarnings
        resetViewStateForLoadedProject()
        undoStack.removeAll()
        redoStack.removeAll()
        pendingDeletion = nil
        pendingOpenURL = nil
        saveState = .saved
        needsFormatUpgrade = session.needsFormatUpgrade
        recordDiskVersion(at: session.projectURL)
        // 升级提示与载入警告同时存在时合并展示，避免丢弃唯一的警告消费点。
        let upgradeNotice = pendingUpgradeNoticeAfterOpen
        pendingUpgradeNoticeAfterOpen = nil
        let warningText = loadWarnings.first.map(Display.loadWarning)
        if let upgradeNotice, let warningText {
            notice = I18n.t("alert.notice.combined", "%1$@; %2$@", upgradeNotice, warningText)
        } else {
            notice = upgradeNotice ?? warningText
        }
        refresh()
    }

    func save(to url: URL? = nil) {
        let wasUpgrade = session.needsFormatUpgrade
        do {
            _ = try session.saveProject(to: url)
            saveState = .saved
            needsFormatUpgrade = session.needsFormatUpgrade
            // 每次保存至多提示一次：保存成功后来源版本即为当前版本。
            if wasUpgrade {
                notice = I18n.t("alert.upgraded_to", "Upgraded to v%1$ld", KairoFile.currentFormatVersion)
            }
            recordDiskVersion(at: session.projectURL)
            refresh()
        } catch {
            saveState = .failed
            report(error)
            refresh()
        }
    }

    /// 复制任务深链（`kairo://task/<id>`），由适配层写入剪贴板。
    func copyTaskLink(_ id: UUID) {
        let link = "kairo://task/\(id.uuidString)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        notice = I18n.t("alert.link_copied", "Task link copied")
    }

    /// 另存为面板的默认文件名（FR-FILE-SAVEAS-2）：有路径沿用文件名，否则按项目标题生成。
    var suggestedSaveFilename: String {
        SaveFilenameSuggestion.suggest(
            currentURL: projectURL,
            title: session.project?.metadata.title ?? ""
        )
    }

    /// 打开另存为面板前记录版本，导出完成时据此判断快照是否仍然最新。
    func beginExport() {
        exportRevision = session.revision
    }

    /// 取消另存为面板：清理导出快照版本，之后的完成回调不再误判快照最新。
    func cancelExport() {
        exportRevision = nil
    }

    /// 另存为完成：文件导出器已写入快照，这里只回填路径并清除脏标记，不重复写文件。
    /// 面板打开期间若又有修改，导出内容已过期，改以内存为准直接写一次。
    func rememberSaveURL(_ url: URL) {
        let revision = exportRevision
        exportRevision = nil
        let wasUpgrade = session.needsFormatUpgrade
        // 未经 beginExport 的调用无法确认导出内容是否最新，直接写内存内容。
        if revision == nil || revision != session.revision {
            save(to: url)
            if wasUpgrade, saveState != .failed {
                notice = I18n.t("alert.saved_as_upgraded", "Saved as a new file and upgraded to v%1$ld", KairoFile.currentFormatVersion)
            }
            return
        }
        session.noteExported(to: url)
        saveState = .saved
        needsFormatUpgrade = session.needsFormatUpgrade
        if wasUpgrade {
            notice = I18n.t("alert.saved_as_upgraded", "Saved as a new file and upgraded to v%1$ld", KairoFile.currentFormatVersion)
        }
        recordDiskVersion(at: url)
        refresh()
    }

    /// 外部重载：丢失本地未保存修改，需由视图确认。
    func reloadExternal() {
        guard let url = session.projectURL else { return }
        let mtime = pendingExternalMtime ?? Self.modificationDate(of: url)
        if open(url: url) {
            notice = mtime.map {
                I18n.t("alert.external_update_loaded", "External update loaded at %1$@", Display.time($0))
            } ?? I18n.t("alert.external_update_loaded.plain", "External update loaded")
        } else {
            // 失败保留横幅；相同 mtime 不再重复尝试。
            failedExternalMtime = mtime
        }
    }

    private func resetViewStateForLoadedProject() {
        let tasks = session.project?.tasks ?? []
        viewState = WorkspaceViewState(
            expandedTaskIDs: Self.allParentIDs(in: tasks),
            inspectorVisible: viewState.inspectorVisible,
            inspectorWidth: viewState.inspectorWidth,
            showCriticalPath: viewState.showCriticalPath,
            showBarLabels: viewState.showBarLabels,
            // 列宽/显隐是应用级视图偏好（与检查器宽度同类）：换项目不重置，
            // 否则打开文件会静默清空用户配置并写回偏好。
            outlineColumnWidths: viewState.outlineColumnWidths,
            hiddenOutlineColumns: viewState.hiddenOutlineColumns
        )
        lockedTaskID = nil
        lockedTaskTitle = nil
        suspendedFilterText = nil
    }

    private static func allParentIDs(in tasks: [TaskItem]) -> Set<UUID> {
        Set(tasks.compactMap(\.parentID))
    }

    // MARK: - 视图偏好持久化

    private static func loadPreferences(from defaults: UserDefaults) -> StoredPreferences? {
        guard let data = defaults.data(forKey: preferencesKey) else { return nil }
        return try? JSONDecoder().decode(StoredPreferences.self, from: data)
    }

    /// 载入列宽覆盖：丢弃未知列、非有限值与越界宽度（静默容错，不牵连其它字段）。
    ///
    /// 越界值丢弃而不夹取：宽度不合法说明数据已损坏，回落默认宽比落到边界更贴近用户原意。
    private static func loadedColumnWidths(_ stored: [String: Double]?) -> [String: Double] {
        guard let stored else { return [:] }
        var loaded: [String: Double] = [:]
        for (raw, width) in stored {
            guard let column = OutlineColumn(rawValue: raw),
                  width.isFinite,
                  OutlineColumnPreferences.widthRange(for: column).contains(width) else { continue }
            loaded[column.rawValue] = width
        }
        return loaded
    }

    /// 载入隐藏列：丢弃未知列 rawValue 与固定列（序号/任务说明不参与显隐）。
    private static func loadedHiddenColumns(_ stored: [String]?) -> Set<String> {
        guard let stored else { return [] }
        return Set(stored.compactMap { raw -> String? in
            guard let column = OutlineColumn(rawValue: raw),
                  !OutlineColumnPreferences.alwaysVisible.contains(column) else { return nil }
            return column.rawValue
        })
    }

    private func savePreferences() {
        let stored = StoredPreferences(
            outlineWidth: viewState.outlineWidth,
            outlineVisible: viewState.outlineVisible,
            expandedTaskIDs: Array(viewState.expandedTaskIDs),
            zoom: viewState.zoom,
            usesFitZoom: viewState.usesFitZoom,
            customDayWidth: viewState.customDayWidth,
            windowStart: viewState.windowStart,
            inspectorWidth: viewState.inspectorWidth,
            inspectorTab: viewState.inspectorTab,
            // 空覆盖/空隐藏写 nil：JSON 不落空容器，旧版本读回同一语义。
            outlineColumnWidths: viewState.outlineColumnWidths.isEmpty ? nil : viewState.outlineColumnWidths,
            hiddenOutlineColumns: viewState.hiddenOutlineColumns.isEmpty
                ? nil
                : viewState.hiddenOutlineColumns.sorted()
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.preferencesKey)
    }

    // MARK: - 外部更新检测

    /// 比较磁盘 mtime（应用前台每 2 秒调用一次；测试可直接调用）。
    func checkExternalUpdate() {
        guard let url = session.projectURL,
              let mtime = Self.modificationDate(of: url) else { return }
        if let acknowledgedMtime, mtime <= acknowledgedMtime { return }
        if let knownDiskMtime, mtime == knownDiskMtime { return }
        if let failedExternalMtime, mtime <= failedExternalMtime { return }

        if session.hasUnsavedChanges {
            pendingExternalMtime = mtime
            externalUpdatePending = true
        } else if open(url: url) {
            notice = I18n.t("alert.external_update_loaded", "External update loaded at %1$@", Display.time(mtime))
        } else {
            failedExternalMtime = mtime
        }
    }

    private func recordDiskVersion(at url: URL?) {
        knownDiskMtime = url.flatMap { Self.modificationDate(of: $0) }
        pendingExternalMtime = nil
        acknowledgedMtime = nil
        failedExternalMtime = nil
        externalUpdatePending = false
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    // MARK: - 错误

    private func report(_ error: Error) {
        if let sessionError = error as? SessionError {
            alertMessage = sessionError.message
        } else if let fileError = error as? KairoFileError {
            alertMessage = fileError.description
        } else {
            alertMessage = error.localizedDescription
        }
    }
}
