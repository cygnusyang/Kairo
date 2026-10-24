import AppKit
import SwiftUI
import UniformTypeIdentifiers
import KairoCore
import KairoPresentation

/// 大纲行列表。
///
/// 只输出行骨架，不持有滚动容器：计划模式与时间画布共用同一个纵向
/// `ScrollView`（ADR-013 第 5 条），大纲模式下画布列为零宽。
struct OutlineRowsList: View {
    @ObservedObject var store: WorkspaceStore
    let rows: [PlanRow]
    let layout: OutlineColumnLayout
    @Binding var editingTaskID: UUID?

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(rows) { row in
                OutlineRowView(
                    store: store,
                    row: row,
                    layout: layout,
                    editingTaskID: $editingTaskID
                )
                .frame(height: DesignTokens.rowHeight)
                .id(row.id)
                // 行分隔线由行视图以底部 overlay 自绘（不占布局空间）：
                // 左列总高必须严格等于 行数 × rowHeight，与画布 28pt 节距对齐。
            }
        }
        .frame(width: layout.totalWidth, alignment: .topLeading)
        .clipped()
        .background(DesignTokens.surfaceBase)
    }
}

/// 列宽计算：非标题列随大纲宽度等比压缩，标题列吃掉剩余宽度。
struct OutlineColumnLayout {
    let columns: [OutlineColumn]
    let totalWidth: CGFloat
    let focused: Bool
    /// 用户列宽覆盖（点，F-14-20）：命中时不再乘压缩系数，否则拖宽无效。
    var widthOverrides: [OutlineColumn: Double] = [:]
    /// 拖拽中的预览草稿（列 + 点宽）：优先于覆盖值，松手才提交。
    var liveResize: (column: OutlineColumn, width: CGFloat)? = nil

    /// 压缩系数：以 600pt 为基准，最窄压到 0.6；聚焦标签栏不压缩。
    private var scale: CGFloat {
        focused ? 1 : min(max(totalWidth / 600, 0.6), 1)
    }

    /// 列宽优先级：拖拽草稿 → 用户覆盖值（不压缩）→ 默认派生宽（乘压缩系数）。
    /// 三者皆无、即无用户配置时与引入本机制前逐位一致。
    func width(of column: OutlineColumn) -> CGFloat {
        if column == .title {
            return max(totalWidth - fixedWidthTotal, focused ? 0 : 120)
        }
        if let live = liveResize, live.column == column {
            return max(live.width, 0)
        }
        // 聚焦标签栏（180pt）忽略用户宽度，避免计划模式拖过的宽度在聚焦模式里串味。
        if !focused, let override = widthOverrides[column] {
            return CGFloat(override)
        }
        return CGFloat(column.width(bodyFontSize: 13)) * scale
    }

    private var fixedWidthTotal: CGFloat {
        columns.filter { $0 != .title }.reduce(0) { $0 + width(of: $1) }
    }
}

/// 大纲表头：列标题 + 每列右缘的调宽手柄 + 右键列显隐菜单（F-14-20）。
///
/// 手柄只在表头出现；列宽拖拽期间只回调预览草稿（`onResizeChanged`），
/// 松手才由 `onResizeEnded` 提交一次，避免每帧落盘（设计 R1）。
struct OutlineHeaderView: View {
    let layout: OutlineColumnLayout
    /// 当前隐藏的列：右键菜单勾选态的数据源。
    let hiddenColumns: Set<OutlineColumn>
    let onResizeChanged: (OutlineColumn, CGFloat) -> Void
    /// 松手：参数为「是否应提交」（<2pt 视为误触，只清草稿）。
    let onResizeEnded: (Bool) -> Void
    let onResizeReset: (OutlineColumn) -> Void
    let onToggleColumn: (OutlineColumn) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(layout.columns, id: \.self) { column in
                Text(headerTitle(column))
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(width: layout.width(of: column), alignment: .leading)
                    .overlay(alignment: .trailing) {
                        // 聚焦标签栏不提供调宽；末列手柄内缩 6pt，避开大纲右边界手柄的热区。
                        if OutlineColumnPreferences.isResizable(column), !layout.focused {
                            OutlineColumnResizeHandle(
                                baseWidth: layout.width(of: column),
                                isLastColumn: layout.columns.last == column,
                                onChanged: { onResizeChanged(column, $0) },
                                onEnded: onResizeEnded,
                                onReset: { onResizeReset(column) }
                            )
                        }
                    }
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 4)
        // leading 锚定 + 裁切：列宽总和超过大纲宽时从右侧裁切，与行列表的 topLeading 一致。
        .frame(width: layout.totalWidth, alignment: .topLeading)
        .clipped()
        .background(DesignTokens.surfaceChrome)
        .contextMenu { columnMenu }
    }

    /// 列显隐菜单：序号/任务说明固定显示，不出现在开关列表（`configurable` 已排除）。
    private var columnMenu: some View {
        ForEach(OutlineColumnPreferences.configurable, id: \.self) { column in
            Toggle(isOn: Binding(
                get: { !hiddenColumns.contains(column) },
                set: { _ in onToggleColumn(column) }
            )) {
                // 标签只写列名：勾选态本身表达显示/隐藏。
                Text("\(Display.outlineColumnTitle(column))列")
            }
        }
    }

    private func headerTitle(_ column: OutlineColumn) -> String {
        switch column {
        case .status: return ""
        case .violation: return "!"
        case .number: return "#"
        case .title: return "任务"
        case .predecessors: return "前置"
        case .start: return "开始"
        case .finish: return "结束"
        case .duration: return "持续"
        case .assignee: return "负责人"
        case .progress: return "完成"
        }
    }
}

/// 表头列宽手柄：叠在列右缘的 6pt 热区。
///
/// - hover 切左右调整光标并显示 1pt 高亮（设计 §2）；
/// - 拖拽以手势开始时的列宽为基准，避免与已回写的预览草稿重复累加；
/// - 双击复位该列（删除覆盖值）。
private struct OutlineColumnResizeHandle: View {
    /// 手势开始时的列宽（点）；每次求值由表头按当前布局给出。
    let baseWidth: CGFloat
    /// 是否末列：末列右缘与大纲右边界手柄重合，需内缩让出热区。
    var isLastColumn: Bool = false
    let onChanged: (CGFloat) -> Void
    /// 松手：参数为「是否应提交」——抖动不足 2pt（误触）时只清草稿、不写覆盖值。
    let onEnded: (Bool) -> Void
    let onReset: () -> Void

    @State private var dragBase: CGFloat?
    @State private var hovering = false

    /// 右缘热区宽度（点）：窄到不挡住相邻列标题，又足够抓取。
    private static let hotZoneWidth: CGFloat = 6
    /// 提交阈值（点）：小于该位移视为抖动，避免单击手柄写入粘滞覆盖值。
    private static let commitThreshold: CGFloat = 2

    var body: some View {
        Color.clear
            .frame(width: Self.hotZoneWidth)
            .contentShape(Rectangle())
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(DesignTokens.accentStrong)
                    .frame(width: 1)
                    .opacity(hovering || dragBase != nil ? 1 : 0)
            }
            .onHover { inside in
                hovering = inside
                if inside {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            // 表头位于滚动容器之外的固定区，仍用 highPriorityGesture 与行选中手势隔离。
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragBase == nil { dragBase = baseWidth }
                        guard let base = dragBase else { return }
                        onChanged(base + value.translation.width)
                    }
                    .onEnded { value in
                        dragBase = nil
                        onEnded(abs(value.translation.width) >= Self.commitThreshold)
                    }
            )
            .onTapGesture(count: 2) { onReset() }
            // 拖拽被系统中断（切模式/换项目/窗口失焦）时 onEnded 不保证触发：
            // 这里兜底清草稿并复位光标，避免未提交宽度长期驻留。
            .onDisappear {
                if dragBase != nil {
                    dragBase = nil
                    onEnded(false)
                }
                if hovering {
                    hovering = false
                    NSCursor.arrow.set()
                }
            }
            .offset(x: isLastColumn ? -Self.hotZoneWidth : 0)
            .accessibilityHidden(true)
            .help("拖动调整列宽，双击复位")
    }
}

private struct OutlineRowView: View {
    @ObservedObject var store: WorkspaceStore
    let row: PlanRow
    let layout: OutlineColumnLayout
    @Binding var editingTaskID: UUID?

    @State private var hovering = false
    @State private var dropTargeted = false
    @FocusState private var titleFocused: Bool

    private var isSelected: Bool { store.selection == row.id }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(layout.columns, id: \.self) { column in
                cell(column)
                    .frame(width: layout.width(of: column), alignment: .leading)
                    .clipped()
            }
        }
        .background(background)
        .contentShape(Rectangle())
        .onTapGesture { store.dispatch(.select(row.id)) }
        .onHover { hovering = $0 }
        .modifier(DragReorderModifier(
            enabled: store.allowsDragReorder,
            taskID: row.id,
            store: store,
            isTargeted: $dropTargeted
        ))
        .overlay(alignment: .bottom) {
            // 行分隔线画进行内底部，不占布局空间，保证行列表节距 = rowHeight。
            Rectangle()
                .fill(DesignTokens.separator)
                .frame(height: 1)
                .opacity(0.35)
            // 普通行插入到目标之后，插入线画在目标下缘（覆盖分隔线）；群组以整行高亮表示「放入」。
            if dropTargeted && row.kind != .group {
                Rectangle()
                    .fill(DesignTokens.accentStrong)
                    .frame(height: 2)
            }
        }
        .contextMenu { contextMenu }
        .help(row.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var background: Color {
        if dropTargeted { return DesignTokens.accentStrong.opacity(0.08) }
        if isSelected { return DesignTokens.selection }
        if row.isHighlighted { return DesignTokens.selection.opacity(0.55) }
        if hovering { return DesignTokens.hoverOverlay }
        return .clear
    }

    @ViewBuilder
    private func cell(_ column: OutlineColumn) -> some View {
        switch column {
        case .status:
            statusCell
        case .violation:
            violationCell
        case .number:
            Text(row.outlineNumber)
                .font(.system(size: DesignTokens.captionFontSize))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.horizontal, 4)
        case .title:
            titleCell
        case .predecessors:
            EditableTextCell(
                text: row.predecessorsText.isEmpty ? "—" : row.predecessorsText,
                value: row.predecessorsText,
                enabled: !row.isAggregate,
                onCommit: { store.dispatch(.setPredecessors(row.id, $0)) }
            )
        case .start:
            OutlineDateCell(
                column: .start,
                row: row,
                isSelected: isSelected,
                onOpen: { store.dispatch(.select(row.id)) },
                onCommit: { store.dispatch(.setTaskStart(row.id, $0)) }
            )
        case .finish:
            OutlineDateCell(
                column: .finish,
                row: row,
                isSelected: isSelected,
                onOpen: { store.dispatch(.select(row.id)) },
                onCommit: { date in
                    // 结束列不提供「清除」，`nil` 只可能来自清除（该列 `allowsClear` 为假，实际不可达）。
                    // 起点取同一快照行：Store 会用它做「排期已变化」与「结束晚于开始」两重校验（设计 R2）。
                    // 参数由策略纯函数给出：列禁用或快照没有排期起点时整体不提交，
                    // 不拿结束日兜底当起点（那会折算成 0 天并掩盖真实原因）。
                    guard let date,
                          let commit = OutlineDateEditing.finishCommit(row: row, finish: date) else {
                        return
                    }
                    store.dispatch(.setTaskFinish(
                        row.id,
                        finish: commit.finish,
                        start: commit.start
                    ))
                }
            )
        case .duration:
            EditableTextCell(
                text: row.durationDays.map { Display.duration($0) } ?? "—",
                value: row.durationDays.map { String(format: "%g", $0) } ?? "",
                enabled: !row.isAggregate,
                onCommit: { store.dispatch(.setDuration(row.id, Double($0))) }
            )
        case .assignee:
            EditableTextCell(
                text: row.assignee ?? "—",
                value: row.assignee ?? "",
                enabled: !row.isAggregate,
                onCommit: { text in
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    store.dispatch(.setAssignee(row.id, trimmed.isEmpty ? nil : trimmed))
                }
            )
        case .progress:
            progressCell
        }
    }

    private var statusCell: some View {
        Menu {
            ForEach(TaskStatus.allCases, id: \.self) { status in
                Button {
                    store.dispatch(.setStatus(row.id, status))
                } label: {
                    Label(
                        Display.statusTitle(status),
                        systemImage: Display.statusSymbol(status)
                    )
                }
            }
        } label: {
            Image(systemName: Display.statusSymbol(row.status))
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.semanticText(
                    statusColor,
                    isSelected: isSelected
                ))
                .frame(width: 18, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Display.statusTitle(row.status))
    }

    private var statusColor: Color {
        switch row.status {
        case .pending: return DesignTokens.textSecondary
        case .inProgress: return DesignTokens.accentStrong
        case .blocked: return DesignTokens.violationWarning
        case .done: return DesignTokens.statusSuccess
        }
    }

    private var violationCell: some View {
        Group {
            if row.violationCount > 0 {
                HStack(spacing: 1) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    if row.violationCount > 1 {
                        Text("\(row.violationCount)")
                            .font(.system(size: 9))
                    }
                }
                .foregroundStyle(DesignTokens.semanticText(
                    row.violationSeverity == .error
                        ? DesignTokens.violationError
                        : DesignTokens.violationWarning,
                    isSelected: isSelected
                ))
                .frame(width: 18)
                .help("\(row.violationCount) 条违例")
            } else {
                Color.clear.frame(width: 18)
            }
        }
    }

    private var titleCell: some View {
        HStack(spacing: 3) {
            if row.hasChildren {
                Button {
                    store.dispatch(.toggleExpanded(row.id))
                } label: {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(width: 14, height: 20)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 14)
            }

            if row.kind == .group {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textSecondary)
            } else if row.kind == .milestone {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(DesignTokens.accentStrong)
            }

            if editingTaskID == row.id {
                TextField("任务标题", text: Binding(
                    get: { row.title },
                    set: { store.dispatch(.rename(row.id, $0)) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: DesignTokens.bodyFontSize))
                .focused($titleFocused)
                .onAppear {
                    DispatchQueue.main.async { titleFocused = true }
                }
                .onSubmit {
                    titleFocused = false
                    editingTaskID = nil
                }
                .onExitCommand {
                    titleFocused = false
                    editingTaskID = nil
                }
                .onChange(of: titleFocused) { _, focused in
                    // 失焦只结束本行编辑；跨行的编辑目标可能已被另一行接管。
                    if !focused, editingTaskID == row.id { editingTaskID = nil }
                }
            } else {
                Text(row.title.isEmpty ? "未命名" : row.title)
                    .font(.system(
                        size: DesignTokens.bodyFontSize,
                        weight: row.kind == .group ? .semibold : .regular
                    ))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) { editingTaskID = row.id }
                    .accessibilityLabel(row.title)
            }

            if row.priority == .critical {
                Text("!")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DesignTokens.semanticText(
                        DesignTokens.violationWarning,
                        isSelected: isSelected
                    ))
                    .help("紧急")
            }
            if row.isOverdue {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignTokens.semanticText(
                        DesignTokens.overdue,
                        isSelected: isSelected
                    ))
                    .help("已逾期")
            }
            if row.deadlineRisk {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignTokens.semanticText(
                        DesignTokens.violationWarning,
                        isSelected: isSelected
                    ))
                    .help("计划结束晚于截止日期")
            }
            if !row.hasSchedule, let reason = row.unscheduledReason {
                Text(Display.unscheduledReason(reason))
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 14 + 2)
        .padding(.trailing, 4)
    }

    private var progressCell: some View {
        HStack(spacing: 4) {
            if row.isAggregate {
                Text(Display.percent(row.progress))
                    .font(.system(size: DesignTokens.bodyFontSize))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.textSecondary)
            } else {
                EditableTextCell(
                    text: Display.percent(row.progress),
                    value: "\(Int((row.progress * 100).rounded()))",
                    enabled: true,
                    onCommit: { text in
                        guard let value = Double(text) else { return }
                        store.dispatch(.setProgress(row.id, value / 100))
                    }
                )
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignTokens.progressTrack)
                    Capsule()
                        .fill(DesignTokens.progressFill)
                        .frame(width: max(0, geo.size.width * min(max(row.progress, 0), 1)))
                }
            }
            .frame(width: 28, height: 4)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("新建同级任务") {
            store.dispatch(.createSibling(after: row.id))
        }
        Button("新建子任务") {
            store.dispatch(.createTask(parentID: row.id, kind: .task))
        }
        Button("复制任务链接") {
            store.dispatch(.copyTaskLink(row.id))
        }
        Divider()
        Button("缩进") { store.dispatch(.indent(row.id)) }
        Button("减少缩进") { store.dispatch(.outdent(row.id)) }
        if row.kind == .group {
            Divider()
            Button("新建群组") { store.dispatch(.createTask(parentID: row.id, kind: .group)) }
            Button("新建里程碑") { store.dispatch(.createTask(parentID: row.id, kind: .milestone)) }
        }
        Divider()
        Button("删除", role: .destructive) {
            store.requestDelete(id: row.id)
        }
    }
}

/// 筛选激活时不注册拖拽手势，避免「可拖但目标不可见」的半成品交互。
private struct DragReorderModifier: ViewModifier {
    let enabled: Bool
    let taskID: UUID
    let store: WorkspaceStore
    @Binding var isTargeted: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    store.dispatch(.select(taskID))
                    return NSItemProvider(object: taskID.uuidString as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: OutlineRowDropDelegate(
                        targetID: taskID,
                        store: store,
                        isTargeted: $isTargeted
                    )
                )
        } else {
            content
        }
    }
}

/// 单行拖拽重排：拖到群组行成为子项，拖到普通行插为其后同级。
private struct OutlineRowDropDelegate: DropDelegate {
    let targetID: UUID
    let store: WorkspaceStore
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
        Task { @MainActor in store.scheduleDropExpand(on: targetID) }
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        Task { @MainActor in store.cancelDropExpand(on: targetID) }
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        Task { @MainActor in store.cancelDropExpand(on: targetID) }
        guard let provider = info.itemProviders(for: [.plainText]).first else {
            return false
        }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String,
                  let draggedID = UUID(uuidString: string) else { return }
            Task { @MainActor in
                guard let target = store.moveTarget(
                    draggedID: draggedID,
                    onto: targetID
                ) else { return }
                store.dispatch(.move(draggedID, parentID: target.parentID, index: target.index))
            }
        }
        return true
    }
}

/// 大纲日期单元格（F-14-19）：显示排期值，点击开月历弹层写回。
///
/// 只服务 `.start` / `.finish` 两列。可编辑性、禁用原因、最小可选日、清除显隐
/// 全部取自 `OutlineDateEditing`（纯函数策略）——单元格不判语义，也不持有 store：
/// 选中与写回经 `onOpen` / `onCommit` 回到行的接线点。
private struct OutlineDateCell: View {
    /// 日期列（`.start` / `.finish`）。
    let column: OutlineColumn
    let row: PlanRow
    let isSelected: Bool
    /// 弹层打开前回调（行选中同步）。
    let onOpen: () -> Void
    /// 提交选中日期；`nil` 只可能来自「清除」（仅开始列提供）。
    let onCommit: (Date?) -> Void

    /// 弹层开关与浏览月独立于标题编辑的 `editingTaskID`：翻月不改值，重开保留上月视图。
    @State private var isPresented = false
    /// 浏览月恒为「当月 1 日」：与 `CalendarGrid` 的口径一致，首次打开时再定位到选中值所在月。
    @State private var visibleMonth = CalendarGrid.month(containing: Date()).firstDay
    /// 上次打开时看到的值：用来识别「值被外部改动」（撤销、画布拖拽、检查器改写）。
    @State private var knownValue: Date?
    @State private var hasKnownValue = false

    /// 结束列越界格的 tooltip / 无障碍说明；与检查器「结束」行同一文案。
    private static let finishBoundaryHint = "结束须晚于开始，至少 1 天"

    var body: some View {
        // 单一视图 + 条件 help：`if let / else` 会因分支切换换掉视图类型，连带丢掉 @State
        //（弹层开关、浏览月），tooltip 也就成了「一显示就重建」。
        content.modifier(OutlineDateHelpModifier(text: helpText))
    }

    /// 文案 + 点击 + 弹层；tooltip 由 `body` 按需附加（空文案不生成 tooltip）。
    private var content: some View {
        Text(Display.date(value))
            .font(.system(size: DesignTokens.bodyFontSize))
            .monospacedDigit()
            .foregroundStyle(foreground)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            .popover(
                isPresented: $isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                CalendarPopover(
                    label: label,
                    selection: selection,
                    minimumDate: minimumDate,
                    allowsClear: column == .start,
                    canClear: OutlineDateEditing.canClear(column: column, row: row),
                    quickActions: DateQuickAction.allCases,
                    preview: { previewText(for: $0) },
                    disabledDayHint: column == .finish ? Self.finishBoundaryHint : nil,
                    visibleMonth: $visibleMonth,
                    onPick: commit,
                    onDismiss: { isPresented = false }
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(Display.isoDate(value))
            .accessibilityHint(isEnabled ? "打开月历选择日期" : (disabledReason ?? ""))
            .accessibilityAddTraits(isEnabled ? .isButton : [])
    }

    // MARK: - 策略

    private var isEnabled: Bool {
        OutlineDateEditing.isEnabled(column: column, row: row)
    }

    /// 不可编辑时的解释文案；可编辑为 nil（文案由视图按语义原因查 Catalog，F-0705）。
    private var disabledReason: String? {
        Display.dateFieldDisabledReason(OutlineDateEditing.availability(column: column, row: row))
    }

    private var minimumDate: Date? {
        OutlineDateEditing.minimumDate(column: column, row: row)
    }

    /// 列显示值：开始列是排期起点（可能被依赖后移）；结束列是排期排他端点。
    ///
    /// 结束日夹取到最小可选日（设计 R3）：亚日持续时间会让原始结束日落在
    /// 「起点 + 1 天」之前，弹层里就会出现「已选中但不可选」的死格。
    /// 口径与检查器一致（`DateFieldValueMath.clampedFinish`）。
    private var value: Date? {
        switch column {
        case .start:
            return row.scheduledStart
        case .finish:
            guard let finish = row.scheduledFinish else { return nil }
            return DateFieldValueMath.clampedFinish(finish, minimumDate: minimumDate)
        default:
            return nil
        }
    }

    /// 弹层选中值 = 真正可编辑的那个值：开始列是意图起点（`startDate`，未设置时回落排期起点），
    /// 结束列与显示值同源。
    ///
    /// 与 `value` 分开是因为开始列「显示排期、编辑意图」（设计 §2）：显示值可能由依赖推后，
    /// 弹层里要落在用户实际设置的那一天，否则「已选中」与「能清除」会指向两个不同的日期。
    private var selection: Date? {
        switch column {
        case .start:
            return row.startDate ?? row.scheduledStart
        case .finish:
            return value
        default:
            return nil
        }
    }

    private var label: String {
        column == .start ? "开始" : "结束"
    }

    /// 无障碍标签：与检查器同一措辞（「开始日期」/「结束日期」）。
    private var accessibilityLabel: String {
        column == .start ? "开始日期" : "结束日期"
    }

    private var foreground: Color {
        guard isEnabled else { return DesignTokens.textSecondary }
        return row.isOverdue
            ? DesignTokens.semanticText(DesignTokens.overdue, isSelected: isSelected)
            : DesignTokens.textPrimary
    }

    /// tooltip：禁用时说明原因；开始列启用态说明「显示排期、编辑意图」的口径差异（设计 §2）。
    private var helpText: String? {
        guard isEnabled else { return disabledReason }
        return column == .start ? "设置为最早开始日期；依赖可能使排期后移" : nil
    }

    // MARK: - 交互

    private func toggle() {
        // 行级 tap 手势会被单元格手势抢先吃掉，选中在这里主动同步（设计 §3.2 / R1）；
        // 禁用行同样同步选中，只是不开弹层——点禁用格仍能选中该行，不至于「点了没反应」。
        onOpen()
        guard isEnabled else { return }
        // 弹层已开时点击就是关闭（toggle），不重新定位浏览月。
        guard !isPresented else {
            isPresented = false
            return
        }
        // 首次打开定位到选中值所在月；只有外部改动（撤销、画布拖拽、检查器改写）
        // 才重新定位，否则保留用户上次翻到的月份。
        let changedExternally = hasKnownValue && !isSameDay(knownValue, selection)
        if !hasKnownValue || changedExternally {
            visibleMonth = CalendarGrid.month(containing: selection ?? Date()).firstDay
        }
        knownValue = selection
        hasKnownValue = true
        isPresented = true
    }

    private func commit(_ date: Date?) {
        knownValue = date
        hasKnownValue = true
        if let date {
            visibleMonth = CalendarGrid.month(containing: date).firstDay
        }
        isPresented = false
        onCommit(date)
    }

    private func isSameDay(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return Calendar.current.isDate(lhs, inSameDayAs: rhs)
        default: return false
        }
    }

    /// 弹层预览行：「开始 2026-10-22」/「结束 2026-10-25 · 4 天」。
    private func previewText(for candidate: Date?) -> String? {
        guard let candidate else { return nil }
        guard column == .finish,
              let start = row.scheduledStart,
              let days = ScheduleDateMath.durationDays(start: start, finish: candidate) else {
            return "\(label) \(Display.isoDate(candidate))"
        }
        return "\(label) \(Display.isoDate(candidate)) · \(Display.duration(days))"
    }
}

/// 只在有文案时附加 tooltip（空文案不生成 tooltip）。
///
/// 用 modifier 包住条件分支，调用方视图保持单一类型：`if let / else` 换分支会换视图类型，
/// 连带丢掉单元格的 `@State`（弹层开关、浏览月）。
private struct OutlineDateHelpModifier: ViewModifier {
    let text: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
        }
    }
}

/// 就地文本编辑：单击选中，双击进入编辑，Return 提交，Esc 取消。
private struct EditableTextCell: View {
    let text: String
    let value: String
    let enabled: Bool
    let onCommit: (String) -> Void

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: DesignTokens.bodyFontSize))
                    .focused($focused)
                    .onSubmit { commit() }
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commit() }
                    }
            } else {
                Text(text)
                    .font(.system(size: DesignTokens.bodyFontSize))
                    .foregroundStyle(enabled ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        guard enabled else { return }
                        draft = value
                        editing = true
                        DispatchQueue.main.async { focused = true }
                    }
            }
        }
        .padding(.horizontal, 4)
    }

    private func commit() {
        guard editing else { return }
        editing = false
        focused = false
        onCommit(draft)
    }
}
