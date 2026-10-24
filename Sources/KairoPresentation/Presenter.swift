import Foundation
import KairoCore

/// 平台中立 Presenter（ADR-013）：纯函数，把项目值快照与视图状态映射为工作台快照。
/// 不持有 `Project`，不访问时间与全局日历以外的环境；相同输入（含固定 `now`）产生相同输出。
public enum WorkspacePresenter {
    public static func make(
        state: ProjectState,
        schedule: ScheduleResult?,
        violations: [Violation],
        viewState: WorkspaceViewState,
        viewport: WorkspaceViewport,
        calendar: Calendar = Calendar(identifier: .gregorian),
        locale: Locale,
        now: Date,
        saveState: SaveState = .saved
    ) -> WorkspaceSnapshot {
        let tasks = state.tasks
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let today = calendar.startOfDay(for: now)

        var childrenByParent: [UUID: [UUID]] = [:]
        for task in tasks {
            if let parent = task.parentID, byID[parent] != nil {
                childrenByParent[parent, default: []].append(task.id)
            }
        }

        // 排期索引：`ScheduleResult.scheduled(_:)` 为线性查找，先在边界处建索引，
        // 避免 1000 任务快照退化为二次复杂度。
        let scheduledByID = Dictionary(
            uniqueKeysWithValues: (schedule?.tasks ?? []).map { ($0.taskID, $0) }
        )
        let unscheduledIDs = Set(schedule?.unscheduledTaskIDs ?? [])
        func validSchedule(_ id: UUID) -> ScheduledTask? {
            guard !unscheduledIDs.contains(id) else { return nil }
            return scheduledByID[id]
        }

        // 过滤：解析出子句才启用；纯文本不启用，与工具栏 AI 徽标同源。
        let trimmedFilter = viewState.filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let clauses = trimmedFilter.isEmpty ? [] : AIFilterTranslator.translate(trimmedFilter)
        let filterActive = !clauses.isEmpty
        let matchedIDs: Set<UUID>? = filterActive
            ? Set(tasks.filter { task in
                clauses.allSatisfy { clause in
                    switch clause {
                    case .overdue:
                        return ProjectSummary.isOverdue(
                            task,
                            plannedFinish: validSchedule(task.id)?.scheduledFinish,
                            now: today,
                            calendar: calendar
                        )
                    case .dueToday:
                        guard let due = task.dueDate else { return false }
                        return calendar.isDate(due, inSameDayAs: today)
                    case .term:
                        return !AIFilterTranslator.apply(clauses: [clause], to: [task]).isEmpty
                    }
                }
            }.map(\.id))
            : nil

        let tree = OutlineTree(
            tasks: tasks,
            schedule: schedule,
            expanded: viewState.expandedTaskIDs,
            matchedIDs: matchedIDs,
            violations: violations,
            calendar: calendar
        )

        // 全量树：为收起/筛选隐藏的任务提供群组聚合与检查器指标。
        let allParentIDs = Set(tasks.compactMap(\.parentID))
        let fullTree = OutlineTree(
            tasks: tasks,
            schedule: schedule,
            expanded: allParentIDs,
            matchedIDs: nil,
            violations: violations,
            calendar: calendar
        )
        let fullRowByID = Dictionary(uniqueKeysWithValues: fullTree.rows.map { ($0.id, $0) })

        var descendantCache: [UUID: Set<UUID>] = [:]
        func descendants(of id: UUID) -> Set<UUID> {
            if let cached = descendantCache[id] { return cached }
            var result: Set<UUID> = []
            var stack = childrenByParent[id] ?? []
            while let current = stack.popLast() {
                guard result.insert(current).inserted else { continue }
                stack.append(contentsOf: childrenByParent[current] ?? [])
            }
            descendantCache[id] = result
            return result
        }

        func isLeaf(_ task: TaskItem) -> Bool {
            task.kind != .group && (childrenByParent[task.id] ?? []).isEmpty
        }

        func plannedFinish(_ task: TaskItem) -> Date? {
            validSchedule(task.id)?.scheduledFinish
        }

        func deadlineRisk(for task: TaskItem, finish: Date?) -> Bool {
            guard let due = task.dueDate, task.status != .done, let finish else { return false }
            return finish > due
        }

        // 违例严重级：按任务直接归属，群组另聚合子树。
        var severityByTask: [UUID: Violation.Severity] = [:]
        for violation in violations {
            guard let id = violation.taskID else { continue }
            if violation.severity == .error || severityByTask[id] == nil {
                severityByTask[id] = violation.severity
            }
        }
        func subtreeSeverity(_ id: UUID, aggregate: Bool) -> Violation.Severity? {
            var ids = Set([id])
            if aggregate { ids.formUnion(descendants(of: id)) }
            if ids.contains(where: { severityByTask[$0] == .error }) { return .error }
            if ids.contains(where: { severityByTask[$0] != nil }) { return .warning }
            return nil
        }

        let criticalIDs: Set<UUID> = {
            guard let schedule else { return [] }
            let entries = CriticalPathEngine.compute(result: schedule)
            return Set(entries.filter { entry in
                guard entry.isCritical, let scheduled = validSchedule(entry.taskID),
                      scheduled.durationDays > 0 else { return false }
                return true
            }.map(\.taskID))
        }()

        func isOverdueRow(_ task: TaskItem) -> Bool {
            if isLeaf(task) {
                return ProjectSummary.isOverdue(
                    task,
                    plannedFinish: plannedFinish(task),
                    now: today,
                    calendar: calendar
                )
            }
            guard task.kind == .group else {
                // 非群组但有子项的旧数据：按自身口径显示。
                return ProjectSummary.isOverdue(
                    task,
                    plannedFinish: plannedFinish(task),
                    now: today,
                    calendar: calendar
                )
            }
            for id in descendants(of: task.id) {
                guard let descendant = byID[id], isLeaf(descendant) else { continue }
                if ProjectSummary.isOverdue(
                    descendant,
                    plannedFinish: plannedFinish(descendant),
                    now: today,
                    calendar: calendar
                ) {
                    return true
                }
            }
            return false
        }

        func isCriticalRow(_ task: TaskItem) -> Bool {
            if criticalIDs.contains(task.id) { return true }
            guard task.kind == .group else { return false }
            return descendants(of: task.id).contains { criticalIDs.contains($0) }
        }

        func unscheduledReason(for task: TaskItem, hasSchedule: Bool) -> UnscheduledReason? {
            guard !hasSchedule else { return nil }
            if task.kind == .group {
                return (childrenByParent[task.id] ?? []).isEmpty ? .emptyGroup : .unavailable
            }
            if schedule?.cycleTaskIDs.contains(task.id) == true { return .cycle }
            return .unavailable
        }

        // 大纲编号按可见树计算；筛选时编号反映当前可见层级。
        // `counters[d]` 记录层级 d 的当前序号；进入更深层级时补位，返回上层时保留上层计数。
        // 先整体算出 任务 ID → 大纲编号 映射（US-E4-01-C4：前置列展示前置任务编号需全量可见行）。
        var counters: [Int] = []
        var outlineNumberByID: [UUID: String] = [:]
        outlineNumberByID.reserveCapacity(tree.rows.count)
        for row in tree.rows {
            let level = row.depth + 1
            if counters.count > level { counters.removeLast(counters.count - level) }
            while counters.count < level { counters.append(0) }
            counters[row.depth] += 1
            outlineNumberByID[row.task.id] = counters.map(String.init).joined(separator: ".")
        }

        counters = []
        var planRows: [PlanRow] = []
        planRows.reserveCapacity(tree.rows.count)
        for row in tree.rows {
            let task = row.task
            let level = row.depth + 1
            if counters.count > level { counters.removeLast(counters.count - level) }
            while counters.count < level { counters.append(0) }
            counters[row.depth] += 1
            let number = counters.map(String.init).joined(separator: ".")

            let isGroup = task.kind == .group
            let fullRow = fullRowByID[task.id]
            let start = isGroup ? (fullRow?.aggregateStart ?? row.aggregateStart) : row.scheduledStart
            let finish = isGroup ? (fullRow?.aggregateFinish ?? row.aggregateFinish) : row.scheduledFinish
            let hasSchedule = isGroup ? (start != nil && finish != nil) : (finish != nil)
            let duration: Double? = {
                if isGroup { return fullRow?.aggregateDurationDays ?? row.aggregateDurationDays }
                if let scheduled = validSchedule(task.id) {
                    return scheduled.durationDays
                }
                return task.durationDays
            }()

            planRows.append(PlanRow(
                id: task.id,
                depth: row.depth,
                outlineNumber: number,
                kind: task.kind,
                title: task.title,
                status: isGroup ? row.aggregateStatus : task.status,
                priority: task.priority,
                scheduledStart: start,
                scheduledFinish: finish,
                durationDays: duration,
                assignee: task.assignee,
                predecessorsText: Self.predecessorsText(
                    task.dependencies, outlineNumberByID: outlineNumberByID
                ),
                progress: row.aggregateProgress,
                isAggregate: isGroup,
                hasChildren: row.hasChildren,
                isExpanded: row.isExpanded,
                isOverdue: isOverdueRow(task),
                deadlineRisk: deadlineRisk(for: task, finish: finish),
                violationSeverity: subtreeSeverity(task.id, aggregate: isGroup),
                violationCount: row.violationCount,
                isCritical: isCriticalRow(task),
                hasSchedule: hasSchedule,
                unscheduledReason: unscheduledReason(for: task, hasSchedule: hasSchedule),
                isHighlighted: viewState.highlightedTaskID == task.id,
                // 意图起点只对非群组行有意义：群组的起止一律是子任务聚合值（口径与 `start` 一致）。
                startDate: isGroup ? nil : task.startDate
            ))
        }

        let rowIndexByID = Dictionary(uniqueKeysWithValues: planRows.enumerated().map { ($0.element.id, $0.offset) })
        let rowByID = Dictionary(uniqueKeysWithValues: planRows.map { ($0.id, $0) })

        let outlineEmptyReason: EmptyReason? = {
            guard planRows.isEmpty else { return nil }
            if tasks.isEmpty { return .noTasks }
            if filterActive || !trimmedFilter.isEmpty { return .noMatches }
            return nil
        }()

        let outline = OutlineSnapshot(
            rows: planRows,
            // 列集合与视图共用同一策略（F-14-20）：阈值降级优先，用户隐藏只能进一步收窄。
            columns: OutlineColumnPreferences.visibleColumns(
                outlineWidth: viewState.outlineWidth,
                hidden: Set(viewState.hiddenOutlineColumns.compactMap(OutlineColumn.init(rawValue:))),
                focused: viewState.chartFocused
            ),
            filterExplanation: filterActive ? AIFilterTranslator.summary(for: clauses) : nil,
            emptyReason: outlineEmptyReason,
            hiddenByCollapseCount: tree.hiddenByCollapseCount,
            hiddenByFilterCount: tree.hiddenByFilterCount
        )

        let gantt = makeGantt(
            tasks: tasks,
            rowByID: rowByID,
            rowIndexByID: rowIndexByID,
            schedule: schedule,
            viewState: viewState,
            viewport: viewport,
            today: today,
            calendar: calendar,
            locale: locale,
            childrenByParent: childrenByParent,
            criticalIDs: criticalIDs
        )

        let summary = ProjectSummary(
            tasks: tasks,
            schedule: schedule,
            violations: violations,
            now: now,
            calendar: calendar
        )

        let inspector = makeInspector(
            state: state,
            tasks: tasks,
            byID: byID,
            fullRowByID: fullRowByID,
            validSchedule: validSchedule,
            violations: violations,
            viewState: viewState,
            summary: summary,
            saveState: saveState,
            today: today,
            calendar: calendar,
            childrenByParent: childrenByParent,
            isLeaf: isLeaf,
            plannedFinish: plannedFinish,
            deadlineRisk: deadlineRisk,
            unscheduledReason: unscheduledReason
        )

        let statusBar = StatusBarSnapshot(
            health: summary.health,
            weightedProgress: summary.totalProgress,
            overdueCount: summary.overdueCount,
            violationErrorCount: summary.errorCount,
            violationWarningCount: summary.warningCount,
            criticalPathCount: summary.criticalPathCount,
            remainingDays: summary.remainingDays,
            saveState: saveState,
            visibleStart: gantt.windowStart,
            visibleEnd: gantt.windowEnd,
            todayVisible: gantt.todayX != nil,
            hiddenTaskCount: tree.hiddenByCollapseCount + tree.hiddenByFilterCount,
            selectionSummary: viewState.selectedTaskID.flatMap { byID[$0]?.title },
            zoom: ZoomIndicator(
                preset: zoomPreset(viewState),
                pointsPerDay: Self.renderableDayWidth(gantt.dayWidth)
            )
        )

        return WorkspaceSnapshot(
            outline: outline,
            gantt: gantt,
            inspector: inspector,
            statusBar: statusBar,
            generatedAt: now
        )
    }

    // MARK: - 画布

    private static func makeGantt(
        tasks: [TaskItem],
        rowByID: [UUID: PlanRow],
        rowIndexByID: [UUID: Int],
        schedule: ScheduleResult?,
        viewState: WorkspaceViewState,
        viewport: WorkspaceViewport,
        today: Date,
        calendar: Calendar,
        locale: Locale,
        childrenByParent: [UUID: [UUID]],
        criticalIDs: Set<UUID>
    ) -> GanttSnapshot {
        // 布局 v2 自身剔除 `unscheduledTaskIDs`；这里保留过滤作为输入防御，
        // 避免调用方传入的历史结果把无排期条目带进内容范围与条体。
        let layoutSchedule = schedule.map { result in
            let unscheduled = Set(result.unscheduledTaskIDs)
            return ScheduleResult(
                tasks: result.tasks.filter { !unscheduled.contains($0.taskID) },
                projectStart: result.projectStart,
                projectEnd: result.projectEnd,
                direction: result.direction,
                cycleTaskIDs: result.cycleTaskIDs,
                projectStartDerived: result.projectStartDerived,
                unscheduledTaskIDs: result.unscheduledTaskIDs
            )
        }
        let content = GanttLayoutEngine.contentRange(
            tasks: tasks,
            schedule: layoutSchedule,
            calendar: calendar
        )
        // 适合项目时在末尾补一天：零持续的里程碑恰好落在内容终点，
        // 半开窗口 `[start, end)` 会把它裁掉。
        let fitRange = content.map {
            DateInterval(start: $0.start, end: $0.end.addingTimeInterval(86_400))
        }
        // 生效日宽：自定义优先（即便状态里 fit 与自定义同时为真），
        // 其次「适合项目」的 fit 宽度，最后才是档位默认宽度。
        // 夹取只作用于自定义路径；fit 宽度不夹取，保持既有 fit 输出不变。
        let custom = viewState.customDayWidth.map(GanttScale.clampDayWidth)
        let canFit = viewState.usesFitZoom && custom == nil
            && fitRange != nil && viewport.canvasWidth > 0
        let fitWidth: Double? = canFit
            ? fitRange.map {
                GanttLayoutEngine.fitDayWidth(
                    contentRange: $0,
                    viewWidth: viewport.canvasWidth,
                    calendar: calendar
                )
            }
            : nil
        let dayWidthOverride = custom ?? fitWidth
        // 核心内部同样以 `max(dayWidth, 0.5)` 兜底；此处引用同一常量
        // （`GanttScale.minimumDayWidth`），避免两侧的日宽下限各自漂移。
        // 自定义路径下该值恒等于 `custom`（已夹取到 ≥ 2，高于核心下限）。
        let effectiveDayWidth = max(
            dayWidthOverride ?? viewState.zoom.dayWidth,
            GanttScale.minimumDayWidth
        )
        // 核心 `zoom` 入参（生效刻度档位）：
        // - 自定义日宽路径：由实际生效日宽推导刻度粒度（≥18 逐日 / ≥6 逐周 / 其余逐月）。
        // - 预设档位与「适合项目」：沿用 `viewState.zoom`，与本功能引入前逐位一致（A7 门禁）。
        let engineZoom: GanttZoom = custom == nil
            ? viewState.zoom
            : GanttScale.tickUnit(forDayWidth: effectiveDayWidth)
        let requestedStart = viewState.windowStart ?? content?.start ?? today

        let layout = GanttLayoutEngine.make(
            tasks: tasks,
            schedule: layoutSchedule,
            calendar: calendar,
            locale: locale,
            zoom: engineZoom,
            viewWidth: max(viewport.canvasWidth, 1),
            windowStart: requestedStart,
            dayWidthOverride: dayWidthOverride,
            rowIndexByTaskID: rowIndexByID,
            rowHeight: 28,
            today: today
        )

        let todayX = layout.todayX

        var bars: [GanttBar] = []
        bars.reserveCapacity(layout.bars.count)
        for bar in layout.bars {
            guard let index = rowIndexByID[bar.taskID],
                  let row = rowByID[bar.taskID] else { continue }
            let childCount = childrenByParent[bar.taskID]?.isEmpty == false
                ? descendantCount(of: bar.taskID, childrenByParent: childrenByParent)
                : 0
            bars.append(GanttBar(
                taskID: bar.taskID,
                rowIndex: index,
                x: bar.x,
                width: bar.width,
                kind: bar.isMilestone ? .milestone : (bar.isGroup ? .group : .task),
                progress: bar.progress,
                isCritical: bar.isCritical || row.isCritical,
                isOverdue: row.isOverdue,
                violationCount: row.violationCount,
                isCollapsedGroup: bar.isGroup && row.hasChildren && !row.isExpanded,
                childCount: bar.isGroup ? childCount : 0
            ))
        }

        let ticks = layout.ticks.map {
            GanttTick(date: $0.date, x: $0.x, label: $0.label, isMajor: $0.tier == .upper)
        }
        let bands = layout.bands.map { GanttBand(x: $0.x, width: $0.width) }
        let dependencies = layout.dependencyRoutes.map { route in
            GanttDependency(
                predecessorID: route.predecessorID,
                successorID: route.successorID,
                type: route.type,
                isCritical: route.isCritical,
                segments: route.segments.map {
                    GanttSegment(
                        startX: $0.startX, startY: $0.startY,
                        endX: $0.endX, endY: $0.endY
                    )
                }
            )
        }

        let emptyReason: EmptyReason? = {
            if tasks.isEmpty { return .noTasks }
            if rowByID.isEmpty { return .noMatches }
            if !rowByID.values.contains(where: \.hasSchedule) { return .noSchedule }
            return nil
        }()

        return GanttSnapshot(
            windowStart: layout.windowStart,
            windowEnd: layout.windowEnd,
            contentStart: layout.contentStart,
            contentEnd: layout.contentEnd,
            dayWidth: layout.dayWidth,
            zoom: viewState.zoom,
            usesFitZoom: canFit,
            today: today,
            todayX: todayX,
            todayOutOfRange: todayX == nil,
            bars: bars,
            dependencies: dependencies,
            ticks: ticks,
            bands: bands,
            emptyReason: emptyReason,
            projectStartDerived: schedule?.projectStartDerived ?? false,
            showsCriticalPath: viewState.showCriticalPath,
            showsBarLabels: viewState.showBarLabels,
            tickGranularity: engineZoom
        )
    }

    private static func descendantCount(
        of id: UUID,
        childrenByParent: [UUID: [UUID]]
    ) -> Int {
        var result: Set<UUID> = []
        var stack = childrenByParent[id] ?? []
        while let current = stack.popLast() {
            guard result.insert(current).inserted else { continue }
            stack.append(contentsOf: childrenByParent[current] ?? [])
        }
        return result.count
    }

    // MARK: - 检查器

    private static func makeInspector(
        state: ProjectState,
        tasks: [TaskItem],
        byID: [UUID: TaskItem],
        fullRowByID: [UUID: OutlineRow],
        validSchedule: (UUID) -> ScheduledTask?,
        violations: [Violation],
        viewState: WorkspaceViewState,
        summary: ProjectSummary,
        saveState: SaveState,
        today: Date,
        calendar: Calendar,
        childrenByParent: [UUID: [UUID]],
        isLeaf: (TaskItem) -> Bool,
        plannedFinish: (TaskItem) -> Date?,
        deadlineRisk: (TaskItem, Date?) -> Bool,
        unscheduledReason: (TaskItem, Bool) -> UnscheduledReason?
    ) -> InspectorSnapshot {
        if viewState.inspectorTab == .violations {
            return InspectorSnapshot(
                content: .violations(makeViolationInspector(violations, byID: byID)),
                tab: .violations,
                locked: viewState.inspectorLocked,
                selectionMissing: false
            )
        }

        let selectedTask = viewState.selectedTaskID.flatMap { byID[$0] }
        if let task = selectedTask {
            let content = makeTaskInspector(
                task: task,
                tasks: tasks,
                byID: byID,
                fullRow: fullRowByID[task.id],
                validSchedule: validSchedule,
                violations: violations,
                assignments: state.resources,
                today: today,
                calendar: calendar,
                childrenByParent: childrenByParent,
                isLeaf: isLeaf,
                plannedFinish: plannedFinish,
                deadlineRisk: deadlineRisk,
                unscheduledReason: unscheduledReason
            )
            return InspectorSnapshot(
                content: .task(content),
                tab: .inspector,
                locked: viewState.inspectorLocked,
                selectionMissing: false
            )
        }

        let project = ProjectInspector(
            title: state.metadata.title,
            projectStart: state.metadata.projectStart,
            projectEnd: state.metadata.projectEnd,
            direction: state.metadata.direction,
            summary: summary,
            recentCompletions: recentCompletions(tasks: tasks),
            saveState: saveState
        )
        return InspectorSnapshot(
            content: .project(project),
            tab: .inspector,
            locked: viewState.inspectorLocked,
            selectionMissing: viewState.selectedTaskID != nil
        )
    }

    private static func makeTaskInspector(
        task: TaskItem,
        tasks: [TaskItem],
        byID: [UUID: TaskItem],
        fullRow: OutlineRow?,
        validSchedule: (UUID) -> ScheduledTask?,
        violations: [Violation],
        assignments: [Resource],
        today: Date,
        calendar: Calendar,
        childrenByParent: [UUID: [UUID]],
        isLeaf: (TaskItem) -> Bool,
        plannedFinish: (TaskItem) -> Date?,
        deadlineRisk: (TaskItem, Date?) -> Bool,
        unscheduledReason: (TaskItem, Bool) -> UnscheduledReason?
    ) -> TaskInspector {
        let isGroup = task.kind == .group
        let full = fullRow
        let scheduled = validSchedule(task.id)

        let start: Date?
        let finish: Date?
        if isGroup {
            start = full?.aggregateStart
            finish = full?.aggregateFinish
        } else {
            start = scheduled?.scheduledStart
            finish = scheduled?.scheduledFinish
        }
        let hasSchedule = isGroup ? (start != nil && finish != nil) : (scheduled != nil)
        let duration = isGroup
            ? full?.aggregateDurationDays
            : (scheduled?.durationDays ?? task.durationDays)

        let resourceByID = Dictionary(uniqueKeysWithValues: assignments.map { ($0.id, $0) })
        let assignmentNames = task.assignments.compactMap { resourceByID[$0.resourceID]?.name }

        let predecessors = task.dependencies.map { dependency in
            DependencyRow(
                taskID: dependency.predecessorID,
                title: byID[dependency.predecessorID]?.title ?? "（已删除任务）",
                type: dependency.type,
                lagDays: dependency.lagDays,
                isScheduled: validSchedule(dependency.predecessorID) != nil
            )
        }

        var successors: [DependencyRow] = []
        for candidate in tasks {
            for dependency in candidate.dependencies where dependency.predecessorID == task.id {
                successors.append(DependencyRow(
                    taskID: candidate.id,
                    title: candidate.title,
                    type: dependency.type,
                    lagDays: dependency.lagDays,
                    isScheduled: validSchedule(candidate.id) != nil
                ))
            }
        }

        let overdue: Bool
        if isGroup {
            overdue = descendantTaskIDs(of: task.id, childrenByParent: childrenByParent)
                .compactMap { byID[$0] }
                .filter { isLeaf($0) }
                .contains { leaf in
                    ProjectSummary.isOverdue(
                        leaf,
                        plannedFinish: plannedFinish(leaf),
                        now: today,
                        calendar: calendar
                    )
                }
        } else {
            overdue = ProjectSummary.isOverdue(
                task,
                plannedFinish: plannedFinish(task),
                now: today,
                calendar: calendar
            )
        }

        return TaskInspector(
            taskID: task.id,
            title: task.title,
            kind: task.kind,
            status: isGroup ? (full?.aggregateStatus ?? task.status) : task.status,
            priority: task.priority,
            tags: task.tags,
            assignee: task.assignee,
            notes: task.notes,
            scheduledStart: start,
            scheduledFinish: finish,
            durationDays: duration,
            effortHours: task.effortHours,
            slackDays: scheduled?.totalSlackDays,
            dueDate: task.dueDate,
            deadlineRisk: deadlineRisk(task, finish),
            isOverdue: overdue,
            progress: isGroup ? (full?.aggregateProgress ?? 0) : task.progress,
            completedAt: task.completedAt,
            constraint: task.constraint,
            schedulingPolicy: task.schedulingPolicy,
            isAggregate: isGroup,
            hasSchedule: hasSchedule,
            unscheduledReason: unscheduledReason(task, hasSchedule),
            predecessors: predecessors,
            successors: successors,
            violations: violations.filter { $0.taskID == task.id },
            assignmentNames: assignmentNames,
            startDate: isGroup ? nil : task.startDate
        )
    }

    private static func descendantTaskIDs(
        of id: UUID,
        childrenByParent: [UUID: [UUID]]
    ) -> [UUID] {
        var result: [UUID] = []
        var seen: Set<UUID> = []
        var stack = childrenByParent[id] ?? []
        while let current = stack.popLast() {
            guard seen.insert(current).inserted else { continue }
            result.append(current)
            stack.append(contentsOf: childrenByParent[current] ?? [])
        }
        return result
    }

    private static func makeViolationInspector(
        _ violations: [Violation],
        byID: [UUID: TaskItem]
    ) -> ViolationInspector {
        let items = violations.map { violation in
            ViolationItem(
                code: violation.code,
                reason: violation.reason,
                severity: violation.severity,
                taskID: violation.taskID,
                taskTitle: violation.reason.taskTitle
                    ?? violation.taskID.flatMap { byID[$0]?.title }
            )
        }
        var groups: [ViolationInspector.Group] = []
        let errors = items.filter { $0.severity == .error }
        let warnings = items.filter { $0.severity == .warning }
        if !errors.isEmpty {
            groups.append(ViolationInspector.Group(severity: .error, items: errors))
        }
        if !warnings.isEmpty {
            groups.append(ViolationInspector.Group(severity: .warning, items: warnings))
        }
        return ViolationInspector(
            groups: groups,
            errorCount: errors.count,
            warningCount: warnings.count
        )
    }

    private static func recentCompletions(tasks: [TaskItem]) -> [CompletedTask] {
        tasks
            .filter { $0.status == .done && $0.completedAt != nil }
            .sorted {
                if $0.completedAt == $1.completedAt { return $0.title < $1.title }
                return ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
            }
            .prefix(5)
            .map { CompletedTask(id: $0.id, title: $0.title, completedAt: $0.completedAt!) }
    }

    /// 缩放档位（F-0704）：只回语义档位，档位名由视图按 statusbar.zoom.<rawValue> 渲染。
    ///
    /// 自定义优先：自定义日宽生效时不再显示任何预设档位（与「适合项目」同真时亦然）。
    static func zoomPreset(_ viewState: WorkspaceViewState) -> ZoomPreset {
        if viewState.customDayWidth != nil { return .custom }
        if viewState.usesFitZoom { return .fit }
        switch viewState.zoom {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        }
    }

    /// 快照可承载的日宽读数。
    ///
    /// 非有限值（NaN / ±∞）与超出可表示范围的值返回 nil，由视图出占位符——
    /// 原实现直接在核心侧格式化成 "—"，那是文案，不属于快照（ADR-013）。
    static func renderableDayWidth(_ dayWidth: Double) -> Double? {
        guard dayWidth.isFinite, dayWidth.magnitude <= 1e15 else { return nil }
        return dayWidth
    }

    /// 前置任务摘要：`1:fs`，带延隔时 `1:fs+1.5`，多项逗号分隔（US-E4-01-C4 以大纲编号展示）。
    /// 前置任务不在当前可见行（折叠/筛选隐藏）时回退到 ID 前缀。
    static func predecessorsText(
        _ dependencies: [TaskDependency],
        outlineNumberByID: [UUID: String]
    ) -> String {
        dependencies.map { dep in
            let number = outlineNumberByID[dep.predecessorID]
                ?? String(dep.predecessorID.uuidString.prefix(4).uppercased())
            var text = "\(number):\(dep.type.rawValue)"
            if dep.lagDays != 0 {
                text += "+\(contractDecimal(dep.lagDays))"
            }
            return text
        }
        .joined(separator: ", ")
    }

    /// 契约格式的数字（前置延隔天数）：与 Locale 无关的定点输出。
    ///
    /// 旧实现用 Double.formatted()，小数点随系统 Locale 变化（1.5 / 1,5），
    /// 而该字符串进快照、被 AppTests 逐字断言——属契约格式，必须钉死。
    /// 整数值不带小数位（+2），非整数保留 1 位（+1.5 / +-1.5 沿用既有拼接）。
    static func contractDecimal(_ value: Double) -> String {
        guard value.isFinite else { return String(value) }
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded(), rounded.magnitude <= 1e15 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}
