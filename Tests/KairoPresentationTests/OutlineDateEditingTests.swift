import Foundation
import Testing
import KairoCore
import KairoPresentation

// F-14-19 大纲「开始 / 结束」日期列的策略纯函数单测（设计稿 §4「策略纯函数」行）。
//
// 视图不判语义：OutlineTable / InspectorView 的三处查询（isEnabled / availability /
// minimumDate）全部落到 `OutlineDateEditing`，因此「群组 / 里程碑 / 无排期」三类禁用
// 与「结束 = 起点次日」下限只能在这里锁定。禁用原因是语义枚举（F-0704），不再是中文串。
//
// 日历与日期全部注入（固定 UTC / Europe-Berlin 时区）：不读系统时区、不读当前时间。

/// 固定日历：避免用例跟随运行机器时区。
private func makeCalendar(_ timeZone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    guard let zone = TimeZone(identifier: timeZone) else {
        fatalError("测试时区不可用：\(timeZone)")
    }
    calendar.timeZone = zone
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

/// 基准日历（无夏令时，日期换算无歧义）。
private let utc = makeCalendar("UTC")
/// 夏令时日历：2025-03-30 进入夏令时（当日 23 小时）、2025-10-26 结束夏令时（当日 25 小时）。
private let berlin = makeCalendar("Europe/Berlin")

private func makeDay(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int = 0,
    minute: Int = 0,
    in calendar: Calendar = utc
) -> Date {
    let components = DateComponents(
        year: year, month: month, day: day, hour: hour, minute: minute
    )
    guard let date = calendar.date(from: components) else {
        fatalError("测试日期构造失败：\(year)-\(month)-\(day) \(hour):\(minute)")
    }
    return date
}

/// 构造 `PlanRow`：只填与日期列策略相关的字段，其余走默认值。
///
/// `hasSchedule` 缺省按 `Presenter` 对非群组行的口径派生（`scheduledFinish != nil`，见
/// `Presenter.swift:213`），保证夹具形状与真实快照一致。
private func makeRow(
    kind: TaskKind = .task,
    isAggregate: Bool = false,
    scheduledStart: Date? = nil,
    scheduledFinish: Date? = nil,
    hasSchedule: Bool? = nil,
    unscheduledReason: UnscheduledReason? = nil,
    startDate: Date? = nil
) -> PlanRow {
    PlanRow(
        id: UUID(),
        depth: 0,
        outlineNumber: "1",
        kind: kind,
        title: "行",
        status: .pending,
        priority: .normal,
        scheduledStart: scheduledStart,
        scheduledFinish: scheduledFinish,
        // 里程碑无持续时间：起止同日即可；普通任务给一个非零持续时间以贴近真实快照。
        durationDays: scheduledFinish == nil ? nil : (kind == .milestone ? 0 : 3),
        isAggregate: isAggregate,
        hasSchedule: hasSchedule ?? (scheduledFinish != nil),
        unscheduledReason: unscheduledReason,
        startDate: startDate
    )
}

// MARK: - 夹具矩阵（跨用例复用的行形状）

/// 有排期的普通任务：起点 2025-10-20，排他端点 10-23。
private func scheduledTaskRow() -> PlanRow {
    makeRow(
        scheduledStart: makeDay(2025, 10, 20),
        scheduledFinish: makeDay(2025, 10, 23)
    )
}

/// 无排期的普通任务（起点未定，回落自动排期）。
private func unscheduledTaskRow() -> PlanRow {
    makeRow()
}

/// 群组：聚合只读，即使带着聚合起止值。
private func groupRow() -> PlanRow {
    makeRow(
        kind: .group,
        isAggregate: true,
        scheduledStart: makeDay(2025, 10, 20),
        scheduledFinish: makeDay(2025, 10, 23),
        hasSchedule: true
    )
}

/// 里程碑：起止同日（无持续时间）。
private func milestoneRow() -> PlanRow {
    let at = makeDay(2025, 10, 20)
    return makeRow(kind: .milestone, scheduledStart: at, scheduledFinish: at)
}

@Suite("F-14-19 大纲日期列可编辑策略")
struct OutlineDateEditingTests {
    // MARK: - .start

    @Test func startColumnIsEnabledForScheduledTask() {
        let row = scheduledTaskRow()

        #expect(OutlineDateEditing.isEnabled(column: .start, row: row))
        #expect(OutlineDateEditing.availability(column: .start, row: row) == .editable)
        #expect(OutlineDateEditing.minimumDate(column: .start, row: row, calendar: utc) == nil)
    }

    /// 里程碑只有开始日可改（结束日由开始决定，见设计 §2 表）。
    @Test func startColumnIsEnabledForMilestone() {
        let row = milestoneRow()

        #expect(OutlineDateEditing.isEnabled(column: .start, row: row))
        #expect(OutlineDateEditing.availability(column: .start, row: row) == .editable)
    }

    /// 无排期仍可编辑开始：清除意图值即回落自动排期（设计 §2）。
    @Test func startColumnIsEnabledForUnscheduledTask() {
        let row = unscheduledTaskRow()
        #expect(row.scheduledStart == nil)

        #expect(OutlineDateEditing.isEnabled(column: .start, row: row))
        #expect(OutlineDateEditing.availability(column: .start, row: row) == .editable)
        #expect(OutlineDateEditing.minimumDate(column: .start, row: row, calendar: utc) == nil)
    }

    @Test func startColumnIsDisabledForGroupRow() throws {
        let row = groupRow()
        let availability = OutlineDateEditing.availability(column: .start, row: row)

        #expect(!OutlineDateEditing.isEnabled(column: .start, row: row))
        // F-0704：原因是语义枚举，不再是非空中文串；文案由视图按原因渲染。
        #expect(availability.disabledReason == .aggregate)
        #expect(OutlineDateEditing.minimumDate(column: .start, row: row, calendar: utc) == nil)
    }

    // MARK: - .finish：启用 + 下限

    @Test func finishColumnIsEnabledForScheduledTaskWithNextDayMinimum() {
        let row = scheduledTaskRow()
        let start = makeDay(2025, 10, 20)

        #expect(OutlineDateEditing.isEnabled(column: .finish, row: row))
        #expect(OutlineDateEditing.availability(column: .finish, row: row) == .editable)

        let minimum = OutlineDateEditing.minimumDate(column: .finish, row: row, calendar: utc)
        #expect(minimum == makeDay(2025, 10, 21), "普通任务最小可选结束日 = 起点次日零点")
        #expect(
            ScheduleDateMath.dayOffset(from: start, to: minimum ?? start, calendar: utc) == 1,
            "排他端点：下限与起点恰差一天"
        )
    }

    /// 起点带时分秒时，下限仍是「次日零点」，不是「起点 + 24 小时」。
    @Test func finishMinimumDateIsNextDayMidnightForSubDayStart() {
        let row = makeRow(
            scheduledStart: makeDay(2025, 10, 20, hour: 23, minute: 30),
            scheduledFinish: makeDay(2025, 10, 24, hour: 9),
            hasSchedule: true
        )

        let minimum = OutlineDateEditing.minimumDate(column: .finish, row: row, calendar: utc)
        #expect(minimum == makeDay(2025, 10, 21))
        #expect(utc.startOfDay(for: minimum ?? .distantPast) == minimum, "下限必须是整天零点")
    }

    /// 下限跨月、跨年、跨闰日都只推进到次日零点。
    @Test func finishMinimumDateHandlesMonthYearAndLeapBoundaries() {
        let cases: [(start: Date, expected: Date)] = [
            (makeDay(2025, 12, 31), makeDay(2026, 1, 1)),
            (makeDay(2026, 2, 28), makeDay(2026, 3, 1)),
            (makeDay(2024, 2, 28), makeDay(2024, 2, 29)),
            (makeDay(2024, 2, 29), makeDay(2024, 3, 1)),
        ]

        for item in cases {
            let row = makeRow(scheduledStart: item.start, scheduledFinish: item.expected)
            #expect(
                OutlineDateEditing.minimumDate(column: .finish, row: row, calendar: utc)
                    == item.expected,
                "下限推进错误：起点 \(item.start) → 期望 \(item.expected)"
            )
        }
    }

    // MARK: - .finish：禁用

    @Test func finishColumnIsDisabledForMilestone() {
        let row = milestoneRow()
        let reason = OutlineDateEditing.availability(column: .finish, row: row).disabledReason

        #expect(!OutlineDateEditing.isEnabled(column: .finish, row: row))
        #expect(reason == .milestone)
        #expect(reason != OutlineDateEditing.availability(column: .start, row: groupRow()).disabledReason,
                "里程碑禁用原因与群组禁用原因应可区分")
        // 里程碑行本身已禁用；下限口径仍与 ScheduleDateMath 一致（起点当日），保证预览行不撒谎。
        #expect(OutlineDateEditing.minimumDate(column: .finish, row: row, calendar: utc)
                == makeDay(2025, 10, 20))
    }

    @Test func finishColumnIsDisabledForGroupRow() {
        let row = groupRow()
        let reason = OutlineDateEditing.availability(column: .finish, row: row).disabledReason

        #expect(!OutlineDateEditing.isEnabled(column: .finish, row: row))
        #expect(reason == .aggregate)
        #expect(reason == OutlineDateEditing.availability(column: .start, row: row).disabledReason,
                "群组的开始/结束共用同一聚合禁用规则")
    }

    /// 群组优先于里程碑：两类条件同时成立时给聚合文案（聚合是不可编辑的根本原因）。
    @Test func aggregateReasonTakesPrecedenceOverMilestone() {
        let row = makeRow(
            kind: .milestone,
            isAggregate: true,
            scheduledStart: makeDay(2025, 10, 20),
            scheduledFinish: makeDay(2025, 10, 20),
            hasSchedule: true
        )

        #expect(OutlineDateEditing.availability(column: .finish, row: row)
                == OutlineDateEditing.availability(column: .finish, row: groupRow()))
        #expect(OutlineDateEditing.availability(column: .finish, row: row)
                != OutlineDateEditing.availability(column: .finish, row: milestoneRow()))
    }

    @Test func finishColumnIsDisabledWhenScheduledStartIsNil() {
        let row = unscheduledTaskRow()
        let reason = OutlineDateEditing.availability(column: .finish, row: row).disabledReason

        #expect(!OutlineDateEditing.isEnabled(column: .finish, row: row))
        #expect(reason == .unscheduled(nil))
        #expect(reason != OutlineDateEditing.availability(column: .finish, row: milestoneRow()).disabledReason,
                "无排期禁用原因与里程碑禁用原因应可区分")
        #expect(OutlineDateEditing.minimumDate(column: .finish, row: row, calendar: utc) == nil,
                "无起点即无下限（弹层不限制任何日期）")
    }

    /// 防御式分支：快照自相矛盾（有起点却标记无排期）时同样禁用，避免折算用错起点。
    @Test func finishColumnIsDisabledWhenSnapshotFlagsUnscheduled() {
        let row = makeRow(
            scheduledStart: makeDay(2025, 10, 20),
            hasSchedule: false
        )

        #expect(!OutlineDateEditing.isEnabled(column: .finish, row: row))
        #expect(OutlineDateEditing.availability(column: .finish, row: row).disabledReason != nil)
    }

    // MARK: - 禁用原因与检查器同源

    /// 三条禁用原因与检查器「结束」行同语义（`InspectorView` 也读同一枚举）：
    /// 同一行在大纲与检查器必须给出同一条解释，渲染层用同一组 Catalog 键。
    @Test func finishDisabledReasonsAreSemanticAndDistinct() {
        #expect(OutlineDateEditing.availability(column: .finish, row: groupRow()).disabledReason
                == .aggregate)
        #expect(OutlineDateEditing.availability(column: .finish, row: milestoneRow()).disabledReason
                == .milestone)
        #expect(OutlineDateEditing.availability(column: .finish, row: unscheduledTaskRow()).disabledReason
                == .unscheduled(nil))
    }

    /// 快照带无排期原因时一并透传（术语与视图层 unscheduledReason 同源）：
    /// 用户据此知道该先修什么，而不是只知道「设不了结束」。
    @Test func unscheduledReasonCarriesSnapshotCause() {
        let cycle = makeRow(unscheduledReason: .cycle)
        #expect(OutlineDateEditing.availability(column: .finish, row: cycle).disabledReason
                == .unscheduled(.cycle))
    }

    // MARK: - canClear（「清除」只见于带意图起点的开始列）

    @Test func canClearIsTrueForStartColumnWithIntentDate() {
        let row = makeRow(
            scheduledStart: makeDay(2025, 10, 20),
            scheduledFinish: makeDay(2025, 10, 23),
            startDate: makeDay(2025, 10, 18)
        )

        #expect(OutlineDateEditing.canClear(column: .start, row: row))
    }

    /// 排期起点是算出来的，不是用户设置的意图值：按它显示「清除」会点了没有可见变化。
    @Test func canClearIsFalseForStartColumnWithoutIntentDate() {
        let row = scheduledTaskRow()
        #expect(row.startDate == nil)

        #expect(!OutlineDateEditing.canClear(column: .start, row: row))
    }

    /// 群组行是聚合只读：即便带着意图值也不提供清除入口。
    @Test func canClearIsFalseForGroupRow() {
        let row = makeRow(
            kind: .group,
            isAggregate: true,
            scheduledStart: makeDay(2025, 10, 20),
            scheduledFinish: makeDay(2025, 10, 23),
            hasSchedule: true,
            startDate: makeDay(2025, 10, 18)
        )

        #expect(!OutlineDateEditing.canClear(column: .start, row: row))
    }

    /// 持续时间不可为空，结束列不提供清除。
    @Test func canClearIsFalseForFinishColumn() {
        let row = makeRow(
            scheduledStart: makeDay(2025, 10, 20),
            scheduledFinish: makeDay(2025, 10, 23),
            startDate: makeDay(2025, 10, 18)
        )

        #expect(!OutlineDateEditing.canClear(column: .finish, row: row))
    }

    // MARK: - finishCommit（结束列提交参数）

    @Test func finishCommitKeepsChosenFinishAndSnapshotStart() throws {
        let row = scheduledTaskRow()
        let finish = makeDay(2025, 10, 26)

        let commit = try #require(OutlineDateEditing.finishCommit(row: row, finish: finish))
        #expect(commit.finish == finish, "用户选的结束日原样提交")
        #expect(commit.start == makeDay(2025, 10, 20), "起点取同一快照的排期起点（Store 逐日复核）")
        #expect(ScheduleDateMath.dayOffset(from: commit.start, to: commit.finish, calendar: utc) == 6)
    }

    /// 无排期起点时整体不提交：不拿结束日兜底当起点（那会折算成 0 天并静默失败）。
    @Test func finishCommitReturnsNilWithoutScheduledStart() {
        let row = unscheduledTaskRow()
        #expect(row.scheduledStart == nil)

        #expect(OutlineDateEditing.finishCommit(row: row, finish: makeDay(2025, 10, 26)) == nil)
    }

    /// 列被禁用（里程碑 / 群组）时同样不提交：禁用即无提交路径。
    @Test func finishCommitReturnsNilWhenColumnDisabled() {
        let finish = makeDay(2025, 10, 26)

        #expect(OutlineDateEditing.finishCommit(row: milestoneRow(), finish: finish) == nil)
        #expect(OutlineDateEditing.finishCommit(row: groupRow(), finish: finish) == nil)
    }

    // MARK: - 非日期列不被策略拦截

    /// 策略只服务日期列：群组行上其它列也必须「可编辑、无原因、无下限」。
    @Test func nonDateColumnsAreNeverGated() {
        let nonDateColumns = OutlineColumn.allCases.filter { $0 != .start && $0 != .finish }
        #expect(nonDateColumns.count == 8, "除开始/结束外共 8 列参与断言")

        for row in [scheduledTaskRow(), unscheduledTaskRow(), groupRow(), milestoneRow()] {
            for column in nonDateColumns {
                #expect(
                    OutlineDateEditing.isEnabled(column: column, row: row),
                    "\(column) 列不应被日期策略拦截"
                )
                #expect(OutlineDateEditing.availability(column: column, row: row) == .editable)
                #expect(OutlineDateEditing.minimumDate(column: column, row: row, calendar: utc) == nil)
            }
        }
    }

    /// 不变量：`isEnabled` 恒等于「无禁用原因」（视图两处查询不会自相矛盾）。
    @Test(arguments: OutlineColumn.allCases)
    func enabledMatchesReasonPresence(column: OutlineColumn) {
        let rows = [scheduledTaskRow(), unscheduledTaskRow(), groupRow(), milestoneRow()]

        for row in rows {
            let enabled = OutlineDateEditing.isEnabled(column: column, row: row)
            let availability = OutlineDateEditing.availability(column: column, row: row)
            #expect(enabled == (availability == .editable), "\(column) 列的启用态与可编辑态不一致")
            #expect(enabled == availability.isEditable)
        }
    }

    // MARK: - 日历边界（夏令时）

    /// 结束夏令时当日（2025-10-26，25 小时）：下限仍是次日零点，且按日历推进而非 +86400 秒。
    @Test func finishMinimumDateSpansEndOfDSTDayInBerlin() {
        let start = makeDay(2025, 10, 26, in: berlin)
        let row = makeRow(
            scheduledStart: start,
            scheduledFinish: makeDay(2025, 10, 29, in: berlin),
            hasSchedule: true
        )

        let minimum = OutlineDateEditing.minimumDate(column: .finish, row: row, calendar: berlin)
        #expect(minimum == makeDay(2025, 10, 27, in: berlin), "夏令时切换日不得漂移一天")
        #expect(berlin.startOfDay(for: minimum ?? .distantPast) == minimum, "仍为整天零点")
        #expect(
            (minimum ?? .distantPast).timeIntervalSince(berlin.startOfDay(for: start)) == 90_000,
            "10-26 当日实为 25 小时：秒差证明走的是日历加法"
        )
        #expect(
            ScheduleDateMath.dayOffset(from: start, to: minimum ?? start, calendar: berlin) == 1
        )
    }

    /// 进入夏令时当日（2025-03-30，23 小时）：下限仍是次日零点。
    @Test func finishMinimumDateSpansStartOfDSTDayInBerlin() {
        let start = makeDay(2025, 3, 30, in: berlin)
        let row = makeRow(
            scheduledStart: start,
            scheduledFinish: makeDay(2025, 4, 2, in: berlin),
            hasSchedule: true
        )

        let minimum = OutlineDateEditing.minimumDate(column: .finish, row: row, calendar: berlin)
        #expect(minimum == makeDay(2025, 3, 31, in: berlin))
        #expect(berlin.startOfDay(for: minimum ?? .distantPast) == minimum)
        #expect(
            (minimum ?? .distantPast).timeIntervalSince(berlin.startOfDay(for: start)) == 82_800,
            "03-30 当日实为 23 小时：秒差证明走的是日历加法"
        )
        #expect(
            ScheduleDateMath.dayOffset(from: start, to: minimum ?? start, calendar: berlin) == 1
        )
    }

    /// 下限跟随注入的日历，而不是系统日历：同一时刻在 Berlin 口径下是 00:00，在 UTC 口径下不是。
    @Test func finishMinimumDateUsesInjectedCalendar() {
        // Berlin 10-20 23:30 = UTC 10-20 21:30，两边「次日零点」不是同一个瞬间。
        let start = makeDay(2025, 10, 20, hour: 23, minute: 30, in: berlin)
        let row = makeRow(scheduledStart: start, scheduledFinish: makeDay(2025, 10, 24, in: berlin))

        let inBerlin = OutlineDateEditing.minimumDate(column: .finish, row: row, calendar: berlin)
        let inUTC = OutlineDateEditing.minimumDate(column: .finish, row: row, calendar: utc)

        #expect(inBerlin == makeDay(2025, 10, 21, in: berlin))
        #expect(inUTC == makeDay(2025, 10, 21, in: utc))
        #expect(inBerlin != inUTC, "日历口径必须来自参数，不能偷用系统时区")
        let clock = berlin.dateComponents([.hour, .minute], from: inBerlin ?? .distantPast)
        #expect(clock.hour == 0 && clock.minute == 0, "下限落在局部时区零点")
    }
}
