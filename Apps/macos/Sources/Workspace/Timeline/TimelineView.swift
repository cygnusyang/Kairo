import SwiftUI
import KairoCore
import KairoPresentation

/// 共用的纵向滚动坐标空间名：大纲与画布在同一滚动容器内。
enum WorkspaceScrollSpace {
    static let name = "kairo-workspace-scroll"
}

/// 两级时间表头（44pt）：上层月/年，下层日/周；拖动平移时间窗。
struct TimelineHeaderView: View {
    @ObservedObject var store: WorkspaceStore
    let gantt: GanttSnapshot
    let width: CGFloat

    @State private var panBaseDate: Date?
    @State private var lastPanDays: Int?

    /// 表头下层标签上限：超出后按 stride 抽稀（网格线不抽稀，保持时间网格完整）。
    private static let maxHeaderLabels = 200

    private var upperTicks: [GanttTick] { gantt.ticks.filter(\.isMajor) }
    private var lowerTicks: [GanttTick] { gantt.ticks.filter { !$0.isMajor } }

    /// 需要绘制标签的下层刻度：数量超上限时按 stride 抽稀，避免标签重叠与绘制量爆炸。
    private var labeledLowerTicks: [GanttTick] {
        let ticks = lowerTicks
        guard ticks.count > Self.maxHeaderLabels else { return ticks }
        let stride = Int((Double(ticks.count) / Double(Self.maxHeaderLabels)).rounded(.up))
        return ticks.enumerated().compactMap { index, tick in
            index % stride == 0 ? tick : nil
        }
    }

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(DesignTokens.surfaceChrome)
            )

            for tick in lowerTicks {
                var line = Path()
                line.move(to: CGPoint(x: tick.x, y: 0))
                line.addLine(to: CGPoint(x: tick.x, y: size.height))
                context.stroke(line, with: .color(DesignTokens.grid), lineWidth: 1)
            }

            for tick in labeledLowerTicks {
                let text = Text(tick.label)
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
                // 逐日档标签居中于日格；周 / 月档左对齐于刻度线。
                let anchor: UnitPoint = gantt.tickGranularity == .day ? .center : .leading
                let x = gantt.tickGranularity == .day
                    ? tick.x + gantt.dayWidth / 2
                    : tick.x + 3
                context.draw(text, at: CGPoint(x: x, y: 33), anchor: anchor)
            }

            for tick in upperTicks {
                let text = Text(tick.label)
                    .font(.system(size: DesignTokens.captionFontSize, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                context.draw(text, at: CGPoint(x: tick.x + 3, y: 11), anchor: .leading)
            }

            var separator = Path()
            separator.move(to: CGPoint(x: 0, y: 22))
            separator.addLine(to: CGPoint(x: size.width, y: 22))
            context.stroke(separator, with: .color(DesignTokens.separator), lineWidth: 1)
        }
        .frame(width: width, height: DesignTokens.headerHeight)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if panBaseDate == nil {
                        panBaseDate = gantt.windowStart
                        lastPanDays = nil
                    }
                    guard let base = panBaseDate else { return }
                    let dayWidth = max(gantt.dayWidth, 1)
                    let days = Int((-value.translation.width / dayWidth).rounded())
                    guard days != lastPanDays else { return }
                    lastPanDays = days
                    let target = Calendar.current.date(byAdding: .day, value: days, to: base) ?? base
                    store.dispatch(.panWindow(to: target))
                }
                .onEnded { _ in
                    panBaseDate = nil
                    lastPanDays = nil
                }
        )
        .help(I18n.t("timeline.pan.help", "Drag to pan the time window"))
    }
}

/// 画布主体：随共用滚动容器移动，只绘制可见行（1000 任务虚拟化）。
///
/// 结构：内容总高由行数决定；`GeometryReader` 读取滚动偏移，
/// 固定高度的 `Canvas` 跟随偏移贴在视口处，按偏移换算行坐标。
struct TimelineBody: View {
    @ObservedObject var store: WorkspaceStore
    let rows: [PlanRow]
    let gantt: GanttSnapshot
    let width: CGFloat
    let viewportHeight: CGFloat

    @State private var hoveredTaskID: UUID?
    /// 画布拖拽状态机（F-14-09）：引用语义跨重渲染持久，手势只驱动不内联逻辑。
    @State private var dragSession: CanvasDragSession?
    /// 点选中的依赖线（视图交互态，不进持久化 view state）。
    @State private var selectedDependencyIndex: Int?
    /// 横向平移上下文（F-14-18）：全进程单例，避免视图重建后监听绑到已销毁的实例。
    private var panContext: HorizontalPanContext { .shared }
    /// 横向平移：空白处拖拽状态机（引用语义，可单测）。
    @State private var panDrag = PanDragSession()

    private var contentHeight: CGFloat {
        CGFloat(rows.count) * DesignTokens.rowHeight
    }

    /// 拖拽状态机懒创建：提交闭包把状态机请求映射为 WorkspaceAction。
    private var drag: CanvasDragSession {
        if let dragSession { return dragSession }
        let session = CanvasDragSession { commit in
            switch commit {
            case .move(let id, let startDate):
                store.dispatch(.canvasEditSchedule(id, startDate: startDate, durationDays: nil))
            case .resize(let id, let startDate, let durationDays):
                store.dispatch(.canvasEditSchedule(id, startDate: startDate, durationDays: durationDays))
            case .link(let taskID, let predecessorID):
                store.dispatch(.addDependency(
                    taskID: taskID, predecessorID: predecessorID,
                    type: .fs, lagDays: 0
                ))
            }
        }
        dragSession = session
        return session
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: width, height: max(contentHeight, 1))
            GeometryReader { geo in
                let offset = max(
                    0,
                    -geo.frame(in: .named(WorkspaceScrollSpace.name)).minY
                )
                Canvas { context, size in
                    draw(context: &context, size: size, offset: offset)
                }
                .frame(width: width, height: viewportHeight)
                .offset(y: offset)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hoveredTaskID = taskID(at: point, offset: offset)
                    case .ended:
                        hoveredTaskID = nil
                    }
                }
                .gesture(SpatialTapGesture().onEnded { value in
                    handleTap(value.location, offset: offset)
                })
                // F-14-09：拖条改期 / 拖端点改持续 / 拖出建依赖（经 CanvasDragSession 节流提交）。
                // F-14-18：空白处拖拽 = 横向平移（同一手势槽位，按命中分派）。
                .simultaneousGesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            handleDragChanged(value, offset: offset)
                        }
                        .onEnded { _ in
                            panDrag.end()
                            drag.finish()
                        }
                )
                // 记录画布视口（AppKit 窗口坐标），供横向滚动命中判断。
                // 不用 `.frame(in: .global)`：SwiftUI 全局空间与 NSEvent 窗口坐标不同源。
                .background(
                    CanvasViewportProbe { window, rect in
                        panContext.attach(window: window, viewportInWindow: rect)
                    }
                )
            }
        }
        .focusable()
        // 依赖线点选后按 Delete/Backspace 删除（仅画布持有焦点时触发，不劫持文本框）。
        .onKeyPress(.delete, phases: .down) { _ in
            deleteSelectedDependency()
        }
        // Escape 取消进行中的拖拽（丢弃预览，不产生提交）。
        .onExitCommand {
            panDrag.cancel()
            drag.cancel()
        }
        .onChange(of: gantt.dependencies) { _, _ in
            // 快照刷新后索引语义失效，清空点选（内容未变时 Equatable 不触发）。
            selectedDependencyIndex = nil
        }
        .onAppear {
            panContext.sync(dayWidth: gantt.dayWidth, windowStart: gantt.windowStart)
            panContext.attach(store: store)
            installScrollMonitorIfNeeded()
        }
        .onChange(of: gantt.windowStart) { _, _ in
            panContext.sync(dayWidth: gantt.dayWidth, windowStart: gantt.windowStart)
        }
        .onChange(of: gantt.dayWidth) { _, _ in
            // 尺度变化后旧余量失去意义，清空避免跳变。
            panContext.resetAccumulator()
            panContext.sync(dayWidth: gantt.dayWidth, windowStart: gantt.windowStart)
        }
        .frame(width: width, alignment: .topLeading)
    }

    /// 横向滚动捕获（F-14-18）：光标在画布内时把横向滚动换算成窗口平移。
    /// 单例监听重复 `start()` 幂等，不产生第二份事件源（D-027）。
    private func installScrollMonitorIfNeeded() {
        HorizontalScrollMonitor.shared.start()
    }

    private func handleTap(_ point: CGPoint, offset: CGFloat) {
        let hit = GanttHitTesting.hitTest(
            pointX: point.x, pointY: point.y, canvasOffset: offset,
            bars: gantt.bars, dependencies: gantt.dependencies,
            rowHeight: DesignTokens.rowHeight, dayWidth: gantt.dayWidth
        )
        if case .dependencyLine(let index) = hit {
            selectedDependencyIndex = index
            return
        }
        selectedDependencyIndex = nil
        guard let id = taskID(at: point, offset: offset) else { return }
        store.dispatch(.select(id))
    }

    private func deleteSelectedDependency() -> KeyPress.Result {
        guard let index = selectedDependencyIndex,
              gantt.dependencies.indices.contains(index) else { return .ignored }
        let dependency = gantt.dependencies[index]
        store.dispatch(.removeDependency(
            taskID: dependency.successorID, predecessorID: dependency.predecessorID
        ))
        selectedDependencyIndex = nil
        return .handled
    }

    private func handleDragChanged(_ value: DragGesture.Value, offset: CGFloat) {
        // 首次回调按起点命中分派：条/端点/环带 → F-14-09 编辑；空白（且该行无条）→ 平移。
        if drag.preview == nil, !panDrag.isActive {
            let target = GanttHitTesting.hitTest(
                pointX: value.startLocation.x, pointY: value.startLocation.y,
                canvasOffset: offset, bars: gantt.bars, dependencies: gantt.dependencies,
                rowHeight: DesignTokens.rowHeight, dayWidth: gantt.dayWidth
            )
            if let bar = draggableBar(for: target) {
                drag.begin(target: target, anchor: anchor(for: bar))
            } else if case .none = target, taskID(at: value.startLocation, offset: offset) == nil {
                // 空白区拖拽平移：群组条所在行不参与（交给点选，避免误移窗口）。
                panDrag.begin(windowStart: gantt.windowStart, dayWidth: gantt.dayWidth)
            } else {
                return
            }
        }
        if panDrag.isActive {
            if let target = panDrag.update(translationX: value.translation.width) {
                store.dispatch(.panWindow(to: target))
            }
            return
        }
        // 连线目标：光标所在行有任务条即为目标（含群组/里程碑）。
        let targetID = taskID(at: value.location, offset: offset)
        drag.update(
            translationX: value.translation.width,
            pointX: value.location.x,
            pointY: value.location.y,
            canvasOffset: offset,
            targetID: targetID
        )
    }

    /// 可拖拽命中的条（依赖线与空白不可拖）。
    private func draggableBar(for target: GanttDragTarget) -> GanttBar? {
        let id: UUID
        switch target {
        case .body(let value), .startHandle(let value), .endHandle(let value),
             .dependencyStart(let value), .dependencyEnd(let value):
            id = value
        case .dependencyLine, .none:
            return nil
        }
        return gantt.bars.first { $0.taskID == id }
    }

    private func anchor(for bar: GanttBar) -> CanvasDragSession.Anchor {
        CanvasDragSession.Anchor(
            bar: bar,
            durationDays: max(bar.width / max(gantt.dayWidth, 0.5), 0),
            windowStart: gantt.windowStart,
            dayWidth: gantt.dayWidth
        )
    }

    private func taskID(at point: CGPoint, offset: CGFloat) -> UUID? {
        let row = Int((point.y + offset) / DesignTokens.rowHeight)
        guard rows.indices.contains(row) else { return nil }
        let id = rows[row].id
        return gantt.bars.first { $0.taskID == id } == nil ? nil : id
    }

    /// 画布高亮的活动任务：悬停优先，否则用当前选中；依赖线据此隔离。
    private var activeTaskID: UUID? {
        hoveredTaskID ?? store.selection
    }

    // MARK: - 绘制

    private func draw(
        context: inout GraphicsContext,
        size: CGSize,
        offset: CGFloat
    ) {
        let rowHeight = DesignTokens.rowHeight
        let firstRow = max(0, Int(offset / rowHeight) - 1)
        let lastRow = min(rows.count - 1, Int((offset + size.height) / rowHeight) + 1)

        drawBands(context: &context, size: size)
        drawRowStates(context: &context, size: size, offset: offset, firstRow: firstRow, lastRow: lastRow)

        var grid = Path()
        for tick in gantt.ticks where !tick.isMajor {
            grid.move(to: CGPoint(x: tick.x, y: 0))
            grid.addLine(to: CGPoint(x: tick.x, y: size.height))
        }
        context.stroke(grid, with: .color(DesignTokens.grid.opacity(0.7)), lineWidth: 1)

        if !rows.isEmpty {
            var rowLines = Path()
            let lineStart = max(firstRow, 0)
            let lineEnd = min(lastRow + 1, rows.count - 1)
            if lineStart <= lineEnd {
                for row in lineStart...lineEnd {
                    let y = CGFloat(row) * rowHeight - offset
                    rowLines.move(to: CGPoint(x: 0, y: y))
                    rowLines.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(rowLines, with: .color(DesignTokens.grid.opacity(0.5)), lineWidth: 0.5)
            }
        }

        if let todayX = gantt.todayX, todayX >= 0, todayX <= size.width {
            var today = Path()
            today.move(to: CGPoint(x: todayX, y: 0))
            today.addLine(to: CGPoint(x: todayX, y: size.height))
            context.stroke(today, with: .color(DesignTokens.today), lineWidth: 1.5)
        }

        drawDependencies(context: &context, size: size, offset: offset)
        drawBars(context: &context, size: size, offset: offset, firstRow: firstRow, lastRow: lastRow)
        drawDragPreview(context: &context, size: size, offset: offset)
    }

    /// 拖拽预览（F-14-09）：拖拽中叠加虚线框 / 连线；无拖拽时零绘制（A7 基线不变）。
    private func drawDragPreview(
        context: inout GraphicsContext,
        size: CGSize,
        offset: CGFloat
    ) {
        guard let session = dragSession, let preview = session.preview else { return }
        switch preview {
        case .bar(let barPreview):
            drawBarPreview(context: &context, size: size, offset: offset, preview: barPreview)
        case .link(let linkPreview):
            drawLinkPreview(context: &context, size: size, offset: offset, preview: linkPreview)
        }
    }

    private func drawBarPreview(
        context: inout GraphicsContext,
        size: CGSize,
        offset: CGFloat,
        preview: CanvasDragSession.BarPreview
    ) {
        let bar = preview.bar
        let top = CGFloat(bar.rowIndex) * DesignTokens.rowHeight - offset
        guard top > -DesignTokens.rowHeight, top < size.height else { return }
        let x = CGFloat(preview.startDay) * gantt.dayWidth
        let previewWidth = CGFloat(preview.durationDays) * gantt.dayWidth

        if bar.kind == .milestone {
            // 里程碑：预览菱形。
            let center = CGPoint(x: x + 5, y: top + 14)
            var diamond = Path()
            diamond.move(to: CGPoint(x: center.x, y: center.y - 5))
            diamond.addLine(to: CGPoint(x: center.x + 5, y: center.y))
            diamond.addLine(to: CGPoint(x: center.x, y: center.y + 5))
            diamond.addLine(to: CGPoint(x: center.x - 5, y: center.y))
            diamond.closeSubpath()
            context.stroke(
                diamond,
                with: .color(DesignTokens.accentStrong.opacity(0.8)),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
            drawPreviewLabel(
                context: &context, size: size,
                text: Self.previewDateText(startDay: preview.startDay, windowStart: gantt.windowStart),
                x: center.x + 9, y: center.y
            )
            return
        }

        let height: CGFloat = bar.kind == .group ? 10 : 14
        let y = top + (DesignTokens.rowHeight - height) / 2
        let rect = CGRect(x: x, y: y, width: max(previewWidth, 1), height: height)
        guard rect.minY < size.height, rect.maxY > 0 else { return }
        context.stroke(
            Path(roundedRect: rect, cornerRadius: bar.kind == .group ? 2 : 3),
            with: .color(DesignTokens.accentStrong.opacity(0.8)),
            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
        )
        var label = Self.previewDateText(startDay: preview.startDay, windowStart: gantt.windowStart)
        if preview.durationDays > 0 {
            let days = Int(preview.durationDays.rounded())
            label += I18n.t("timeline.preview.duration", " · %1$ld days", days)
        }
        drawPreviewLabel(context: &context, size: size, text: label, x: rect.maxX + 6, y: rect.midY)
    }

    private func drawLinkPreview(
        context: inout GraphicsContext,
        size: CGSize,
        offset: CGFloat,
        preview: CanvasDragSession.LinkPreview
    ) {
        // 目标条高亮。
        if let targetID = preview.targetID, let bar = gantt.bars.first(where: { $0.taskID == targetID }) {
            let top = CGFloat(bar.rowIndex) * DesignTokens.rowHeight - offset
            let height: CGFloat = bar.kind == .group ? 10 : 14
            let rect = CGRect(
                x: CGFloat(bar.x), y: top + (DesignTokens.rowHeight - height) / 2,
                width: max(CGFloat(bar.width), 1), height: height
            )
            context.stroke(
                Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 4),
                with: .color(DesignTokens.accentStrong.opacity(0.9)),
                lineWidth: 2
            )
        }
        let source = preview.sourceBar
        let startX = preview.isFromEnd
            ? CGFloat(source.x + max(source.width, 1))
            : CGFloat(source.x)
        let startY = CGFloat(source.rowIndex) * DesignTokens.rowHeight + 14 - offset
        let end = CGPoint(x: preview.pointX, y: preview.pointY - offset)
        var line = Path()
        line.move(to: CGPoint(x: startX, y: startY))
        line.addLine(to: end)
        context.stroke(
            line,
            with: .color(DesignTokens.accentStrong.opacity(0.9)),
            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
        )
        drawArrow(context: &context, from: CGPoint(x: startX, y: startY), to: end, color: DesignTokens.accentStrong.opacity(0.9))
    }

    /// 拖拽预览的日期标签：展示格式，按生效 Locale 出（zh `11月6日`，en `Nov 6`，F-0712）。
    private static func previewDateText(startDay: Int, windowStart: Date) -> String {
        Display.shortMonthDay(windowStart.addingTimeInterval(Double(startDay) * 86_400))
    }

    private func drawPreviewLabel(
        context: inout GraphicsContext,
        size: CGSize,
        text: String,
        x: CGFloat,
        y: CGFloat
    ) {
        guard x < size.width else { return }
        context.draw(
            Text(text)
                .font(.system(size: DesignTokens.captionFontSize, weight: .semibold))
                .foregroundStyle(DesignTokens.accentStrong),
            at: CGPoint(x: x, y: y),
            anchor: .leading
        )
    }

    private func drawBands(context: inout GraphicsContext, size: CGSize) {
        for band in gantt.bands {
            let rect = CGRect(x: band.x, y: 0, width: band.width, height: size.height)
            context.fill(Path(rect), with: .color(DesignTokens.nonWorkingBand))
        }
    }

    private func drawRowStates(
        context: inout GraphicsContext,
        size: CGSize,
        offset: CGFloat,
        firstRow: Int,
        lastRow: Int
    ) {
        guard firstRow <= lastRow, rows.indices.contains(firstRow) else { return }
        for row in firstRow...lastRow {
            let planRow = rows[row]
            let y = CGFloat(row) * DesignTokens.rowHeight - offset
            let rect = CGRect(x: 0, y: y, width: size.width, height: DesignTokens.rowHeight)
            if planRow.id == store.selection {
                context.fill(Path(rect), with: .color(DesignTokens.selection.opacity(0.6)))
            } else if planRow.isHighlighted {
                context.fill(Path(rect), with: .color(DesignTokens.selection.opacity(0.3)))
            } else if planRow.id == hoveredTaskID {
                context.fill(Path(rect), with: .color(DesignTokens.hoverOverlay))
            }
        }
    }

    private func drawDependencies(
        context: inout GraphicsContext,
        size: CGSize,
        offset: CGFloat
    ) {
        for (index, dependency) in gantt.dependencies.enumerated() {
            let related = activeTaskID.map {
                dependency.predecessorID == $0 || dependency.successorID == $0
            } ?? false
            let isSelected = index == selectedDependencyIndex
            let color: Color
            if isSelected {
                color = DesignTokens.accentStrong
            } else if dependency.isCritical && gantt.showsCriticalPath {
                color = DesignTokens.criticalGraphic
            } else {
                color = DesignTokens.dependency
            }
            let opacity: Double = activeTaskID == nil || related || isSelected ? 1 : 0.2
            let baseWidth: CGFloat = dependency.isCritical && gantt.showsCriticalPath ? 1.5 : 1
            let lineWidth: CGFloat = isSelected ? 2.5 : (related ? max(baseWidth, 1.5) : baseWidth)

            var path = Path()
            for segment in dependency.segments {
                path.move(to: CGPoint(x: segment.startX, y: segment.startY - offset))
                path.addLine(to: CGPoint(x: segment.endX, y: segment.endY - offset))
            }
            context.stroke(
                path,
                with: .color(color.opacity(opacity)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            if let last = dependency.segments.last {
                drawArrow(
                    context: &context,
                    from: CGPoint(x: last.startX, y: last.startY - offset),
                    to: CGPoint(x: last.endX, y: last.endY - offset),
                    color: color.opacity(opacity)
                )
            }
        }
    }

    private func drawArrow(
        context: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        color: Color
    ) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let length: CGFloat = 4
        let spread: CGFloat = 3
        let tip = to
        let left = CGPoint(
            x: tip.x - length * cos(angle) + spread * sin(angle),
            y: tip.y - length * sin(angle) - spread * cos(angle)
        )
        let right = CGPoint(
            x: tip.x - length * cos(angle) - spread * sin(angle),
            y: tip.y - length * sin(angle) + spread * cos(angle)
        )
        var path = Path()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    private func drawBars(
        context: inout GraphicsContext,
        size: CGSize,
        offset: CGFloat,
        firstRow: Int,
        lastRow: Int
    ) {
        guard firstRow <= lastRow else { return }
        let byRow = Dictionary(grouping: gantt.bars, by: \.rowIndex)
        for row in firstRow...lastRow {
            guard let bars = byRow[row] else { continue }
            let top = CGFloat(row) * DesignTokens.rowHeight - offset
            for bar in bars {
                drawBar(context: &context, size: size, bar: bar, rowTop: top)
            }
        }
    }

    private func drawBar(
        context: inout GraphicsContext,
        size: CGSize,
        bar: GanttBar,
        rowTop: CGFloat
    ) {
        let title = rows.indices.contains(bar.rowIndex) ? rows[bar.rowIndex].title : ""

        if bar.kind == .milestone {
            let center = CGPoint(x: bar.x + max(bar.width, 0) / 2, y: rowTop + 14)
            var diamond = Path()
            diamond.move(to: CGPoint(x: center.x, y: center.y - 5))
            diamond.addLine(to: CGPoint(x: center.x + 5, y: center.y))
            diamond.addLine(to: CGPoint(x: center.x, y: center.y + 5))
            diamond.addLine(to: CGPoint(x: center.x - 5, y: center.y))
            diamond.closeSubpath()
            context.fill(
                diamond,
                with: .color(bar.isOverdue ? DesignTokens.overdue : DesignTokens.criticalGraphic)
            )
            if bar.taskID == store.selection {
                context.stroke(diamond, with: .color(DesignTokens.accentStrong), lineWidth: 2)
            }
            drawLabel(context: &context, size: size, text: title, x: center.x + 9, y: center.y)
            drawViolationBadge(context: &context, bar: bar, x: center.x + 7, y: rowTop + 4)
            return
        }

        let height: CGFloat = bar.kind == .group ? 10 : 14
        let y = rowTop + (DesignTokens.rowHeight - height) / 2
        let rect = CGRect(x: bar.x, y: y, width: max(bar.width, 1), height: height)
        guard rect.minY < size.height, rect.maxY > 0 else { return }

        let radius: CGFloat = bar.kind == .group ? 2 : 3
        let shape = Path(roundedRect: rect, cornerRadius: radius)
        context.fill(
            shape,
            with: .color(bar.kind == .group
                ? DesignTokens.textSecondary.opacity(0.28)
                : DesignTokens.progressTrack)
        )
        if bar.progress > 0 {
            let fillWidth = rect.width * min(max(bar.progress, 0), 1)
            let fillRect = CGRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
            context.fill(
                Path(roundedRect: fillRect, cornerRadius: radius),
                with: .color(DesignTokens.progressFill)
            )
        }

        if bar.isOverdue {
            context.stroke(shape, with: .color(DesignTokens.overdue), lineWidth: 1.5)
        } else if bar.isCritical && gantt.showsCriticalPath {
            context.stroke(shape, with: .color(DesignTokens.criticalGraphic), lineWidth: 1.5)
        }
        // 选中任务条：accent 外描边盖在逾期/关键描边之上，点击后在画布上立即可辨。
        if bar.taskID == store.selection {
            let outline = Path(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: radius + 1.5)
            context.stroke(outline, with: .color(DesignTokens.accentStrong), lineWidth: 2)
        }

        drawViolationBadge(context: &context, bar: bar, x: rect.maxX + 2, y: rowTop + 4)

        let labelY = rowTop + DesignTokens.rowHeight / 2
        let labelX = rect.maxX + 6
        if labelX + 60 < size.width {
            drawLabel(context: &context, size: size, text: labelText(bar: bar, title: title), x: labelX, y: labelY)
        } else if rect.minX - 66 > 0 {
            let text = Text(labelText(bar: bar, title: title))
                .font(.system(size: DesignTokens.captionFontSize))
                .foregroundStyle(DesignTokens.textPrimary)
            context.draw(text, at: CGPoint(x: rect.minX - 6, y: labelY), anchor: .trailing)
        }
    }

    private func labelText(bar: GanttBar, title: String) -> String {
        if bar.isCollapsedGroup {
            return I18n.t("timeline.bar.collapsed_group", "%1$@ (%2$ld items)", title, bar.childCount)
        }
        return title
    }

    private func drawLabel(
        context: inout GraphicsContext,
        size: CGSize,
        text: String,
        x: CGFloat,
        y: CGFloat
    ) {
        // 条标签在逐月档隐藏（密度过低时标签不可读）；粒度取生效刻度档位。
        guard gantt.showsBarLabels, gantt.tickGranularity != .month else { return }
        guard x < size.width else { return }
        context.draw(
            Text(text)
                .font(.system(size: DesignTokens.captionFontSize))
                .foregroundStyle(DesignTokens.textPrimary),
            at: CGPoint(x: x, y: y),
            anchor: .leading
        )
    }

    private func drawViolationBadge(
        context: inout GraphicsContext,
        bar: GanttBar,
        x: CGFloat,
        y: CGFloat
    ) {
        guard bar.violationCount > 0 else { return }
        var triangle = Path()
        triangle.move(to: CGPoint(x: x, y: y))
        triangle.addLine(to: CGPoint(x: x + 6, y: y))
        triangle.addLine(to: CGPoint(x: x + 3, y: y + 7))
        triangle.closeSubpath()
        context.fill(triangle, with: .color(DesignTokens.violationWarning))
    }
}
