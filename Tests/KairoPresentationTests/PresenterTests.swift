import Foundation
import Testing
import KairoCore
import KairoPresentation

/// 夹具项目名（用户数据，不翻译）：一处定义，避免断言与构造两处字面量漂移。
private let fixtureProjectTitle = "演示项目"

// MARK: - 行对齐与聚合

@Test func rowsAndBarsShareIndexAndOrder() throws {
    let projectStart = makeDate(2025, 1, 1)
    let group = TaskItem(title: "阶段一", kind: .group)
    let design = TaskItem(
        title: "设计",
        startDate: projectStart,
        parentID: group.id,
        durationDays: 2
    )
    let build = TaskItem(
        title: "实现",
        parentID: group.id,
        durationDays: 3,
        dependencies: [TaskDependency(predecessorID: design.id)]
    )
    let release = TaskItem(
        title: "发布",
        kind: .milestone,
        parentID: group.id,
        dependencies: [TaskDependency(predecessorID: build.id)]
    )
    let tasks = [group, design, build, release]
    let state = makeState(tasks, projectStart: projectStart)
    let now = makeDate(2025, 1, 2)
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)
    var viewState = WorkspaceViewState()
    viewState.expandedTaskIDs = [group.id]

    let snapshot = makeSnapshot(state: state, schedule: schedule, viewState: viewState, now: now)

    #expect(snapshot.outline.rows.map(\.id) == tasks.map(\.id))
    #expect(snapshot.outline.rows.map(\.outlineNumber) == ["1", "1.1", "1.2", "1.3"])
    #expect(snapshot.gantt.bars.count == snapshot.outline.rows.count)

    let orderedBars = snapshot.gantt.bars.sorted { $0.rowIndex < $1.rowIndex }
    #expect(orderedBars.map(\.rowIndex) == Array(0..<snapshot.outline.rows.count))
    for bar in orderedBars {
        #expect(snapshot.outline.rows[bar.rowIndex].id == bar.taskID)
    }
}

@Test func collapsedGroupHidesChildrenAndKeepsSummaryBar() throws {
    let projectStart = makeDate(2025, 1, 1)
    let group = TaskItem(title: "阶段一", kind: .group)
    let first = TaskItem(title: "设计", startDate: projectStart, parentID: group.id, durationDays: 2)
    let second = TaskItem(title: "实现", parentID: group.id, durationDays: 2)
    let tasks = [group, first, second]
    let state = makeState(tasks, projectStart: projectStart)
    let now = projectStart
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)

    let snapshot = makeSnapshot(state: state, schedule: schedule, now: now)

    #expect(snapshot.outline.rows.count == 1)
    #expect(snapshot.outline.rows[0].id == group.id)
    #expect(snapshot.outline.hiddenByCollapseCount == 2)
    let bar = try #require(snapshot.gantt.bars.first { $0.taskID == group.id })
    #expect(bar.kind == .group)
    #expect(bar.isCollapsedGroup)
    #expect(bar.childCount == 2)
}

@Test func groupAggregatesWeightedProgressStatusAndRange() throws {
    let projectStart = makeDate(2025, 1, 1)
    let group = TaskItem(title: "阶段一", kind: .group)
    let design = TaskItem(
        title: "设计",
        status: .done,
        parentID: group.id,
        effortHours: 3,
        durationDays: 3,
        progress: 1
    )
    let build = TaskItem(
        title: "实现",
        status: .inProgress,
        parentID: group.id,
        effortHours: 1,
        durationDays: 1,
        dependencies: [TaskDependency(predecessorID: design.id)],
        progress: 0.5
    )
    let tasks = [group, design, build]
    let state = makeState(tasks, projectStart: projectStart)
    let now = projectStart
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)
    var viewState = WorkspaceViewState()
    viewState.expandedTaskIDs = [group.id]

    let snapshot = makeSnapshot(state: state, schedule: schedule, viewState: viewState, now: now)
    let groupRow = try #require(snapshot.outline.rows.first { $0.id == group.id })
    let designSchedule = try #require(schedule.scheduled(design.id))
    let buildSchedule = try #require(schedule.scheduled(build.id))

    #expect(groupRow.isAggregate)
    #expect(abs(groupRow.progress - 0.875) < 0.0001)
    #expect(groupRow.status == .inProgress)
    #expect(groupRow.hasSchedule)
    #expect(groupRow.scheduledStart == designSchedule.scheduledStart)
    #expect(groupRow.scheduledFinish == buildSchedule.scheduledFinish)
    #expect(groupRow.durationDays == 4)
}

// MARK: - 过滤

@Test func filterKeepsAncestorsAndForcesExpansion() throws {
    let projectStart = makeDate(2025, 1, 1)
    let group = TaskItem(title: "阶段一", kind: .group)
    let design = TaskItem(title: "设计评审", parentID: group.id, durationDays: 2)
    let build = TaskItem(title: "开发", parentID: group.id, durationDays: 2)
    let tasks = [group, design, build]
    let state = makeState(tasks, projectStart: projectStart)
    let now = projectStart
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)
    var viewState = WorkspaceViewState()
    viewState.filterText = "设计"

    let snapshot = makeSnapshot(state: state, schedule: schedule, viewState: viewState, now: now)

    #expect(snapshot.outline.rows.map(\.id) == [group.id, design.id])
    #expect(snapshot.outline.rows.map(\.outlineNumber) == ["1", "1.1"])
    #expect(snapshot.outline.hiddenByFilterCount == 1)
    #expect(snapshot.outline.hiddenByCollapseCount == 0)
    #expect(snapshot.outline.filterSummary?.contains("筛选") == true)
    #expect(snapshot.gantt.bars.count == 2)
    #expect(Set(snapshot.gantt.bars.map(\.taskID)) == Set([group.id, design.id]))
}

@Test func unparsedFilterTextDoesNotFilter() {
    let projectStart = makeDate(2025, 1, 1)
    let tasks = [TaskItem(title: "A", startDate: projectStart, durationDays: 1)]
    let state = makeState(tasks, projectStart: projectStart)
    let now = projectStart
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)
    var viewState = WorkspaceViewState()
    viewState.filterText = "!!!"

    let snapshot = makeSnapshot(state: state, schedule: schedule, viewState: viewState, now: now)

    #expect(snapshot.outline.rows.count == 1)
    #expect(snapshot.outline.hiddenByFilterCount == 0)
    #expect(snapshot.outline.filterSummary == nil)
}

// MARK: - 今天线与空态

@Test func todayInsideWindowProducesX() throws {
    let projectStart = makeDate(2025, 1, 1)
    let tasks = [TaskItem(title: "A", startDate: projectStart, durationDays: 3)]
    let state = makeState(tasks, projectStart: projectStart)
    let now = makeDate(2025, 1, 2)
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)

    let snapshot = makeSnapshot(state: state, schedule: schedule, now: now)
    let todayX = try #require(snapshot.gantt.todayX)

    #expect(todayX > 0)
    #expect(todayX < snapshot.gantt.windowEnd.timeIntervalSince(snapshot.gantt.windowStart) / 86_400 * snapshot.gantt.dayWidth)
    #expect(!snapshot.gantt.todayOutOfRange)
    #expect(snapshot.statusBar.todayVisible)
}

@Test func todayOutsideWindowIsMarked() {
    let projectStart = makeDate(2025, 1, 1)
    let tasks = [TaskItem(title: "A", startDate: projectStart, durationDays: 3)]
    let state = makeState(tasks, projectStart: projectStart)
    let now = makeDate(2026, 2, 1)
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)

    let snapshot = makeSnapshot(state: state, schedule: schedule, now: now)

    #expect(snapshot.gantt.todayX == nil)
    #expect(snapshot.gantt.todayOutOfRange)
    #expect(!snapshot.statusBar.todayVisible)
}

@Test func emptyReasonsCoverNoTasksNoMatchesNoSchedule() {
    let now = makeDate(2025, 1, 1)
    let projectStart = makeDate(2025, 1, 1)

    // 空项目
    let emptyState = makeState([], projectStart: projectStart)
    let emptySchedule = makeSchedule([], now: now)
    let emptySnapshot = makeSnapshot(state: emptyState, schedule: emptySchedule, now: now)
    #expect(emptySnapshot.outline.emptyReason == .noTasks)
    #expect(emptySnapshot.gantt.emptyReason == .noTasks)

    // 筛选无结果
    let tasks = [TaskItem(title: "A", startDate: projectStart, durationDays: 1)]
    let state = makeState(tasks, projectStart: projectStart)
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)
    var filterState = WorkspaceViewState()
    filterState.filterText = "zzz"
    let filtered = makeSnapshot(state: state, schedule: schedule, viewState: filterState, now: now)
    #expect(filtered.outline.emptyReason == .noMatches)
    #expect(filtered.gantt.emptyReason == .noMatches)

    // 无排期结果
    let unscheduled = makeSnapshot(state: state, schedule: nil, now: now)
    #expect(unscheduled.outline.rows.count == 1)
    #expect(unscheduled.outline.emptyReason == nil)
    #expect(unscheduled.gantt.emptyReason == .noSchedule)
}

@Test func cycleTasksAreUnscheduledWithReason() throws {
    let projectStart = makeDate(2025, 1, 1)
    let a = TaskItem(title: "A", startDate: projectStart, durationDays: 1)
    let b = TaskItem(
        title: "B",
        durationDays: 1,
        dependencies: [TaskDependency(predecessorID: a.id)]
    )
    let loopingA = TaskItem(
        id: a.id,
        title: a.title,
        startDate: a.startDate,
        durationDays: 1,
        dependencies: [TaskDependency(predecessorID: b.id)]
    )
    let tasks = [loopingA, b]
    let state = makeState(tasks, projectStart: projectStart)
    let now = makeDate(2025, 1, 5)
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)

    let snapshot = makeSnapshot(state: state, schedule: schedule, now: now)

    #expect(snapshot.gantt.bars.isEmpty)
    #expect(snapshot.gantt.emptyReason == .noSchedule)
    for row in snapshot.outline.rows {
        #expect(!row.hasSchedule)
        #expect(row.unscheduledReason == .cycle)
    }
}

// MARK: - 健康、逾期与状态栏

@Test func statusBarMirrorsProjectSummary() throws {
    let projectStart = makeDate(2025, 1, 1)
    let a = TaskItem(title: "A", startDate: projectStart, durationDays: 2)
    let b = TaskItem(
        title: "B",
        dueDate: makeDate(2025, 1, 1),
        durationDays: 1,
        dependencies: [TaskDependency(predecessorID: a.id)]
    )
    let done = TaskItem(
        title: "C",
        dueDate: makeDate(2025, 1, 1),
        status: .done,
        durationDays: 1
    )
    let tasks = [a, b, done]
    let state = makeState(tasks, projectStart: projectStart)
    let now = makeDate(2025, 1, 10)
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)
    let violations = [Violation(reason: .cycle(taskTitle: "A"), taskID: a.id)]
    let summary = ProjectSummary(
        tasks: tasks,
        schedule: schedule,
        violations: violations,
        now: now,
        calendar: testCalendar
    )

    let snapshot = makeSnapshot(
        state: state,
        schedule: schedule,
        violations: violations,
        now: now,
        saveState: .unsaved
    )

    #expect(snapshot.statusBar.health == summary.health)
    #expect(snapshot.statusBar.health == .red)
    #expect(snapshot.statusBar.weightedProgress == summary.totalProgress)
    #expect(snapshot.statusBar.overdueCount == summary.overdueCount)
    #expect(snapshot.statusBar.violationErrorCount == 1)
    #expect(snapshot.statusBar.violationWarningCount == 0)
    #expect(snapshot.statusBar.saveState == .unsaved)
    let rowB = try #require(snapshot.outline.rows.first { $0.id == b.id })
    let rowC = try #require(snapshot.outline.rows.first { $0.id == done.id })
    #expect(rowB.isOverdue)
    #expect(!rowC.isOverdue)
}

@Test func deadlineRiskUsesDueDateAndPlannedFinish() throws {
    let projectStart = makeDate(2025, 1, 1)
    let a = TaskItem(
        title: "A",
        startDate: projectStart,
        dueDate: makeDate(2025, 1, 2),
        durationDays: 3
    )
    let tasks = [a]
    let state = makeState(tasks, projectStart: projectStart)
    let now = projectStart
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)

    let snapshot = makeSnapshot(state: state, schedule: schedule, now: now)
    let row = try #require(snapshot.outline.rows.first)
    let finish = try #require(schedule.scheduled(a.id)?.scheduledFinish)

    #expect(row.deadlineRisk == (finish > makeDate(2025, 1, 2)))
}

@Test func groupViolationSeverityAggregatesSubtree() throws {
    let projectStart = makeDate(2025, 1, 1)
    let group = TaskItem(title: "阶段一", kind: .group)
    let child = TaskItem(title: "设计", parentID: group.id, durationDays: 1)
    let tasks = [group, child]
    let state = makeState(tasks, projectStart: projectStart)
    let now = projectStart
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)
    let violations = [
        Violation(
            reason: .constraintConflict(
                taskTitle: "设计", kind: .endNoEarlierThan, conflict: .windowDoesNotFit
            ),
            taskID: child.id,
            severity: .warning
        )
    ]
    var viewState = WorkspaceViewState()
    viewState.expandedTaskIDs = [group.id]

    let snapshot = makeSnapshot(
        state: state,
        schedule: schedule,
        violations: violations,
        viewState: viewState,
        now: now
    )
    let groupRow = try #require(snapshot.outline.rows.first { $0.id == group.id })

    #expect(groupRow.violationCount == 1)
    #expect(groupRow.violationSeverity == .warning)
}

// MARK: - 检查器

@Test func inspectorShowsTaskDependencies() throws {
    let projectStart = makeDate(2025, 1, 1)
    let a = TaskItem(title: "A", startDate: projectStart, durationDays: 1)
    let b = TaskItem(
        title: "B",
        durationDays: 1,
        dependencies: [TaskDependency(predecessorID: a.id, type: .ss, lagDays: 1)]
    )
    let tasks = [a, b]
    let state = makeState(tasks, projectStart: projectStart)
    let now = projectStart
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)

    var viewingB = WorkspaceViewState()
    viewingB.selectedTaskID = b.id
    let bSnapshot = makeSnapshot(state: state, schedule: schedule, viewState: viewingB, now: now)
    guard case .task(let bInspector) = bSnapshot.inspector.content else {
        Issue.record("预期任务页")
        return
    }
    #expect(bInspector.predecessors.count == 1)
    #expect(bInspector.predecessors[0].taskID == a.id)
    #expect(bInspector.predecessors[0].type == .ss)
    #expect(bInspector.predecessors[0].lagDays == 1)
    #expect(bInspector.successors.isEmpty)

    var viewingA = WorkspaceViewState()
    viewingA.selectedTaskID = a.id
    let aSnapshot = makeSnapshot(state: state, schedule: schedule, viewState: viewingA, now: now)
    guard case .task(let aInspector) = aSnapshot.inspector.content else {
        Issue.record("预期任务页")
        return
    }
    #expect(aInspector.successors.map(\.taskID) == [b.id])
}

@Test func inspectorFallsBackWhenSelectionMissing() {
    let projectStart = makeDate(2025, 1, 1)
    let tasks = [TaskItem(title: "A", startDate: projectStart, durationDays: 1)]
    let state = makeState(tasks, title: fixtureProjectTitle, projectStart: projectStart)
    let now = projectStart
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)
    var viewState = WorkspaceViewState()
    viewState.selectedTaskID = UUID()

    let snapshot = makeSnapshot(state: state, schedule: schedule, viewState: viewState, now: now)
    guard case .project(let project) = snapshot.inspector.content else {
        Issue.record("选择缺失时应回项目页")
        return
    }
    #expect(project.title == fixtureProjectTitle)
    #expect(snapshot.inspector.selectionMissing)
}

@Test func violationInspectorGroupsAndListsRuleCatalog() throws {
    let now = makeDate(2025, 1, 1)
    let a = TaskItem(title: "A", startDate: now, durationDays: 1)
    let b = TaskItem(title: "B", startDate: now, durationDays: 1)
    let state = makeState([a, b], projectStart: now)
    let schedule = makeSchedule([a, b], projectStart: now, now: now)
    let violations = [
        Violation(reason: .cycle(taskTitle: "A"), taskID: a.id, severity: .error),
        Violation(reason: .negativeSlack(taskTitle: nil), taskID: b.id, severity: .warning)
    ]
    var viewState = WorkspaceViewState()
    viewState.inspectorTab = .violations

    let snapshot = makeSnapshot(
        state: state,
        schedule: schedule,
        violations: violations,
        viewState: viewState,
        now: now
    )
    guard case .violations(let inspector) = snapshot.inspector.content else {
        Issue.record("预期违例页")
        return
    }
    #expect(inspector.errorCount == 1)
    #expect(inspector.warningCount == 1)
    #expect(inspector.groups.map(\.severity) == [.error, .warning])
    // F-0704：条目只带码与语义，规则名与原因文案由视图按 Catalog 渲染。
    #expect(inspector.groups[0].items[0].code == .scheduleCycle)
    #expect(inspector.groups[0].items[0].reason == .cycle(taskTitle: "A"))
    #expect(inspector.groups[0].items[0].taskTitle == "A")
    #expect(inspector.groups[1].items[0].code == .negativeSlack)
    // 核心层不再写「未知任务」：reason 的 taskTitle 为 nil，快照用项目数据兜底。
    #expect(inspector.groups[1].items[0].reason == .negativeSlack(taskTitle: nil))
    #expect(inspector.groups[1].items[0].taskTitle == "B")
    #expect(inspector.checkedRules.count == ViolationEngine.ruleCategories.count)
}

// MARK: - 快照形态与确定性

@Test func outlineColumnsDegradeWithWidth() throws {
    let projectStart = makeDate(2025, 1, 1)
    let tasks = [TaskItem(title: "A", startDate: projectStart, durationDays: 1)]
    let state = makeState(tasks, projectStart: projectStart)
    let now = projectStart
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)

    var narrow = WorkspaceViewState()
    narrow.outlineWidth = 340
    let narrowSnapshot = makeSnapshot(state: state, schedule: schedule, viewState: narrow, now: now)
    #expect(!narrowSnapshot.outline.columns.contains(.start))
    #expect(!narrowSnapshot.outline.columns.contains(.assignee))
    #expect(narrowSnapshot.outline.columns.contains(.progress))

    var wide = WorkspaceViewState()
    wide.outlineWidth = 600
    let wideSnapshot = makeSnapshot(state: state, schedule: schedule, viewState: wide, now: now)
    #expect(wideSnapshot.outline.columns.contains(.start))
    #expect(wideSnapshot.outline.columns.contains(.finish))
    #expect(wideSnapshot.outline.columns.contains(.duration))
    #expect(wideSnapshot.outline.columns.contains(.assignee))
}

@Test func snapshotIsDeterministicForSameInput() {
    let projectStart = makeDate(2025, 1, 1)
    let group = TaskItem(title: "阶段一", kind: .group)
    let task = TaskItem(title: "A", startDate: projectStart, parentID: group.id, durationDays: 2)
    let tasks = [group, task]
    let state = makeState(tasks, projectStart: projectStart)
    let now = makeDate(2025, 1, 3)
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)
    var viewState = WorkspaceViewState()
    viewState.expandedTaskIDs = [group.id]

    let first = makeSnapshot(state: state, schedule: schedule, viewState: viewState, now: now)
    let second = makeSnapshot(state: state, schedule: schedule, viewState: viewState, now: now)

    #expect(first == second)
    #expect(first.generatedAt == now)
}

@Test func statusBarZoomPresetReflectsPreference() {
    let projectStart = makeDate(2025, 1, 1)
    let tasks = [TaskItem(title: "A", startDate: projectStart, durationDays: 1)]
    let state = makeState(tasks, projectStart: projectStart)
    let now = projectStart
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)

    var viewState = WorkspaceViewState()
    viewState.usesFitZoom = false
    viewState.zoom = .day
    let snapshot = makeSnapshot(state: state, schedule: schedule, viewState: viewState, now: now)
    #expect(snapshot.statusBar.zoom.preset == .day)
    #expect(snapshot.statusBar.zoom.pointsPerDay == GanttZoom.day.dayWidth)
    #expect(snapshot.gantt.dayWidth == GanttZoom.day.dayWidth)
}

@Test func ganttSnapshotCarriesDependencyRoutes() throws {
    let projectStart = makeDate(2025, 1, 1)
    let first = TaskItem(title: "A", startDate: projectStart, durationDays: 1)
    let second = TaskItem(
        title: "B",
        startDate: projectStart,
        durationDays: 1,
        dependencies: [TaskDependency(predecessorID: first.id)]
    )
    let tasks = [first, second]
    let state = makeState(tasks, projectStart: projectStart)
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: projectStart)

    let snapshot = makeSnapshot(state: state, schedule: schedule, now: projectStart)
    #expect(snapshot.gantt.dependencies.count == 1)
    let route = try #require(snapshot.gantt.dependencies.first)
    #expect(route.predecessorID == first.id)
    #expect(route.successorID == second.id)
    #expect(route.type == .fs)
    #expect(!route.segments.isEmpty)
    #expect(route.segments.allSatisfy { segment in
        abs(segment.startX - segment.endX) < 0.0001
            || abs(segment.startY - segment.endY) < 0.0001
    })
}

@Test func thousandTaskSnapshotStaysWithinBudget() async throws {
    let projectStart = makeDate(2025, 1, 1)
    var tasks: [TaskItem] = []
    for index in 0..<1_000 {
        let dependencies: [TaskDependency] = index >= 20
            ? [TaskDependency(predecessorID: tasks[index - 20].id)]
            : []
        tasks.append(TaskItem(
            title: "任务 \(index)",
            startDate: projectStart,
            durationDays: 1,
            dependencies: dependencies
        ))
    }
    let state = makeState(tasks, projectStart: projectStart)
    let now = projectStart
    let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)

    // 并行测试会持续占用 CPU：在最长 10s 内取最快一次，等待机器出现安静窗口。
    // 算法回退时任何一次都会超预算；调度抖动不应判为性能回退。
    // 门禁取 1000ms sanity 上限（与其他性能用例同口径）：100ms 紧墙钟在并行
    // 负载下固有 flaky（安静窗口 10s 内可能始终不出现，实测误报）。
    var snapshot = makeSnapshot(state: state, schedule: schedule, now: now)
    var bestMilliseconds = Double.infinity
    let deadline = Date().addingTimeInterval(10)
    repeat {
        let started = DispatchTime.now().uptimeNanoseconds
        snapshot = makeSnapshot(state: state, schedule: schedule, now: now)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        bestMilliseconds = min(bestMilliseconds, elapsed)
        if bestMilliseconds < 1000 { break }
        try await Task.sleep(nanoseconds: 100_000_000)
    } while Date() < deadline

    #expect(snapshot.outline.rows.count == 1_000)
    #expect(bestMilliseconds < 1000, "1000 任务快照最快耗时 \(bestMilliseconds) ms（超出 sanity 上限，疑似数量级回归）")
}
