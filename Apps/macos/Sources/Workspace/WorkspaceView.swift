import AppKit
import SwiftUI
import KairoCore
import KairoPresentation

/// 主窗口：计划工作台 / 全宽大纲。
///
/// 壳层只消费 `WorkspaceStore` 的快照与动作，不直接读写核心模型。
struct WorkspaceView: View {
    @ObservedObject var store: WorkspaceStore
    let commands: [KairoCommand]

    @State private var editingTaskID: UUID?
    @State private var scrollTarget: UUID?
    @State private var findAdapter = RowsFindAdapter()
    /// 日宽调节面板（工具栏标尺按钮的 popover）是否展开。
    @State private var showsDayWidthControl = false
    /// 列宽拖拽中的预览草稿（F-14-20）：表头与行共用同一 layout，故两侧同步预览。
    /// 松手（`onResizeEnded`）才提交一次，拖动期间不落盘。
    @State private var liveColumnResize: (column: OutlineColumn, width: CGFloat)?

    var body: some View {
        VStack(spacing: 0) {
            if store.filterBarVisible {
                FilterBar(store: store)
                Divider()
            }
            if store.externalUpdatePending {
                ExternalUpdateBar(store: store)
            }
            workspaceContent
            Divider()
            StatusBarView(store: store)
        }
        .background(DesignTokens.surfaceBase)
        .toolbar { toolbarContent }
        .overlay {
            if store.showCommandPalette {
                CommandPalette(commands: commands) {
                    store.showCommandPalette = false
                }
            }
        }
        .overlay {
            if store.showsLoadingSkeleton {
                LoadingSkeletonView()
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let notice = store.notice {
                noticeToast(notice)
            }
        }
        .alert(
            "无法完成操作",
            isPresented: Binding(
                get: { store.alertMessage != nil },
                set: { if !$0 { store.alertMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {
                store.alertMessage = nil
            }
        } message: {
            Text(store.alertMessage ?? "")
        }
        .confirmationDialog(
            store.pendingDeletion.map { "删除群组「\($0.title)」？" } ?? "删除？",
            isPresented: Binding(
                get: { store.pendingDeletion != nil },
                set: { if !$0 { store.pendingDeletion = nil } }
            ),
            presenting: store.pendingDeletion
        ) { pending in
            Button("删除 \(pending.affectedCount) 个任务", role: .destructive) {
                store.confirmPendingDeletion()
            }
            Button("取消", role: .cancel) {
                store.pendingDeletion = nil
            }
        } message: { pending in
            Text("「\(pending.title)」包含 \(max(pending.affectedCount - 1, 0)) 个子任务，将一并删除。该操作可以撤销。")
        }
        .confirmationDialog(
            "当前项目有未保存的修改",
            isPresented: Binding(
                get: { store.pendingOpenURL != nil },
                set: { if !$0 { store.cancelPendingOpen() } }
            )
        ) {
            Button("丢弃修改并打开", role: .destructive) {
                store.discardChangesAndOpenPending()
            }
            if store.canSavePendingOpen {
                Button("保存并打开") {
                    store.saveAndOpenPending()
                }
            }
            Button("取消", role: .cancel) {
                store.cancelPendingOpen()
            }
        } message: {
            Text("打开其他项目会丢失当前项目中未保存的修改。")
        }
        .confirmationDialog(
            "当前项目有未保存的修改",
            isPresented: Binding(
                get: { store.pendingLoadExample },
                set: { if !$0 { store.cancelPendingLoadExample() } }
            )
        ) {
            Button("丢弃修改并载入", role: .destructive) {
                store.confirmPendingLoadExample()
            }
            Button("取消", role: .cancel) {
                store.cancelPendingLoadExample()
            }
        } message: {
            Text("载入示例项目会丢弃当前项目中未保存的修改。")
        }
        .onAppear {
            findAdapter.onReveal = { store.reveal($0) }
            findAdapter.rows = store.snapshot.outline.rows
            store.find.attach(target: findAdapter)
        }
        .onChange(of: store.snapshot.outline.rows) { _, rows in
            findAdapter.rows = rows
            store.find.rescan()
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Picker("视图", selection: Binding(
                get: { store.viewState.mode },
                set: { store.dispatch(.setMode($0)) }
            )) {
                Text("计划").tag(WorkspaceMode.plan)
                Text("大纲").tag(WorkspaceMode.outline)
            }
            .pickerStyle(.segmented)
            .frame(width: 132)
            .help("计划 ⌥⌘1 · 大纲 ⌥⌘2")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if !AIFilterTranslator.translate(store.viewState.filterText).isEmpty {
                Button {
                    store.filterBarVisible = true
                } label: {
                    Label("AI 筛选", systemImage: "sparkles")
                        .foregroundStyle(DesignTokens.criticalText)
                }
                .help("自然语言筛选已解析为结构化条件")
            }

            Menu {
                ForEach(GanttZoom.allCases, id: \.self) { zoom in
                    Button(zoomTitle(zoom)) {
                        store.dispatch(.setZoom(zoom))
                    }
                }
                Divider()
                Button(fitMenuTitle) {
                    store.dispatch(.setFitZoom(true))
                }
                Divider()
                Button("更宽") {
                    store.dispatch(.nudgeCustomDayWidth(by: GanttScale.dayWidthStep))
                }
                Button("更窄") {
                    store.dispatch(.nudgeCustomDayWidth(by: -GanttScale.dayWidthStep))
                }
                Button("重置宽度") {
                    store.dispatch(.clearCustomDayWidth)
                }
                Button("自定义日宽…") {
                    // 菜单关闭后再弹出，避免与菜单收起动画抢时机。
                    Task { @MainActor in showsDayWidthControl = true }
                }
                Divider()
                Text("当前日宽：\(currentDayWidthText)")
                Divider()
                Button(store.viewState.showBarLabels ? "隐藏任务条标签" : "显示任务条标签") {
                    store.dispatch(.toggleBarLabels)
                }
            } label: {
                Label(Display.zoomPresetTitle(store.snapshot.statusBar.zoom.preset), systemImage: "arrow.left.and.right")
            }
            .help("时间缩放")

            Button {
                showsDayWidthControl.toggle()
            } label: {
                Image(systemName: "ruler")
            }
            .help("自定义每日宽度")
            .popover(isPresented: $showsDayWidthControl, arrowEdge: .bottom) {
                DayWidthControl(store: store, dayWidth: store.snapshot.gantt.dayWidth)
            }

            Button {
                store.dispatch(.toggleCriticalPath)
            } label: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(store.viewState.showCriticalPath
                        ? DesignTokens.criticalGraphic
                        : DesignTokens.textSecondary)
            }
            .help(store.viewState.showCriticalPath ? "隐藏重要路径" : "显示重要路径")

            Button {
                store.dispatch(.setInspectorVisible(true))
                store.dispatch(.setInspectorTab(.violations))
            } label: {
                Image(systemName: "exclamationmark.triangle")
                    .overlay(alignment: .topTrailing) {
                        if violationCount > 0 {
                            Circle()
                                .fill(DesignTokens.violationError)
                                .frame(width: 6, height: 6)
                                .offset(x: 2, y: -2)
                        }
                    }
            }
            .help("违例（⌥⌘V）")

            Menu {
                Button("新建任务") { store.dispatch(.createTask(parentID: nil, kind: .task)) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("新建群组") { store.dispatch(.createTask(parentID: nil, kind: .group)) }
                    .keyboardShortcut("g", modifiers: [.command, .option])
                Button("新建里程碑") { store.dispatch(.createTask(parentID: nil, kind: .milestone)) }
                    .keyboardShortcut("m", modifiers: [.command, .option])
            } label: {
                Image(systemName: "plus")
            }
            .help("新建任务")

            Button {
                store.dispatch(.setOutlineVisible(!store.viewState.outlineVisible))
            } label: {
                Image(systemName: "sidebar.leading")
                    .foregroundStyle(store.viewState.outlineVisible
                        ? DesignTokens.textPrimary
                        : DesignTokens.textSecondary)
            }
            .help(store.viewState.outlineVisible ? "隐藏任务列表" : "显示任务列表")

            Button {
                store.dispatch(.setInspectorVisible(!store.viewState.inspectorVisible))
            } label: {
                Image(systemName: "sidebar.right")
                    .foregroundStyle(store.viewState.inspectorVisible
                        ? DesignTokens.textPrimary
                        : DesignTokens.textSecondary)
            }
            .help(store.viewState.inspectorVisible ? "隐藏检查器" : "显示检查器")
        }
    }

    private var violationCount: Int {
        store.snapshot.statusBar.violationErrorCount + store.snapshot.statusBar.violationWarningCount
    }

    /// 缩放菜单的档位标题：当前生效档位打勾，并附该档位的默认日宽。
    private func zoomTitle(_ zoom: GanttZoom) -> String {
        let name: String
        switch zoom {
        case .day: name = "日"
        case .week: name = "周"
        case .month: name = "月"
        }
        let mark = isCurrentPreset(zoom) ? "✓ " : ""
        return "\(mark)\(name)（\(Int(zoom.dayWidth)) 点/天）"
    }

    /// 当前生效的预设档位：自定义日宽或「适合项目」生效时无档位打勾。
    private func isCurrentPreset(_ zoom: GanttZoom) -> Bool {
        store.viewState.customDayWidth == nil
            && !store.viewState.usesFitZoom
            && store.viewState.zoom == zoom
    }

    /// 「适合项目」菜单项标题：生效时打勾。
    private var fitMenuTitle: String {
        let active = store.viewState.customDayWidth == nil && store.viewState.usesFitZoom
        return active ? "✓ 适合项目" : "适合项目"
    }

    /// 缩放菜单的当前日宽读数（点/天）。
    private var currentDayWidthText: String {
        Display.pointsPerDay(store.snapshot.gantt.dayWidth)
    }

    // MARK: - 工作区

    private var workspaceContent: some View {
        GeometryReader { geo in
            let sizes = WorkspaceSizes(state: store.viewState, width: geo.size.width)
            HStack(spacing: 0) {
                planArea(sizes: sizes, height: geo.size.height)
                if sizes.inspectorDocked {
                    inspectorDivider(sizes: sizes)
                    InspectorView(
                        store: store,
                        snapshot: store.snapshot.inspector,
                        width: sizes.inspectorWidth,
                        onClose: { store.dispatch(.setInspectorVisible(false)) }
                    )
                }
            }
            .overlay(alignment: .trailing) {
                if store.viewState.inspectorVisible, !sizes.inspectorDocked {
                    overlayInspector(height: geo.size.height)
                }
            }
            .onAppear {
                store.setViewport(
                    canvasWidth: Double(sizes.canvasWidth),
                    canvasHeight: Double(max(geo.size.height - 45, 1))
                )
            }
            .onChange(of: sizes.canvasWidth) { _, width in
                store.setViewport(
                    canvasWidth: Double(width),
                    canvasHeight: Double(max(geo.size.height - 45, 1))
                )
            }
        }
    }

    private func planArea(sizes: WorkspaceSizes, height: CGFloat) -> some View {
        let rows = store.snapshot.outline.rows
        let gantt = store.snapshot.gantt
        let hiddenColumns = hiddenOutlineColumns
        // 列集合与 Presenter 同源（F-14-20 策略）：阈值降级优先，用户隐藏只进一步收窄。
        let columns = !sizes.showsOutline
            ? []
            : OutlineColumnPreferences.visibleColumns(
                outlineWidth: Double(sizes.outlineWidth),
                hidden: hiddenColumns,
                focused: sizes.focused
            )
        let layout = OutlineColumnLayout(
            columns: columns,
            totalWidth: sizes.outlineWidth,
            focused: sizes.focused,
            widthOverrides: columnWidthOverrides,
            liveResize: liveColumnResize
        )
        let bannerHeight: CGFloat = gantt.projectStartDerived && sizes.showsTimeline ? 24 : 0
        let bodyHeight = max(height - DesignTokens.headerHeight - 1 - bannerHeight, 1)

        return VStack(spacing: 0) {
            if gantt.projectStartDerived && sizes.showsTimeline {
                projectStartBanner
            }
            HStack(spacing: 0) {
                if sizes.showsOutline {
                    OutlineHeaderView(
                        layout: layout,
                        hiddenColumns: hiddenColumns,
                        onResizeChanged: { column, width in
                            liveColumnResize = (column, clampedColumnWidth(width, for: column))
                        },
                        onResizeEnded: { shouldCommit in commitLiveColumnResize(shouldCommit) },
                        onResizeReset: { column in
                            liveColumnResize = nil
                            store.dispatch(.setOutlineColumnWidth(column, nil))
                        },
                        onToggleColumn: { store.dispatch(.toggleOutlineColumn($0)) }
                    )
                    .frame(width: sizes.outlineWidth, height: DesignTokens.headerHeight)
                }
                if sizes.showsTimeline {
                    if sizes.showsOutline {
                        OutlineResizeHandle(store: store, baseWidth: sizes.outlineWidth)
                    }
                    TimelineHeaderView(store: store, gantt: gantt, width: sizes.canvasWidth)
                }
            }
            // 表头固定 44pt：分界线等弹性子视图不得抬高表头、挤压滚动区。
            .frame(height: DesignTokens.headerHeight)
            horizontalRule
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        if sizes.showsOutline {
                            OutlineRowsList(
                                store: store,
                                rows: rows,
                                layout: layout,
                                editingTaskID: $editingTaskID
                            )
                            .frame(width: sizes.outlineWidth)
                        }
                        if sizes.showsTimeline {
                            if sizes.showsOutline {
                                OutlineResizeHandle(store: store, baseWidth: sizes.outlineWidth)
                            }
                            TimelineBody(
                                store: store,
                                rows: rows,
                                gantt: gantt,
                                width: sizes.canvasWidth,
                                viewportHeight: bodyHeight
                            )
                        }
                    }
                    .frame(width: sizes.mainWidth, alignment: .topLeading)
                }
                .coordinateSpace(name: WorkspaceScrollSpace.name)
                .focusable()
                .onKeyPress(keys: [.upArrow, .downArrow, .return, .tab, .escape]) { press in
                    handleKey(press, rows: rows)
                }
                .onChange(of: scrollTarget) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    scrollTarget = nil
                }
                .overlay {
                    if let reason = store.snapshot.outline.emptyReason {
                        EmptyWorkspaceView(reason: reason, store: store)
                    }
                }
            }
        }
        .frame(width: sizes.mainWidth, height: height, alignment: .top)
    }

    // MARK: - 大纲列偏好（F-14-20）

    /// 用户隐藏的列：状态里存的是 rawValue，未知键在此静默忽略。
    private var hiddenOutlineColumns: Set<OutlineColumn> {
        Set(store.viewState.hiddenOutlineColumns.compactMap(OutlineColumn.init(rawValue:)))
    }

    /// 用户列宽覆盖（列 → 点宽）：Store 载入/写入时已过滤未知列与越界值。
    private var columnWidthOverrides: [OutlineColumn: Double] {
        var overrides: [OutlineColumn: Double] = [:]
        for (raw, width) in store.viewState.outlineColumnWidths {
            guard let column = OutlineColumn(rawValue: raw) else { continue }
            overrides[column] = width
        }
        return overrides
    }

    /// 列宽夹取到策略区间（非有限值回落默认宽）：拖动草稿与提交共用同一口径。
    private func clampedColumnWidth(_ width: CGFloat, for column: OutlineColumn) -> CGFloat {
        let range = OutlineColumnPreferences.widthRange(for: column)
        guard Double(width).isFinite else {
            return CGFloat(OutlineColumnPreferences.defaultWidth(for: column))
        }
        return CGFloat(min(max(Double(width), range.lowerBound), range.upperBound))
    }

    /// 表头拖拽松手：提交一次并清空草稿（拖动期间只改本地状态，设计 R1）。
    /// 松手提交：`shouldCommit == false`（误触/中断）只清草稿，不写覆盖值。
    private func commitLiveColumnResize(_ shouldCommit: Bool = true) {
        guard let live = liveColumnResize else { return }
        liveColumnResize = nil
        guard shouldCommit else { return }
        store.dispatch(.setOutlineColumnWidth(live.column, Double(live.width)))
    }

    private var projectStartBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textSecondary)
            Text("未设置项目开始日期，已按最早任务开始日期推导。")
                .font(.system(size: DesignTokens.captionFontSize))
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer(minLength: 0)
            Button("设置项目开始日期") {
                store.dispatch(.select(nil))
                store.dispatch(.setInspectorTab(.inspector))
            }
            .buttonStyle(.link)
            .font(.system(size: DesignTokens.captionFontSize))
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(DesignTokens.surfaceChrome)
    }

    private var horizontalRule: some View {
        Rectangle()
            .fill(DesignTokens.separator)
            .frame(height: 1)
    }

    private func inspectorDivider(sizes: WorkspaceSizes) -> some View {
        InspectorResizeHandle(store: store, baseWidth: sizes.inspectorWidth)
    }

    private func overlayInspector(height: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { store.dispatch(.setInspectorVisible(false)) }
            InspectorView(
                store: store,
                snapshot: store.snapshot.inspector,
                width: 300,
                onClose: { store.dispatch(.setInspectorVisible(false)) }
            )
            .background(DesignTokens.surfaceElevated)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(DesignTokens.separator)
                    .frame(width: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 12, x: -2, y: 0)
        }
        .frame(height: height)
        .onExitCommand { store.dispatch(.setInspectorVisible(false)) }
    }

    private func noticeToast(_ message: String) -> some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.system(size: DesignTokens.captionFontSize))
            Button {
                store.clearNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DesignTokens.surfaceElevated, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(DesignTokens.separator, lineWidth: 1)
        }
        .padding(10)
        .padding(.bottom, 24)
        .task(id: message) {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            store.clearNotice()
        }
    }

    // MARK: - 键盘

    private func handleKey(_ press: KeyPress, rows: [PlanRow]) -> KeyPress.Result {
        switch press.key {
        case .upArrow:
            moveSelection(offset: -1, rows: rows)
            return .handled
        case .downArrow:
            moveSelection(offset: 1, rows: rows)
            return .handled
        case .return:
            editingTaskID = store.selection
            return .handled
        case .tab:
            // ⌃Tab 保留为全键盘访问出口，不得被缩进快捷键截断。
            if press.modifiers.contains(.control) { return .ignored }
            guard let id = store.selection else { return .ignored }
            if press.modifiers.contains(.shift) {
                store.dispatch(.outdent(id))
            } else {
                store.dispatch(.indent(id))
            }
            return .handled
        case .escape:
            editingTaskID = nil
            return .handled
        default:
            return .ignored
        }
    }

    private func moveSelection(offset: Int, rows: [PlanRow]) {
        guard !rows.isEmpty else { return }
        guard let current = store.selection,
              let index = rows.firstIndex(where: { $0.id == current }) else {
            let id = rows.first?.id
            store.dispatch(.select(id))
            scrollTarget = id
            return
        }
        let target = min(max(index + offset, 0), rows.count - 1)
        let id = rows[target].id
        store.dispatch(.select(id))
        scrollTarget = id
    }
}

// MARK: - 尺寸

/// 响应式宽度分配（ui-redesign §2.2）：检查器 → 画布保底 → 大纲夹取。
struct WorkspaceSizes {
    let mainWidth: CGFloat
    let outlineWidth: CGFloat
    let canvasWidth: CGFloat
    let showsTimeline: Bool
    let showsOutline: Bool
    let focused: Bool
    let inspectorDocked: Bool
    let inspectorWidth: CGFloat

    init(state: WorkspaceViewState, width: CGFloat) {
        let docked = state.inspectorVisible && width >= DesignTokens.inspectorThreshold
        let inspector = min(
            max(CGFloat(state.inspectorWidth), DesignTokens.inspectorMinWidth),
            DesignTokens.inspectorMaxWidth
        )
        let main = max(width - (docked ? inspector + 1 : 0), 0)
        self.inspectorDocked = docked
        self.inspectorWidth = inspector
        self.mainWidth = main

        guard state.mode == .plan else {
            self.focused = false
            self.outlineWidth = main
            self.canvasWidth = 0
            self.showsTimeline = false
            self.showsOutline = true
            return
        }

        // 大纲隐藏：时间画布占满主区。
        guard state.outlineVisible else {
            self.focused = false
            self.outlineWidth = 0
            self.canvasWidth = main
            self.showsTimeline = true
            self.showsOutline = false
            return
        }

        let focus = state.chartFocused
        var outline: CGFloat
        if focus {
            outline = DesignTokens.focusedOutlineWidth
        } else {
            outline = min(
                max(CGFloat(state.outlineWidth), DesignTokens.outlineMinWidth),
                DesignTokens.outlineMaxWidth
            )
            let maxOutline = main - 1 - DesignTokens.canvasMinWidth
            if maxOutline >= DesignTokens.outlineMinWidth {
                outline = min(outline, maxOutline)
            } else {
                outline = max(main - 1, 0)
            }
            if state.inspectorVisible && !docked {
                outline = min(outline, DesignTokens.outlineMinWidth)
            }
        }
        let canvas = max(main - outline - 1, 0)
        self.focused = focus
        if canvas > 0 {
            self.outlineWidth = outline
            self.canvasWidth = canvas
            self.showsTimeline = true
        } else {
            self.outlineWidth = main
            self.canvasWidth = 0
            self.showsTimeline = false
        }
        self.showsOutline = true
    }
}

// MARK: - 空态

private struct EmptyWorkspaceView: View {
    let reason: EmptyReason
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(DesignTokens.textSecondary)
            Text(title)
                .font(.system(size: DesignTokens.bodyFontSize, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text(detail)
                .font(.system(size: DesignTokens.captionFontSize))
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            actions
        }
        .padding(20)
        .background(DesignTokens.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DesignTokens.separator, lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.surfaceBase.opacity(0.92))
    }

    private var symbol: String {
        switch reason {
        case .noTasks: return "square.stack.3d.up"
        case .noMatches: return "line.3.horizontal.decrease.circle"
        case .noSchedule: return "calendar.badge.exclamationmark"
        }
    }

    private var title: String {
        switch reason {
        case .noTasks: return "项目中还没有任务"
        case .noMatches: return "没有匹配的任务"
        case .noSchedule: return "任务尚未排期"
        }
    }

    private var detail: String {
        switch reason {
        case .noTasks:
            return "新建任务开始规划，或由 AI 智能体通过 MCP / CLI 导入现有 WBS。"
        case .noMatches:
            return "调整筛选条件，或清除筛选查看全部任务。"
        case .noSchedule:
            return "设置项目开始日期，或检查相关性环与时限设置。"
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch reason {
        case .noTasks:
            // MCP 是协议而非界面能力：导入由 AI 智能体在会话侧发起，界面只保留人工新建入口。
            Button("新建任务") {
                store.dispatch(.createTask(parentID: nil, kind: .task))
            }
            .buttonStyle(.borderedProminent)
        case .noMatches:
            Button("清除筛选") {
                store.dispatch(.setFilter(""))
            }
        case .noSchedule:
            Button("设置项目开始日期") {
                store.dispatch(.select(nil))
                store.dispatch(.setInspectorTab(.inspector))
            }
        }
    }
}

// MARK: - 查找适配

/// 检查器拖宽把手：以手势开始时的宽度为基准，避免夹取造成漂移。
private struct InspectorResizeHandle: View {
    @ObservedObject var store: WorkspaceStore
    let baseWidth: CGFloat

    @State private var dragBase: CGFloat?

    var body: some View {
        Rectangle()
            .fill(DesignTokens.separator)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 6)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if dragBase == nil { dragBase = baseWidth }
                                guard let base = dragBase else { return }
                                store.dispatch(.setInspectorWidth(
                                    Double(base - value.translation.width)
                                ))
                            }
                            .onEnded { _ in dragBase = nil }
                    )
            }
    }
}

/// 大纲与时间画布之间的分界线（对齐 OmniPlan）：向右拖加大纲、向左拖扩大甘特，
/// 宽度经 `.setOutlineWidth` 夹取并持久化。
///
/// 手势用 `.highPriorityGesture`：滚动容器内的分界线不得被滚动手势吞掉。
private struct OutlineResizeHandle: View {
    @ObservedObject var store: WorkspaceStore
    let baseWidth: CGFloat

    @State private var dragBase: CGFloat?

    var body: some View {
        Rectangle()
            .fill(DesignTokens.separator)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if dragBase == nil { dragBase = baseWidth }
                                guard let base = dragBase else { return }
                                store.dispatch(.setOutlineWidth(
                                    Double(base + value.translation.width)
                                ))
                            }
                            .onEnded { _ in dragBase = nil }
                    )
            }
    }
}

/// 把可见大纲行接到 `FindController`；命中后统一走「揭示目标」。
final class RowsFindAdapter: FindTarget {
    var rows: [PlanRow] = []
    var onReveal: ((UUID) -> Void)?

    var findableText: [String] { rows.map(\.title) }

    func revealMatch(at index: Int) {
        guard rows.indices.contains(index) else { return }
        onReveal?(rows[index].id)
    }
}
