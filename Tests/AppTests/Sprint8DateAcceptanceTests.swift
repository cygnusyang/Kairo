import Foundation
import Testing
import KairoCore
import KairoCommands
import KairoPresentation
@testable import KairoMacApp

/// Sprint 8 / F-14-10 起止日期验收用例。
///
/// 判据唯一来源：`docs/archive/Sprint8-task-dates/acceptance.md`（每个用例注释标注 AC-S8-xx）。
///
/// 通用夹具（acceptance.md §0）：`projectStart = 2026-11-02`（周一）、任务 A duration 3 天、
/// 任务 B 为 A 的 FS 后继、duration 2 天；基线 `A [11-02, 11-05)`、`B [11-05, 11-07)`。
///
/// 时区约定：`WorkspaceStore` 内部用 `Calendar.current`，故经 Store 的日期一律用本机日历年构造；
/// 纯函数（`ScheduleDateMath` / `CalendarGrid`）显式传入固定 UTC + 指定 `firstWeekday` 的日历。
/// 两侧都只看日历日，不依赖机器时区、当前时刻与执行顺序（确定性）。
///
/// 命名：`@Test` 名与 acceptance.md「判定方式」列逐字对应，回填时按名检索。

// MARK: - 纯函数夹具（固定时区/周首，避免机器设置影响）

private enum S8Fixture {
    static func calendar(firstWeekday: Int, timeZone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// 周日为首日（系统设置常见值）。
    static let sundayFirst = calendar(firstWeekday: 1)
    /// 周一为首日。
    static let mondayFirst = calendar(firstWeekday: 2)

    static func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, in calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        guard let date = calendar.date(from: components) else {
            fatalError("夹具日期构造失败：\(year)-\(month)-\(dayOfMonth)")
        }
        return calendar.startOfDay(for: date)
    }
}

@MainActor
@Suite("Sprint 8 起止日期验收（F-14-10）")
struct Sprint8DateAcceptanceTests {
    // MARK: - Store 夹具

    private func makeStore() -> WorkspaceStore {
        let suite = "kairo.s8.acceptance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return WorkspaceStore(defaults: defaults)
    }

    /// 本机日历日零点（与 `WorkspaceStore` 内部日历同口径）。
    private func localDay(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        guard let date = Calendar.current.date(from: components) else {
            fatalError("夹具日期构造失败：\(year)-\(month)-\(dayOfMonth)")
        }
        return Calendar.current.startOfDay(for: date)
    }

    /// acceptance.md §0 的标准夹具：projectStart 11-02、A(duration 3)、B(duration 2, FS after A)。
    private func makeDateFixture() throws -> (store: WorkspaceStore, a: UUID, b: UUID) {
        let store = makeStore()
        store.dispatch(.setProjectStart(localDay(2026, 11, 2)))
        store.dispatch(.createTask(parentID: nil, kind: .task))
        let a = try #require(store.selection)
        store.dispatch(.rename(a, "A"))
        store.dispatch(.setDuration(a, 3))
        store.dispatch(.createTask(parentID: nil, kind: .task))
        let b = try #require(store.selection)
        store.dispatch(.rename(b, "B"))
        store.dispatch(.setDuration(b, 2))
        store.dispatch(.addDependency(taskID: b, predecessorID: a, type: .fs, lagDays: 0))
        return (store, a, b)
    }

    private func task(_ store: WorkspaceStore, _ id: UUID) throws -> TaskItem {
        try #require(store.exportProject.tasks.first { $0.id == id })
    }

    private func row(_ store: WorkspaceStore, _ id: UUID) throws -> PlanRow {
        try #require(store.snapshot.outline.rows.first { $0.id == id })
    }

    private func bar(_ store: WorkspaceStore, _ id: UUID) throws -> GanttBar {
        try #require(store.snapshot.gantt.bars.first { $0.taskID == id })
    }

    private func taskInspector(_ store: WorkspaceStore) throws -> TaskInspector {
        guard case .task(let inspector) = store.snapshot.inspector.content else {
            Issue.record("选中任务后检查器应显示任务页")
            throw CancellationError()
        }
        return inspector
    }

    // MARK: - AC-S8-01 开始字段写入（日粒度归一）

    /// AC-S8-01：日粒度归一的写入路径（视图提交的就是归一后的零点）。
    @Test func startEditWritesStartDateAtStartOfDay() throws {
        let (store, a, _) = try makeDateFixture()
        // 17:42 的选择结果经 ScheduleDateMath 归一后落到 11-06 零点（时分秒丢弃）。
        let withTime = try #require(
            Calendar.current.date(byAdding: .minute, value: 17 * 60 + 42, to: localDay(2026, 11, 6))
        )
        let normalized = ScheduleDateMath.startOfDay(withTime, calendar: Calendar.current)
        #expect(normalized == localDay(2026, 11, 6))

        store.dispatch(.setTaskStart(a, normalized))

        #expect(try task(store, a).startDate == localDay(2026, 11, 6))
        #expect(try task(store, a).durationDays == 3, "改开始不改持续时间")
        store.dispatch(.select(a))
        #expect(try taskInspector(store).startDate == localDay(2026, 11, 6), "检查器回显同步")

        // 一次编辑 = 一个撤销点。
        store.dispatch(.undo)
        #expect(try task(store, a).startDate == nil)
    }

    /// AC-S8-01（归一的下游保证）：即便意图值带时分，引擎仍按当天零点排期。
    @Test func startDateWithTimeComponentSchedulesAtStartOfDay() throws {
        let (store, a, _) = try makeDateFixture()
        let withTime = try #require(
            Calendar.current.date(byAdding: .minute, value: 18 * 60 + 5, to: localDay(2026, 11, 6))
        )

        store.dispatch(.setTaskStart(a, withTime))

        #expect(try row(store, a).scheduledStart == localDay(2026, 11, 6), "排期取日历日，不取时刻")
        #expect(try row(store, a).scheduledFinish == localDay(2026, 11, 9))
    }

    // MARK: - AC-S8-02 引擎生效（E1 方案 C 核心验收）

    /// AC-S8-02：设未来开始 → 计划开始/结束前移，且 FS 后继跟随；甘特条体 x 前移 4 天 × 日宽。
    @Test func futureStartDateMovesScheduledStartAndGanttBar() throws {
        let (store, a, b) = try makeDateFixture()

        // 夹具自检（基线）。
        #expect(try row(store, a).scheduledStart == localDay(2026, 11, 2))
        #expect(try row(store, a).scheduledFinish == localDay(2026, 11, 5))
        #expect(try row(store, b).scheduledStart == localDay(2026, 11, 5))
        #expect(try row(store, b).scheduledFinish == localDay(2026, 11, 7))

        // 固定视窗起点：默认窗口跟随内容起点，不固定则条体 x 恒为 0，测不出整体前移。
        store.dispatch(.panWindow(to: localDay(2026, 11, 2)))
        let dayWidth = store.snapshot.gantt.dayWidth
        let beforeA = try bar(store, a)
        #expect(abs(beforeA.x) < 0.001, "基线：A 起点即窗口起点")
        #expect(abs(beforeA.width - 3 * dayWidth) < 0.001)

        store.dispatch(.setTaskStart(a, localDay(2026, 11, 6)))

        // 意图 → 排期 → 后继传播，三处都要动（不能只验 startDate 回显）。
        #expect(try task(store, a).startDate == localDay(2026, 11, 6))
        #expect(try row(store, a).scheduledStart == localDay(2026, 11, 6))
        #expect(try row(store, a).scheduledFinish == localDay(2026, 11, 9), "duration 3、排他端点")
        #expect(try row(store, b).scheduledStart == localDay(2026, 11, 9), "FS 传播到后继 B")
        #expect(try row(store, b).scheduledFinish == localDay(2026, 11, 11))

        #expect(store.snapshot.gantt.dayWidth == dayWidth, "日宽不受编辑影响")
        let afterA = try bar(store, a)
        #expect(abs((afterA.x - beforeA.x) - 4 * dayWidth) < 0.001, "条体前移量 = 4 天 × 日宽")
        #expect(abs(afterA.width - beforeA.width) < 0.001, "持续时间不变，条宽不变")
    }

    /// AC-S8-02 反向：显式开始早于锚点时不回拉（下界取 max），意图值仍原样保存。
    @Test func startDateEarlierThanAnchorDoesNotPullScheduleBack() throws {
        let (store, a, b) = try makeDateFixture()
        store.dispatch(.panWindow(to: localDay(2026, 11, 2)))
        let before = try bar(store, a)

        store.dispatch(.setTaskStart(a, localDay(2026, 10, 20)))

        #expect(try task(store, a).startDate == localDay(2026, 10, 20), "意图与结果可不同源")
        #expect(try row(store, a).scheduledStart == localDay(2026, 11, 2), "不得早于项目锚点")
        #expect(try row(store, b).scheduledStart == localDay(2026, 11, 5), "后继位置不变")
        let after = try bar(store, a)
        #expect(abs(after.x - before.x) < 0.001, "条体不因回填更早日期而左移")
    }

    // MARK: - AC-S8-05 结束 ≤ 开始不可达（双层防线）

    /// AC-S8-05 第一层：日历侧最小可选日 + 非法区间折算为 nil。
    @Test func finishMustBeLaterThanStart() {
        let calendar = S8Fixture.mondayFirst
        let start = S8Fixture.day(2026, 11, 6, in: calendar)

        #expect(ScheduleDateMath.minimumFinish(start: start, kind: .task, calendar: calendar)
            == S8Fixture.day(2026, 11, 7, in: calendar), "普通任务最小可选日 = 起点 + 1 天")
        #expect(ScheduleDateMath.durationDays(
            start: start, finish: start, calendar: calendar
        ) == nil, "结束 == 开始非法")
        #expect(ScheduleDateMath.durationDays(
            start: start, finish: S8Fixture.day(2026, 11, 5, in: calendar), calendar: calendar
        ) == nil, "结束早于开始非法")
        #expect(ScheduleDateMath.durationDays(
            start: start, finish: S8Fixture.day(2026, 11, 7, in: calendar), calendar: calendar
        ) == 1, "最小合法区间 = 1 天")
        // 里程碑：最小可选日退回当日，由调用方按 kind 禁用整行（AC-S8-08）。
        #expect(ScheduleDateMath.minimumFinish(start: start, kind: .milestone, calendar: calendar) == start)
    }

    /// AC-S8-05 第一层（边界置灰判据）：结束日历里早于最小可选日的格子必须落在禁用区。
    @Test func finishCalendarDisablesDaysBeforeMinimumFinish() {
        let calendar = S8Fixture.sundayFirst
        let start = S8Fixture.day(2026, 11, 6, in: calendar)
        let grid = CalendarGrid.month(containing: start, calendar: calendar)
        let minimum = ScheduleDateMath.minimumFinish(start: start, kind: .task, calendar: calendar)

        let disabled = grid.days.filter { $0 < minimum }
        let enabled = grid.days.filter { $0 >= minimum }
        #expect(disabled.contains(S8Fixture.day(2026, 11, 6, in: calendar)), "起点当日置灰")
        #expect(disabled.contains(S8Fixture.day(2026, 11, 5, in: calendar)), "早于起点置灰")
        #expect(enabled.contains(minimum), "起点 + 1 天可选")
        #expect(disabled.allSatisfy { $0 <= start }, "禁用区恰为「起点当日及更早」")
        #expect(enabled.allSatisfy { $0 >= minimum })
        #expect(!disabled.isEmpty && !enabled.isEmpty, "边界两侧都要在网格内出现")
    }

    /// AC-S8-05 第二层：绕过 UI 直接 dispatch，Store 拒绝且不产生撤销点（无草稿残留）。
    @Test func finishNotAfterStartIsRejectedWithoutUndo() throws {
        let (store, a, _) = try makeDateFixture()
        store.dispatch(.setTaskStart(a, localDay(2026, 11, 6)))
        let scheduledStart = try #require(try row(store, a).scheduledStart)
        #expect(scheduledStart == localDay(2026, 11, 6))
        let duration = try #require(try task(store, a).durationDays)
        let scheduledFinish = try #require(try row(store, a).scheduledFinish)

        store.dispatch(.setTaskFinish(a, finish: scheduledStart, start: scheduledStart))
        #expect(store.alertMessage == I18n.t("alert.finish_after_start", "The finish date must be later than the start date"))
        #expect(try task(store, a).durationDays == duration)
        #expect(try row(store, a).scheduledFinish == scheduledFinish)
        #expect(store.notice == nil, "不产生非模态提示（无草稿残留）")

        store.alertMessage = nil
        store.dispatch(.setTaskFinish(
            a, finish: localDay(2026, 11, 5), start: scheduledStart
        ))
        #expect(store.alertMessage == I18n.t("alert.finish_after_start", "The finish date must be later than the start date"))
        #expect(try task(store, a).durationDays == duration)

        // 撤销栈深度不变：一次 undo 回到「设开始」之前，而不是只回退被拒的那笔。
        store.dispatch(.undo)
        #expect(try task(store, a).startDate == nil)
        #expect(try row(store, a).scheduledStart == localDay(2026, 11, 2))
    }

    // MARK: - AC-S8-06 结束编辑只改写持续时间

    /// AC-S8-06：结束 → durationDays 换算，落点为排他端点，不动开始与截止。
    @Test func finishEditRewritesDurationOnlyAndScheduledFinishMatches() throws {
        let (store, a, _) = try makeDateFixture()
        store.dispatch(.setTaskStart(a, localDay(2026, 11, 6)))
        let dueDateBefore = try task(store, a).dueDate

        store.dispatch(.setTaskFinish(
            a, finish: localDay(2026, 11, 12), start: localDay(2026, 11, 6)
        ))

        let updated = try task(store, a)
        #expect(updated.durationDays == 6, "11-06 → 11-12 = 6 天")
        #expect(updated.startDate == localDay(2026, 11, 6))
        #expect(updated.dueDate == dueDateBefore)
        #expect(try row(store, a).scheduledStart == localDay(2026, 11, 6))
        #expect(try row(store, a).scheduledFinish == localDay(2026, 11, 12), "结束日 == 选中日")

        // 一次编辑一步撤销：只回退结束。
        store.dispatch(.undo)
        #expect(try task(store, a).durationDays == 3)
        #expect(try task(store, a).startDate == localDay(2026, 11, 6))
    }

    // MARK: - AC-S8-07 / AC-S8-08 日历网格与导航

    /// AC-S8-07/08：42 格（6×7），首格 = 当月 1 日所在周的周首，随 firstWeekday 变化。
    @Test func calendarGridHas42CellsWithFirstWeekdayDrivenStart() {
        // 2026-11-01 为周日、11-02 为周一（夹具前提）。
        let sundayFirst = CalendarGrid.month(
            containing: S8Fixture.day(2026, 11, 15, in: S8Fixture.sundayFirst),
            calendar: S8Fixture.sundayFirst
        )
        #expect(sundayFirst.days.count == 42)
        #expect(sundayFirst.days.first == S8Fixture.day(2026, 11, 1, in: S8Fixture.sundayFirst))
        #expect(sundayFirst.days.last == S8Fixture.day(2026, 12, 12, in: S8Fixture.sundayFirst))

        let mondayFirst = CalendarGrid.month(
            containing: S8Fixture.day(2026, 11, 15, in: S8Fixture.mondayFirst),
            calendar: S8Fixture.mondayFirst
        )
        #expect(mondayFirst.days.count == 42)
        #expect(mondayFirst.days.first == S8Fixture.day(2026, 10, 26, in: S8Fixture.mondayFirst))
        #expect(mondayFirst.days.last == S8Fixture.day(2026, 12, 6, in: S8Fixture.mondayFirst))

        // 逐日连续、无重复（网格不得跳日或复读）。
        #expect(Set(mondayFirst.days).count == 42)
        for index in 1..<mondayFirst.days.count {
            let expected = S8Fixture.mondayFirst.date(
                byAdding: .day, value: 1, to: mondayFirst.days[index - 1]
            )
            #expect(mondayFirst.days[index] == expected)
        }
    }

    /// AC-S8-07：非本月日照样输出（灰显但可点，点了顺带翻月）；周末有独立标记。
    @Test func calendarGridMarksAdjacentMonthDaysAndWeekends() {
        let calendar = S8Fixture.mondayFirst
        let grid = CalendarGrid.month(containing: S8Fixture.day(2026, 11, 15, in: calendar), calendar: calendar)

        let outside = grid.days.filter { !grid.isInMonth($0) }
        #expect(grid.days.filter { grid.isInMonth($0) }.count == 30, "11 月 30 天")
        #expect(outside.count == 12, "前导 6 + 尾随 6")
        #expect(outside.first == S8Fixture.day(2026, 10, 26, in: calendar))
        #expect(outside.last == S8Fixture.day(2026, 12, 6, in: calendar))
        #expect(outside.contains(S8Fixture.day(2026, 10, 31, in: calendar)), "上月尾日可点")

        #expect(grid.isWeekend(S8Fixture.day(2026, 11, 7, in: calendar)), "11-07 周六")
        #expect(grid.isWeekend(S8Fixture.day(2026, 11, 8, in: calendar)), "11-08 周日")
        #expect(!grid.isWeekend(S8Fixture.day(2026, 11, 6, in: calendar)), "11-06 周五")
        #expect(grid.isSameDay(
            S8Fixture.day(2026, 11, 6, in: calendar),
            S8Fixture.day(2026, 11, 6, in: calendar).addingTimeInterval(23 * 3600)
        ), "今天/选中态按日历日比较，不受时刻影响")
    }

    /// AC-S8-07/08：翻月与跨年，周首设置不丢（往返回到同一网格）。
    @Test func calendarGridMonthNavigationCrossesYearBoundary() {
        let calendar = S8Fixture.mondayFirst
        let november = CalendarGrid.month(containing: S8Fixture.day(2026, 11, 15, in: calendar), calendar: calendar)

        let december = november.month(offsetBy: 1)
        #expect(calendar.component(.month, from: december.firstDay) == 12)
        #expect(december.days.first == S8Fixture.day(2026, 11, 30, in: calendar), "12-01 为周二 → 周首回退 1 天")
        #expect(december.isInMonth(S8Fixture.day(2026, 12, 31, in: calendar)))
        #expect(december.days.count == 42)

        let january = december.month(offsetBy: 1) // 跨年
        #expect(calendar.component(.year, from: january.firstDay) == 2027)
        #expect(calendar.component(.month, from: january.firstDay) == 1)
        #expect(january.days.first == S8Fixture.day(2026, 12, 28, in: calendar))
        #expect(january.days.count == 42)

        #expect(january.month(offsetBy: -2).days == november.days, "翻月往返回到同一网格")
        #expect(november.month(offsetBy: 0).days == november.days)
    }

    /// AC-S8-07 边界：不存在的日期（2 月 30 日）必须返回 nil，不能被日历顺延。
    @Test func calendarGridRejectsNonexistentFebThirtieth() {
        let calendar = S8Fixture.mondayFirst
        let grid = CalendarGrid.month(containing: S8Fixture.day(2026, 2, 10, in: calendar), calendar: calendar)

        #expect(grid.date(year: 2026, month: 2, day: 30) == nil)
        #expect(grid.date(year: 2026, month: 2, day: 28) == S8Fixture.day(2026, 2, 28, in: calendar))
        #expect(grid.date(year: 2026, month: 11, day: 6) == S8Fixture.day(2026, 11, 6, in: calendar))
        #expect(grid.date(year: 2026, month: 13, day: 1) == nil)
    }

    // MARK: - AC-S8-09 撤销粒度

    /// AC-S8-09 a：单次开始编辑 = 一步撤销，意图与排期一起回退。
    @Test func eachDateEditIsOneUndoStep() throws {
        let (store, a, _) = try makeDateFixture()
        store.dispatch(.setTaskStart(a, localDay(2026, 11, 6)))
        #expect(try row(store, a).scheduledStart == localDay(2026, 11, 6))

        store.dispatch(.undo)

        #expect(try task(store, a).startDate == nil)
        #expect(try row(store, a).scheduledStart == localDay(2026, 11, 2), "排期一并回退")
        #expect(try row(store, a).scheduledFinish == localDay(2026, 11, 5))
    }

    /// AC-S8-09 b：500ms 内同字段两笔合并为一步（同步连续 dispatch，不 sleep 造竞态）。
    @Test func sameFieldEditsWithin500msMergeIntoOneStep() throws {
        let (store, a, _) = try makeDateFixture()
        store.dispatch(.select(a)) // 预热：排除首次调度开销落在计时窗口内

        let startedAt = Date()
        store.dispatch(.setTaskStart(a, localDay(2026, 11, 6)))
        store.dispatch(.setTaskStart(a, localDay(2026, 11, 9)))
        let elapsed = Date().timeIntervalSince(startedAt)

        #expect(try task(store, a).startDate == localDay(2026, 11, 9))
        #expect(elapsed < 0.5, "用例前提：两笔落在同一 500ms 合并窗口（实测 \(elapsed)s）")

        store.dispatch(.undo)
        #expect(try task(store, a).startDate == nil, "同字段两笔合并为一步")
    }

    /// AC-S8-09 c：跨字段不合并（mergeKey 含字段名），⌘Z 两次依次回退。
    @Test func crossFieldEditsDoNotMerge() throws {
        let (store, a, _) = try makeDateFixture()
        store.dispatch(.setTaskStart(a, localDay(2026, 11, 6)))
        store.dispatch(.setTaskFinish(
            a, finish: localDay(2026, 11, 12), start: localDay(2026, 11, 6)
        ))

        store.dispatch(.undo)
        #expect(try task(store, a).durationDays == 3, "第一步只回退结束")
        #expect(try task(store, a).startDate == localDay(2026, 11, 6))

        store.dispatch(.undo)
        #expect(try task(store, a).startDate == nil, "第二步回退开始")
    }

    /// AC-S8-09 d：检查器编辑与 canvas-move 不互并（`task-start-` vs `canvas-move-`）。
    @Test func inspectorEditDoesNotMergeWithCanvasMove() throws {
        let (store, a, _) = try makeDateFixture()
        store.dispatch(.setTaskStart(a, localDay(2026, 11, 6)))
        store.dispatch(.canvasEditSchedule(a, startDate: localDay(2026, 11, 9), durationDays: nil))
        #expect(try task(store, a).startDate == localDay(2026, 11, 9))

        store.dispatch(.undo)
        #expect(try task(store, a).startDate == localDay(2026, 11, 6), "画布拖拽仍是独立一步")

        store.dispatch(.undo)
        #expect(try task(store, a).startDate == nil)
    }

    // MARK: - AC-S8-10 回归：dueDate 与既有画布语义

    /// AC-S8-10 a/b：截止日期写入/清除不影响开始与持续时间，也不影响排期。
    @Test func dueDateEditStillWritesDueDateOnly() throws {
        let (store, a, _) = try makeDateFixture()
        store.dispatch(.setTaskStart(a, localDay(2026, 11, 6)))
        let baseline = try task(store, a)
        let scheduledFinish = try #require(try row(store, a).scheduledFinish)

        store.dispatch(.setDueDate(a, localDay(2026, 12, 1)))

        let updated = try task(store, a)
        #expect(updated.dueDate == localDay(2026, 12, 1))
        #expect(updated.startDate == baseline.startDate)
        #expect(updated.durationDays == baseline.durationDays)
        #expect(try row(store, a).scheduledFinish == scheduledFinish, "截止日期不参与排期")

        store.dispatch(.setDueDate(a, nil))
        #expect(try task(store, a).dueDate == nil)
        #expect(try task(store, a).startDate == baseline.startDate)
        #expect(try task(store, a).durationDays == baseline.durationDays)
    }

    // MARK: - AC-S8-11 结束与持续时间同字段双入口

    /// AC-S8-11：两入口读同一字段，换算互为逆运算（不一致即为双源）。
    @Test func durationAndFinishStayConsistent() throws {
        let (store, a, _) = try makeDateFixture()
        store.dispatch(.setTaskStart(a, localDay(2026, 11, 6)))

        store.dispatch(.setDuration(a, 5))
        var rowA = try row(store, a)
        let scheduledStart = try #require(rowA.scheduledStart)
        var scheduledFinish = try #require(rowA.scheduledFinish)
        #expect(scheduledFinish == ScheduleDateMath.finish(
            start: scheduledStart, durationDays: 5, calendar: Calendar.current
        ))
        #expect(ScheduleDateMath.durationDays(
            start: scheduledStart, finish: scheduledFinish, calendar: Calendar.current
        ) == 5)

        // 反向：经「结束」入口回写后，持续时间入口读到同一值。
        store.dispatch(.setTaskFinish(a, finish: localDay(2026, 11, 16), start: scheduledStart))
        rowA = try row(store, a)
        scheduledFinish = try #require(rowA.scheduledFinish)
        #expect(scheduledFinish == localDay(2026, 11, 16))
        #expect(try task(store, a).durationDays == 10)
        #expect(try task(store, a).durationDays == ScheduleDateMath.durationDays(
            start: scheduledStart, finish: scheduledFinish, calendar: Calendar.current
        ))
    }

    // MARK: - AC-S8-16 / AC-S8-17 无锚点与违例不阻断

    /// AC-S8-16 c（R2 已知行为）：项目未设开始时，改最早任务的开始会让整条时间轴随之前移。
    @Test func taskStartEditWithoutProjectAnchorShiftsTimeline() throws {
        let store = makeStore()
        store.dispatch(.createTask(parentID: nil, kind: .task))
        let id = try #require(store.selection)
        store.dispatch(.setDuration(id, 2))
        #expect(try row(store, id).scheduledStart != nil, "无项目开始时按今天/最早任务推导排期")

        store.dispatch(.setTaskStart(id, localDay(2026, 11, 6)))

        #expect(store.alertMessage == nil)
        #expect(try task(store, id).startDate == localDay(2026, 11, 6))
        #expect(try row(store, id).scheduledStart == localDay(2026, 11, 6))
        #expect(store.snapshot.gantt.projectStartDerived, "锚点由任务推导（界面据此提示）")
    }

    /// AC-S8-17：已存在违例时，结束编辑仍写入、不弹新对话框、不回滚。
    @Test func finishEditDoesNotBlockOnViolations() throws {
        let (store, a, _) = try makeDateFixture()
        store.dispatch(.setTaskStart(a, localDay(2026, 11, 6)))
        // 项目结束日 11-05，而 A 已排到 11-09 → 稳定的项目边界违例。
        store.dispatch(.setProjectEnd(localDay(2026, 11, 5)))
        let violationsBefore = try store.sessionForTesting.violations().count
        #expect(violationsBefore > 0, "前提：违例已存在")

        store.dispatch(.setTaskFinish(
            a, finish: localDay(2026, 11, 12), start: localDay(2026, 11, 6)
        ))

        #expect(store.alertMessage == nil, "不弹新对话框")
        #expect(try task(store, a).durationDays == 6, "不回滚")
        #expect(try store.sessionForTesting.violations().count == violationsBefore)
    }

    // MARK: - AC-S8-14 快捷项顺序（lead 裁定 2026-10-21）

    /// AC-S8-14（lead 裁定 2026-10-21，覆盖 design §3.3 原文）：视觉/Tab 顺序为
    /// 上个月 → 下个月 → 网格 → 今天 → 下周一 → +1 周 → 清除。
    ///
    /// 网格是单一焦点停靠点（42 格各有无障碍元素，但不做 42 个 Tab 停靠点）。
    /// 视图声明顺序即焦点顺序（`DateFieldRow.swift` 的 header → weekdayHeader → grid → previewRow → quickBar），
    /// 但物理键盘事件不可离屏派发（§3 N2），因此本用例只锁定可测的快捷项声明顺序；
    /// 「网格在快捷区之前」与完整 Tab 环仍为人工走查。
    @Test func calendarQuickActionOrderMatchesRuling() {
        #expect(DateQuickAction.allCases == [.today, .nextMonday, .plusWeek])
        #expect(DateQuickAction.allCases.map(\.title) == [
            I18n.t("date.quick.today", "Today"),
            I18n.t("date.quick.next_monday", "Next Monday"),
            I18n.t("date.quick.plus_week", "+1 week")
        ])
    }

    // MARK: - AC-S8-22 夏令时口径

    /// AC-S8-22：America/New_York 回拨日（2025-11-02）前后，duration 3 / 5 的结束日
    /// 必须等于「日历整日相加」的结果（不得少一天），且 finish − start 的日历天数 == duration。
    @Test func dstTransitionKeepsFinishOnCalendarDay() throws {
        let ny = S8Fixture.calendar(firstWeekday: 2, timeZone: "America/New_York")
        let start = S8Fixture.day(2025, 11, 1, in: ny) // 回拨前一日：11-02 02:00 回拨到 01:00

        let cases: [(Double, Date)] = [
            (3, S8Fixture.day(2025, 11, 4, in: ny)),
            (5, S8Fixture.day(2025, 11, 6, in: ny))
        ]
        for (duration, expectedFinish) in cases {
            // 换算层（检查器「结束」字段的显示值）
            #expect(
                ScheduleDateMath.finish(start: start, durationDays: duration, calendar: ny) == expectedFinish,
                "duration \(duration) 的结束显示值必须是日历加日结果"
            )
            #expect(ScheduleDateMath.dayOffset(from: start, to: expectedFinish, calendar: ny) == Int(duration))

            // 排期层（引擎落点）
            let task = TaskItem(title: "DST", startDate: start, durationDays: duration)
            let result = ScheduleEngine.compute(tasks: [task], projectStart: start, calendar: ny)
            let scheduled = try #require(result.tasks.first { $0.taskID == task.id })
            #expect(scheduled.scheduledStart == start)
            #expect(
                scheduled.scheduledFinish == expectedFinish,
                "duration \(duration) 的 scheduledFinish 不得比日历少一天"
            )
            #expect(
                ScheduleDateMath.dayOffset(
                    from: scheduled.scheduledStart, to: scheduled.scheduledFinish, calendar: ny
                ) == Int(duration),
                "finish − start 的日历天数必须等于 duration"
            )
        }
    }

    // MARK: - AC-S8-23 陈旧起点

    /// AC-S8-23：弹层打开后（视图记住的起点）排期发生变化，再提交旧起点 → 必须拒绝。
    @Test func staleStartFinishIsRejectedWithoutUndo() throws {
        let (store, a, _) = try makeDateFixture()
        let staleStart = try #require(try row(store, a).scheduledStart)
        #expect(staleStart == localDay(2026, 11, 2), "前提：弹层打开时起点为 11-02")

        // 打开期间排期变化（等价于画布拖拽 / 撤销重做 / ALAP 重算）。
        store.dispatch(.canvasEditSchedule(a, startDate: localDay(2026, 11, 6), durationDays: nil))
        #expect(try row(store, a).scheduledStart == localDay(2026, 11, 6))
        let duration = try #require(try task(store, a).durationDays)
        let scheduledFinish = try #require(try row(store, a).scheduledFinish)

        // 用户仍按旧起点 11-02 看到的月历选 11-10 提交。
        store.dispatch(.setTaskFinish(a, finish: localDay(2026, 11, 10), start: staleStart))

        #expect(store.alertMessage == I18n.t("alert.schedule_changed", "The schedule changed; pick the finish date again"))
        #expect(try task(store, a).durationDays == duration, "数据不变")
        #expect(try row(store, a).scheduledFinish == scheduledFinish, "落点不变")

        // 撤销栈不变：一次 undo 只回退画布拖拽，而不是先回退这笔被拒的写回。
        store.alertMessage = nil
        store.dispatch(.undo)
        #expect(try task(store, a).startDate == nil)
        #expect(try row(store, a).scheduledStart == localDay(2026, 11, 2))
    }
}
