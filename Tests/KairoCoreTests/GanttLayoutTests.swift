import Foundation
import Testing
@testable import KairoCore

// 甘特布局纯函数测试（US-E4-04 / F-14-01 / F-14-13 / F-14-14）。

/// 刻度标签语言（F-0702）：v0.8.5 的中文标签形态用 zh_CN 锁；en_US 见 GanttTickLabelLocaleTests。
private let zhCN = Locale(identifier: "zh_CN")

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d))!
}

/// 2026-11-02 为周一。
private let monday = day(2026, 11, 2)

private func scheduled(
    _ task: TaskItem,
    start: Date,
    days: Double,
    slack: Double = 0
) -> ScheduledTask {
    let finish = start.addingTimeInterval(days * 86_400)
    return ScheduledTask(
        taskID: task.id,
        durationDays: days,
        earliestStart: start,
        earliestFinish: finish,
        latestStart: start.addingTimeInterval(slack * 86_400),
        latestFinish: finish.addingTimeInterval(slack * 86_400),
        scheduledStart: start,
        scheduledFinish: finish,
        totalSlackDays: slack,
        freeSlackDays: slack
    )
}

private func result(
    _ items: [ScheduledTask],
    projectStart: Date? = nil,
    projectEnd: Date? = nil
) -> ScheduleResult {
    ScheduleResult(tasks: items, projectStart: projectStart, projectEnd: projectEnd)
}

struct GanttLayoutTests {
    @Test func contentRangeCoversProjectAndTaskBounds() throws {
        let task = TaskItem(title: "任务")
        let schedule = result(
            [scheduled(task, start: day(2026, 11, 3), days: 2)],
            projectStart: day(2026, 11, 2),
            projectEnd: day(2026, 11, 20)
        )
        let range = try #require(
            GanttLayoutEngine.contentRange(tasks: [task], schedule: schedule, calendar: utc)
        )
        #expect(range.start == monday)
        #expect(range.end == day(2026, 11, 20))
    }

    @Test func contentRangeFallsBackToScheduledTasks() throws {
        let first = TaskItem(title: "一")
        let second = TaskItem(title: "二")
        let schedule = result([
            scheduled(first, start: day(2026, 11, 3), days: 2),
            scheduled(second, start: day(2026, 11, 10), days: 2)
        ])
        let range = try #require(
            GanttLayoutEngine.contentRange(tasks: [first, second], schedule: schedule, calendar: utc)
        )
        #expect(range.start == day(2026, 11, 3))
        #expect(range.end == day(2026, 11, 12))
    }

    @Test func barPositionFollowsScheduledDates() {
        let task = TaskItem(title: "任务")
        let layout = GanttLayoutEngine.make(
            tasks: [task],
            schedule: result([scheduled(task, start: day(2026, 11, 4), days: 3)]),
            calendar: utc,
            locale: zhCN,
            zoom: .day,
            viewWidth: 800,
            windowStart: monday
        )
        let bar = layout.bars.first
        #expect(bar?.x == 64)
        #expect(bar?.width == 96)
        #expect(bar?.isMilestone == false)
    }

    @Test func barsOutsideWindowAreExcluded() {
        let inside = TaskItem(title: "窗内")
        let outside = TaskItem(title: "窗外")
        let layout = GanttLayoutEngine.make(
            tasks: [inside, outside],
            schedule: result([
                scheduled(inside, start: day(2026, 11, 6), days: 1),
                scheduled(outside, start: day(2026, 11, 1), days: 1)
            ]),
            calendar: utc,
            locale: zhCN,
            zoom: .day,
            viewWidth: 5 * 32,
            windowStart: day(2026, 11, 5)
        )
        #expect(layout.bars.map(\.taskID) == [inside.id])
    }

    @Test func barsStartingBeforeWindowKeepNegativeX() {
        let task = TaskItem(title: "跨界")
        let layout = GanttLayoutEngine.make(
            tasks: [task],
            schedule: result([scheduled(task, start: day(2026, 11, 3), days: 4)]),
            calendar: utc,
            locale: zhCN,
            zoom: .day,
            viewWidth: 5 * 32,
            windowStart: day(2026, 11, 5)
        )
        let bar = layout.bars.first
        #expect(bar?.x == -64)
        #expect(bar?.width == 128)
    }

    @Test func milestoneHasZeroWidth() {
        let milestone = TaskItem(title: "里程碑", kind: .milestone)
        let layout = GanttLayoutEngine.make(
            tasks: [milestone],
            schedule: result([scheduled(milestone, start: day(2026, 11, 4), days: 0)]),
            calendar: utc,
            locale: zhCN,
            zoom: .day,
            viewWidth: 400,
            windowStart: monday
        )
        let bar = layout.bars.first
        #expect(bar?.isMilestone == true)
        #expect(bar?.width == 0)
    }

    @Test func weekendBandsShadeSaturdayAndSunday() {
        // 2026-11-02 周一起七天窗口；日档位 32 点/天 → 周六索引 5、周日索引 6。
        let layout = GanttLayoutEngine.make(
            tasks: [],
            schedule: nil,
            calendar: utc,
            locale: zhCN,
            zoom: .day,
            viewWidth: 7 * 32,
            windowStart: monday
        )
        #expect(layout.bands.map(\.x) == [160, 192])
        #expect(layout.bands.allSatisfy { $0.width == 32 })
    }

    @Test func zoomChangesDayWidth() {
        #expect(GanttZoom.day.dayWidth == 32)
        #expect(GanttZoom.week.dayWidth == 12)
        #expect(GanttZoom.month.dayWidth == 5)
        let layout = GanttLayoutEngine.make(
            tasks: [],
            schedule: nil,
            calendar: utc,
            locale: zhCN,
            zoom: .month,
            viewWidth: 400,
            windowStart: monday
        )
        #expect(layout.dayWidth == 5)
    }

    @Test func dayZoomTicksUseTwoTiers() {
        let layout = GanttLayoutEngine.make(
            tasks: [],
            schedule: nil,
            calendar: utc,
            locale: zhCN,
            zoom: .day,
            viewWidth: 5 * 32,
            windowStart: day(2026, 11, 28)
        )
        let lower = layout.ticks.filter { $0.tier == .lower }
        #expect(lower.map(\.label) == ["28", "29", "30", "1", "2"])
        #expect(lower.allSatisfy { !$0.isMajor })

        let upper = layout.ticks.filter { $0.tier == .upper }
        #expect(upper.map(\.label) == ["11月", "12月"])
        #expect(upper.map(\.x) == [0.0, 96.0])
        #expect(upper.filter { !$0.isMajor }.isEmpty)
        #expect(upper.last?.date == day(2026, 12, 1))
    }

    @Test func monthZoomTicksAtMonthStart() {
        let layout = GanttLayoutEngine.make(
            tasks: [],
            schedule: nil,
            calendar: utc,
            locale: zhCN,
            zoom: .month,
            viewWidth: 60 * 5,
            windowStart: day(2026, 11, 1)
        )
        let lower = layout.ticks.filter { $0.tier == .lower }
        #expect(lower.map(\.label) == ["11月", "12月"])
        #expect(lower.map(\.x) == [0.0, 150.0])

        let upper = layout.ticks.filter { $0.tier == .upper }
        #expect(upper.map(\.label) == ["2026年"])
        #expect(upper.first?.x == 0)
    }

    @Test func monthZoomHidesNonWorkingBands() {
        let month = GanttLayoutEngine.make(
            tasks: [],
            schedule: nil,
            calendar: utc,
            locale: zhCN,
            zoom: .month,
            viewWidth: 60 * 5,
            windowStart: day(2026, 11, 1)
        )
        #expect(month.bands.isEmpty)

        let day = GanttLayoutEngine.make(
            tasks: [],
            schedule: nil,
            calendar: utc,
            locale: zhCN,
            zoom: .day,
            viewWidth: 7 * 32,
            windowStart: monday
        )
        #expect(!day.bands.isEmpty)
    }

    @Test func todayXTracksWindowBounds() throws {
        let inside = GanttLayoutEngine.make(
            tasks: [],
            schedule: nil,
            calendar: utc,
            locale: zhCN,
            zoom: .day,
            viewWidth: 7 * 32,
            windowStart: monday,
            today: day(2026, 11, 4)
        )
        let x = try #require(inside.todayX)
        #expect(abs(x - 2 * 32) < 0.0001)

        let outside = GanttLayoutEngine.make(
            tasks: [],
            schedule: nil,
            calendar: utc,
            locale: zhCN,
            zoom: .day,
            viewWidth: 7 * 32,
            windowStart: monday,
            today: day(2026, 11, 1)
        )
        #expect(outside.todayX == nil)
    }

    @Test func dependencyRoutesConnectAllFourTypesAtBarEdges() throws {
        let cases: [(TaskDependency.DependencyType, Double, Double)] = [
            (.fs, 68, 92),
            (.ff, 68, 164),
            (.ss, -4, 92),
            (.sf, -4, 164)
        ]
        for (type, expectedStartX, expectedEndX) in cases {
            let predecessor = TaskItem(title: "前")
            let successor = TaskItem(
                title: "后",
                dependencies: [TaskDependency(predecessorID: predecessor.id, type: type)]
            )
            let layout = GanttLayoutEngine.make(
                tasks: [predecessor, successor],
                schedule: result([
                    scheduled(predecessor, start: monday, days: 2),
                    scheduled(successor, start: day(2026, 11, 5), days: 2)
                ]),
                calendar: utc,
                locale: zhCN,
                zoom: .day,
                viewWidth: 400,
                windowStart: monday,
                rowIndexByTaskID: [predecessor.id: 0, successor.id: 1],
                rowHeight: 28
            )
            let route = try #require(layout.dependencyRoutes.first)
            #expect(layout.dependencyRoutes.count == 1)
            #expect(route.type == type)
            #expect(route.predecessorID == predecessor.id)
            #expect(route.successorID == successor.id)

            let first = try #require(route.segments.first)
            let last = try #require(route.segments.last)
            #expect(abs(first.startX - expectedStartX) < 0.0001)
            #expect(abs(first.startY - 14) < 0.0001)
            #expect(abs(last.endX - expectedEndX) < 0.0001)
            #expect(abs(last.endY - 42) < 0.0001)
            #expect(route.segments.allSatisfy { segment in
                abs(segment.startX - segment.endX) < 0.0001
                    || abs(segment.startY - segment.endY) < 0.0001
            })
        }
    }

    @Test func unscheduledTasksAreExcludedFromBarsAndContent() {
        let task = TaskItem(title: "环")
        let schedule = ScheduleResult(
            tasks: [scheduled(task, start: monday, days: 2)],
            unscheduledTaskIDs: [task.id]
        )
        #expect(
            GanttLayoutEngine.contentRange(tasks: [task], schedule: schedule, calendar: utc) == nil
        )
        let layout = GanttLayoutEngine.make(
            tasks: [task],
            schedule: schedule,
            calendar: utc,
            locale: zhCN,
            zoom: .day,
            viewWidth: 400,
            windowStart: monday
        )
        #expect(layout.bars.isEmpty)
    }

    @Test func dependencyRoutesSkipUnscheduledEndpoints() {
        let predecessor = TaskItem(title: "前")
        let successor = TaskItem(
            title: "后",
            dependencies: [TaskDependency(predecessorID: predecessor.id)]
        )
        let layout = GanttLayoutEngine.make(
            tasks: [predecessor, successor],
            schedule: result([scheduled(predecessor, start: monday, days: 2)]),
            calendar: utc,
            locale: zhCN,
            zoom: .day,
            viewWidth: 400,
            windowStart: monday,
            rowIndexByTaskID: [predecessor.id: 0, successor.id: 1]
        )
        #expect(layout.dependencyRoutes.isEmpty)
    }

    @Test func dependencyRoutesAvoidMiddleRowBars() throws {
        let predecessor = TaskItem(title: "前")
        let middle = TaskItem(title: "中")
        let successor = TaskItem(
            title: "后",
            dependencies: [TaskDependency(predecessorID: predecessor.id)]
        )
        let layout = GanttLayoutEngine.make(
            tasks: [predecessor, middle, successor],
            schedule: result([
                scheduled(predecessor, start: monday, days: 2),
                scheduled(middle, start: monday, days: 10),
                scheduled(successor, start: day(2026, 11, 5), days: 2)
            ]),
            calendar: utc,
            locale: zhCN,
            zoom: .day,
            viewWidth: 400,
            windowStart: monday,
            rowIndexByTaskID: [predecessor.id: 0, middle.id: 1, successor.id: 2],
            rowHeight: 28
        )
        let route = try #require(layout.dependencyRoutes.first)
        // 中间行条体占据 x 0...320；通道必须落在条体右侧之外。
        let lane = try #require(route.segments.first { segment in
            abs(segment.startX - segment.endX) < 0.0001
                && abs(segment.startY - 28) < 0.0001
                && abs(segment.endY - 56) < 0.0001
        })
        #expect(lane.startX > 320)
        // 穿过中间行（y 28...56）的垂直线都必须落在条体右侧。
        let crossing = route.segments.filter { segment in
            abs(segment.startX - segment.endX) < 0.0001
                && max(segment.startY, 28) < min(segment.endY, 56)
        }
        #expect(crossing.allSatisfy { $0.startX > 320 })
    }

    @Test func windowEndFollowsViewWidth() {
        let layout = GanttLayoutEngine.make(
            tasks: [],
            schedule: nil,
            calendar: utc,
            locale: zhCN,
            zoom: .day,
            viewWidth: 320,
            windowStart: monday
        )
        #expect(layout.windowEnd == day(2026, 11, 12))
    }

    @Test func progressAndCriticalFlagsComeFromTasks() {
        let critical = TaskItem(title: "关键", progress: 0.5)
        let slack = TaskItem(title: "有余量")
        let layout = GanttLayoutEngine.make(
            tasks: [critical, slack],
            schedule: result([
                scheduled(critical, start: monday, days: 2, slack: 0),
                scheduled(slack, start: monday, days: 2, slack: 3)
            ]),
            calendar: utc,
            locale: zhCN,
            zoom: .day,
            viewWidth: 400,
            windowStart: monday
        )
        #expect(layout.bars.first?.progress == 0.5)
        #expect(layout.bars.first?.isCritical == true)
        #expect(layout.bars.last?.isCritical == false)
    }

    @Test func dayWidthOverrideWinsOverZoom() {
        let layout = GanttLayoutEngine.make(
            tasks: [],
            schedule: nil,
            calendar: utc,
            locale: zhCN,
            zoom: .month,
            viewWidth: 400,
            windowStart: monday,
            dayWidthOverride: 10
        )
        #expect(layout.dayWidth == 10)
        #expect(layout.windowEnd == monday.addingTimeInterval(40 * 86_400))
    }

    @Test func fitDayWidthSpreadsContentAcrossView() {
        let range = DateInterval(start: monday, end: day(2026, 11, 12))
        let width = GanttLayoutEngine.fitDayWidth(
            contentRange: range,
            viewWidth: 320,
            calendar: utc
        )
        #expect(width == 32)
    }

    @Test func pannedWindowStartMovesOppositeToDrag() {
        // 向右拖 100pt（每日 20pt）→ 窗口起点左移 5 天。
        #expect(
            GanttLayoutEngine.pannedWindowStart(from: monday, translationX: 100, dayWidth: 20)
                == monday.addingTimeInterval(-5 * 86_400)
        )
        // 向左拖 40pt（每日 20pt）→ 窗口起点右移 2 天。
        #expect(
            GanttLayoutEngine.pannedWindowStart(from: monday, translationX: -40, dayWidth: 20)
                == monday.addingTimeInterval(2 * 86_400)
        )
    }

    @Test func pannedWindowStartClampsDayWidthToAvoidDivisionExplosion() {
        // 每日宽度下限 0.5pt：拖 100pt 最多平移 200 天。
        #expect(
            GanttLayoutEngine.pannedWindowStart(from: monday, translationX: 100, dayWidth: 0)
                == monday.addingTimeInterval(-200 * 86_400)
        )
    }
}

// MARK: - F-0702 刻度标签注入 Locale（Core 内不读 Locale.current）

/// 标签形态完全由注入的 Locale 决定：en_US 下不得出现「年 / 月 / 日」，
/// zh_CN 下与 v0.8.5 的既有标签形态语义等价（含 1 月的「仅年份」大刻度）。
struct GanttTickLabelLocaleTests {
    private let enUS = Locale(identifier: "en_US")

    private func makeLayout(
        zoom: GanttZoom,
        locale: Locale,
        windowStart: Date,
        width: Double
    ) -> GanttLayout {
        GanttLayoutEngine.make(
            tasks: [],
            schedule: nil,
            calendar: utc,
            locale: locale,
            zoom: zoom,
            viewWidth: width,
            windowStart: windowStart
        )
    }

    @Test func dayZoomLabelsUseEnglishUnderEnUS() {
        let layout = makeLayout(
            zoom: .day, locale: enUS, windowStart: day(2026, 11, 28), width: 5 * 32
        )
        let lower = layout.ticks.filter { $0.tier == .lower }.map(\.label)
        let upper = layout.ticks.filter { $0.tier == .upper }.map(\.label)

        #expect(lower == ["28", "29", "30", "1", "2"])
        #expect(upper == ["Nov", "Dec"])
        for label in lower + upper {
            #expect(
                !label.contains("年") && !label.contains("月") && !label.contains("日"),
                "en_US 注入下不得出现中文字段：\(label)"
            )
        }
    }

    @Test func dayZoomLabelsKeepV085ChineseShapesUnderZhCN() {
        let layout = makeLayout(
            zoom: .day, locale: zhCN, windowStart: day(2026, 11, 28), width: 5 * 32
        )

        #expect(layout.ticks.filter { $0.tier == .lower }.map(\.label) == ["28", "29", "30", "1", "2"])
        #expect(layout.ticks.filter { $0.tier == .upper }.map(\.label) == ["11月", "12月"])
    }

    @Test func monthZoomLocalizesYearAndMonthTicks() {
        let en = makeLayout(
            zoom: .month, locale: enUS, windowStart: day(2026, 11, 1), width: 60 * 5
        )
        #expect(en.ticks.filter { $0.tier == .lower }.map(\.label) == ["Nov", "Dec"])
        #expect(en.ticks.filter { $0.tier == .upper }.map(\.label) == ["2026"])

        let zh = makeLayout(
            zoom: .month, locale: zhCN, windowStart: day(2026, 11, 1), width: 60 * 5
        )
        #expect(zh.ticks.filter { $0.tier == .lower }.map(\.label) == ["11月", "12月"])
        #expect(zh.ticks.filter { $0.tier == .upper }.map(\.label) == ["2026年"])
    }

    /// 1 月：下层大刻度只出年份，上层只出年份（v0.8.5 口径，两种语言同构）。
    @Test func januaryTickDegradesToYearOnlyInBothLocales() {
        let en = makeLayout(
            zoom: .month, locale: enUS, windowStart: day(2026, 1, 1), width: 60 * 5
        )
        #expect(en.ticks.filter { $0.tier == .lower }.map(\.label) == ["2026", "Feb", "Mar"])
        #expect(en.ticks.filter { $0.tier == .upper }.map(\.label) == ["2026"])

        let zh = makeLayout(
            zoom: .month, locale: zhCN, windowStart: day(2026, 1, 1), width: 60 * 5
        )
        #expect(zh.ticks.filter { $0.tier == .lower }.map(\.label) == ["2026年", "2月", "3月"])
        #expect(zh.ticks.filter { $0.tier == .upper }.map(\.label) == ["2026年"])
    }

    /// 周档下层是「月 / 日」：两种目标语言都用数字斜杠形态（不引入月份名）。
    @Test func weekZoomMonthDayTickIsSlashFormInBothLocales() {
        let en = makeLayout(
            zoom: .week, locale: enUS, windowStart: day(2026, 11, 2), width: 8 * 12
        )
        let zh = makeLayout(
            zoom: .week, locale: zhCN, windowStart: day(2026, 11, 2), width: 8 * 12
        )
        let enLabels = en.ticks.filter { $0.tier == .lower }.map(\.label)
        let zhLabels = zh.ticks.filter { $0.tier == .lower }.map(\.label)

        #expect(enLabels == zhLabels, "月/日刻度应为同一数字形态：\(enLabels) vs \(zhLabels)")
        #expect(enLabels.first == "11/8")
    }
}
