import Foundation
import Testing
@testable import KairoCore

private let zhCN = Locale(identifier: "zh_CN")

/// D-017：month 档快路径与逐日参考实现逐位等价（跨实现比较，防快路径漂移）。
///
/// F-0702 起刻度标签的语言由注入 Locale 决定，因此本套用例比较的是**语义键**
/// （哪个日期该出下层 / 上层刻度、是否大刻度、横坐标）而不是标签文本；
/// 标签文本形态由 GanttTickLabelLocaleTests 按 en_US / zh_CN 各自锁定。
struct MonthFastPathEquivalenceTests {
    /// 逐日参考实现（与改造前 GanttLayout.make 的循环逐行同构）。
    private static func naiveMonthTicks(
        windowStart: Date, windowEnd: Date, calendar: Calendar
    ) -> (lower: [String], dates: [Date], upper: [String]) {
        var lower: [String] = []
        var dates: [Date] = []
        var upper: [String] = []
        var upperSeen = Set<Date>()
        var cursor = windowStart
        while cursor < windowEnd {
            let day = calendar.component(.day, from: cursor)
            let month = calendar.component(.month, from: cursor)
            let year = calendar.component(.year, from: cursor)
            if day == 1 {
                lower.append(month == 1 ? "y:\(year)" : "m:\(month)")
                dates.append(cursor)
                let day0 = calendar.startOfDay(for: cursor)
                if upperSeen.insert(day0).inserted, month == 1 {
                    upper.append("y:\(year)")
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return (lower, dates, upper)
    }

    /// 刻度语义键：1 月与「非月初的补位标签」只标年份，其余月份标月份。
    ///
    /// 补位标签（窗口起点不在月初时上层补的当月标签）带的是起点日期而非月初，
    /// v0.8.5 对它输出的就是「<year>年」，故按 day != 1 判定为年份键。
    private static func key(for date: Date, calendar: Calendar) -> String {
        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        return (month == 1 || day != 1) ? "y:\(year)" : "m:\(month)"
    }

    @Test func monthFastPathMatchesNaiveDayLoop() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let start = calendar.date(from: DateComponents(year: 2020, month: 3, day: 15))!

        for dayWidth in [0.5, 2.0, 5.0, 120.0] {
            let layout = GanttLayoutEngine.make(
                tasks: [], schedule: nil, calendar: calendar, locale: zhCN, zoom: .month,
                viewWidth: 1_920, windowStart: start, dayWidthOverride: dayWidth
            )
            let windowEnd = start.addingTimeInterval(1_920 / dayWidth * 86_400)
            var expected = Self.naiveMonthTicks(
                windowStart: start, windowEnd: windowEnd, calendar: calendar)
            // 循环前的既有行为：窗口起点非月初时补当月上层标签（x=0）。
            if calendar.component(.month, from: start) != 1 {
                expected.upper.insert(
                    "y:\(calendar.component(.year, from: start))", at: 0)
            }

            let lower = layout.ticks.filter { $0.tier == .lower }
            let upper = layout.ticks.filter { $0.tier == .upper }
            #expect(lower.map { Self.key(for: $0.date, calendar: calendar) } == expected.lower)
            #expect(lower.map(\.date) == expected.dates)
            #expect(upper.map { Self.key(for: $0.date, calendar: calendar) } == expected.upper)
            #expect(lower.map(\.x) == expected.dates.map {
                $0.timeIntervalSince(start) / 86_400 * dayWidth
            })
            #expect(lower.allSatisfy { !$0.label.isEmpty })
            #expect(upper.allSatisfy { !$0.label.isEmpty })
            #expect(layout.bands.isEmpty)
        }
    }

    @Test func monthFastPathStartsAtNextMonthWhenMidMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 18))!
        let layout = GanttLayoutEngine.make(
            tasks: [], schedule: nil, calendar: calendar, locale: zhCN, zoom: .month,
            viewWidth: 1_920, windowStart: start, dayWidthOverride: 5.0
        )
        let first = try #require(layout.ticks.first { $0.tier == .lower })
        let components = calendar.dateComponents([.year, .month, .day], from: first.date)
        #expect(components.month == 8 && components.day == 1 && components.year == 2026)
        #expect(abs(first.x - 14 * 5.0) < 1e-9)
    }
}
