import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import KairoCore
import KairoPresentation
@testable import KairoMacApp

/// F-14-10 日期字段与月历弹层的离屏渲染测试。
///
/// 覆盖 AC-S8-05（越界日置灰）、AC-S8-12（群组两行只读外观）、AC-S8-18（三态非空白且可区分、
/// 浅色/深色、选中态与今天态有差异）。真实 popover 动画、物理键盘事件与 VoiceOver 播报
/// 不在自动化范围（判据 §3 N1–N3）。
@MainActor
@Suite("S8 日期字段渲染")
struct Sprint8DateFieldRenderTests {
    private enum Threshold {
        /// 非空画面至少出现的颜色数；纯色空白画面为 1。
        static let distinctColors = 20
        /// 整套表面/文字 token 换肤后画面差异下限（背景占绝大多数像素）。
        static let themeChange = 0.3
        /// 内容/状态变化的最低可区分差异（与 GUIRenderTests 的 contentChange 同口径；
        /// 用以排除「只有一个像素不同」的抗锯齿噪声）。
        static let contentChange = 0.002
    }

    /// 固定周首（周一）的日历，时区跟随主机。
    ///
    /// 时区不能在这里钉死：被测的 `Display.isoDate` 与视图渲染都用 `TimeZone.current`
    /// 格式化日期，测试若固定在 Asia/Shanghai，在 UTC runner 上同一瞬间会落到前一天，
    /// 断言与离屏渲染比对整体错位（D-025：v0.5.0–v0.8.0 发版 CI 红）。
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else {
            Issue.record("无法构造日期 \(year)-\(month)-\(day)")
            return Date()
        }
        return calendar.startOfDay(for: date)
    }

    // MARK: - 渲染入口

    /// 离屏渲染（支持指定深浅色；`GUIRenderer` 固定浅色，深色用例单独构造）。
    private func snapshot(
        _ view: some View,
        width: CGFloat,
        height: CGFloat,
        scheme: ColorScheme
    ) throws -> RenderedSnapshot {
        let renderer = ImageRenderer(
            content: view
                .environment(\.colorScheme, scheme)
                .frame(width: width, height: height)
        )
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        let image = try #require(renderer.cgImage)

        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        #expect(drew)
        return RenderedSnapshot(width: image.width, height: image.height, pixels: pixels)
    }

    // MARK: - 夹具

    private func row(
        label: String = "开始",
        value: Date?,
        helper: String? = nil,
        isEnabled: Bool = true,
        disabledReason: String? = nil,
        minimumDate: Date? = nil
    ) -> some View {
        DateFieldRow(
            label: label,
            value: value,
            placeholder: "未设置",
            helper: helper,
            isEnabled: isEnabled,
            disabledReason: disabledReason,
            minimumDate: minimumDate,
            allowsClear: true,
            preview: nil,
            onCommit: { _ in }
        )
        .padding(8)
        .background(DesignTokens.surfaceChrome)
    }

    private func popover(
        selection: Date?,
        minimumDate: Date? = nil,
        allowsClear: Bool = false,
        preview: ((Date?) -> String?)? = nil,
        today: Date? = nil
    ) -> some View {
        let anchor = selection ?? date(2026, 11, 6)
        let month = CalendarGrid.month(containing: anchor, calendar: calendar).firstDay
        return CalendarPopover(
            label: "结束",
            selection: selection,
            minimumDate: minimumDate,
            maximumDate: nil,
            allowsClear: allowsClear,
            quickActions: DateQuickAction.allCases,
            preview: preview,
            disabledDayHint: minimumDate == nil ? nil : "结束须晚于开始，至少 1 天",
            today: today ?? date(2026, 11, 6),
            calendar: calendar,
            visibleMonth: .constant(month),
            onPick: { _ in },
            onDismiss: {}
        )
    }

    private func renderPopover(
        selection: Date?,
        minimumDate: Date? = nil,
        scheme: ColorScheme = .light,
        today: Date? = nil
    ) throws -> RenderedSnapshot {
        try snapshot(
            popover(selection: selection, minimumDate: minimumDate, today: today),
            width: CalendarPopover.width,
            height: CalendarPopover.height,
            scheme: scheme
        )
    }

    // MARK: - AC-S8-18 字段行三态

    @Test func dateFieldRowStatesRenderDistinctly() throws {
        let filled = try snapshot(
            row(value: date(2026, 11, 6), helper: "计划开始 2026-11-10"),
            width: 300, height: 64, scheme: .light
        )
        let empty = try snapshot(
            row(value: nil),
            width: 300, height: 64, scheme: .light
        )
        let disabled = try snapshot(
            row(value: date(2026, 11, 6), isEnabled: false, disabledReason: "群组字段由子任务聚合，只读"),
            width: 300, height: 64, scheme: .light
        )

        for rendered in [filled, empty, disabled] {
            #expect(rendered.distinctColorCount >= Threshold.distinctColors)
        }
        #expect(filled.differenceRatio(from: empty) > Threshold.contentChange)
        #expect(filled.differenceRatio(from: disabled) > Threshold.contentChange)
        #expect(empty.differenceRatio(from: disabled) > Threshold.contentChange)
    }

    // MARK: - AC-S8-18 弹层浅色 / 深色

    @Test func calendarPopoverRendersInLightAndDark() throws {
        let light = try renderPopover(selection: date(2026, 11, 6), scheme: .light)
        let dark = try renderPopover(selection: date(2026, 11, 6), scheme: .dark)

        #expect(light.width == Int(CalendarPopover.width))
        #expect(light.height == Int(CalendarPopover.height))
        #expect(light.distinctColorCount >= Threshold.distinctColors)
        #expect(dark.distinctColorCount >= Threshold.distinctColors)
        // 差异必须大到只能是整套表面/文字 token 换肤，而非抗锯齿噪声。
        #expect(light.differenceRatio(from: dark) > Threshold.themeChange)
    }

    // MARK: - AC-S8-18 选中态与今天态可区分

    @Test func selectedAndTodayStatesRenderDifferently() throws {
        let today = date(2026, 11, 6)
        let selectedToday = try renderPopover(selection: today, today: today)
        // 同一天被选中 → 只剩选中底色；另一天选中 → 今天保留描边环。
        let selectedOtherDay = try renderPopover(selection: date(2026, 11, 10), today: today)

        #expect(selectedToday.distinctColorCount >= Threshold.distinctColors)
        #expect(selectedOtherDay.distinctColorCount >= Threshold.distinctColors)
        #expect(selectedToday.differenceRatio(from: selectedOtherDay) > Threshold.contentChange)
    }

    // MARK: - AC-S8-05 结束日历越界日置灰

    @Test func finishCalendarDisablesDaysAtOrBeforeStart() throws {
        let start = date(2026, 11, 6)
        let minimum = ScheduleDateMath.minimumFinish(start: start, kind: .task, calendar: calendar)
        #expect(minimum == date(2026, 11, 7))

        let month = CalendarGrid.month(containing: start, calendar: calendar)
        for day in [date(2026, 11, 5), start] {
            let style = CalendarPopover.style(
                for: day,
                in: month,
                selection: minimum,
                minimumDate: minimum,
                maximumDate: nil,
                today: start
            )
            #expect(!style.isSelectable, "早于或等于起点的日子应不可选：\(Display.isoDate(day))")
        }
        let boundary = CalendarPopover.style(
            for: minimum,
            in: month,
            selection: minimum,
            minimumDate: minimum,
            maximumDate: nil,
            today: start
        )
        #expect(boundary.isSelectable)

        // 置灰必须落到画面上：有下限与无下限两张图应不同。
        let bounded = try renderPopover(selection: minimum, minimumDate: minimum, today: start)
        let unbounded = try renderPopover(selection: minimum, minimumDate: nil, today: start)
        #expect(bounded.distinctColorCount >= Threshold.distinctColors)
        #expect(bounded.differenceRatio(from: unbounded) > Threshold.contentChange)
    }

    // MARK: - AC-S8-12 群组两行只读外观

    @Test func groupDateRowsRenderAsReadOnly() throws {
        func rows(isEnabled: Bool) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                DateFieldRow(
                    label: "开始",
                    value: date(2026, 11, 2),
                    placeholder: "未设置",
                    isEnabled: isEnabled,
                    disabledReason: "群组字段由子任务聚合，只读",
                    allowsClear: true,
                    onCommit: { _ in }
                )
                DateFieldRow(
                    label: "结束",
                    value: date(2026, 11, 6),
                    placeholder: "无排期",
                    isEnabled: isEnabled,
                    disabledReason: "群组字段由子任务聚合，只读",
                    onCommit: { _ in }
                )
            }
            .padding(8)
            .background(DesignTokens.surfaceChrome)
        }

        let group = try snapshot(rows(isEnabled: false), width: 300, height: 96, scheme: .light)
        let editable = try snapshot(rows(isEnabled: true), width: 300, height: 96, scheme: .light)

        #expect(group.distinctColorCount >= Threshold.distinctColors)
        // 只读行不再渲染可编辑样式（次要文字色 + 禁用说明副行）。
        #expect(group.differenceRatio(from: editable) > Threshold.contentChange)
    }

    // MARK: - AC-S8-19 可静态断言的文案

    /// 无障碍标签由「字段名 + 分隔符 + 值」组成：措辞随语言，结构固定（F-0705）。
    @Test func dateRowAccessibilityLabelsMatchDesign() {
        let zh = Locale(identifier: "zh_CN")
        #expect(
            DateFieldRow.accessibilityLabelText(
                label: "开始",
                value: date(2026, 11, 6),
                calendar: calendar,
                locale: zh
            ) == I18n.t("date.field.accessible.value", "%1$@: %2$@", "开始", "2026年11月6日")
        )
        #expect(
            DateFieldRow.accessibilityLabelText(
                label: "开始",
                value: nil,
                calendar: calendar,
                locale: zh
            ) == I18n.t("date.field.accessible.unset", "%1$@: not set", "开始")
        )
        // 字段名原样使用：本组件不再追加「日期」后缀。
        #expect(
            DateFieldRow.accessibilityLabelText(
                label: "截止日期",
                value: nil,
                calendar: calendar,
                locale: zh
            ) == I18n.t("date.field.accessible.unset", "%1$@: not set", "截止日期")
        )
    }

    /// 单元格标签：日期 + 今天 / 已选中 / 不在本月 / 不可选，按固定顺序用分隔符拼接。
    @Test func dayLabelsDescribeTodaySelectionAndBounds() {
        let month = CalendarGrid.month(containing: date(2026, 11, 6), calendar: calendar)
        let label = CalendarPopover.dayAccessibilityLabel(
            for: date(2026, 11, 6),
            in: month,
            selection: date(2026, 11, 6),
            today: date(2026, 11, 6),
            isSelectable: false
        )
        #expect(label.hasPrefix(Display.dayLabel(date(2026, 11, 6), calendar: calendar)))
        #expect(label.contains(I18n.t("date.quick.today", "Today")))
        #expect(label.contains(I18n.t("date.calendar.badge.selected", "Selected")))
        #expect(label.contains(I18n.t("date.calendar.badge.unavailable", "Unavailable")))
        #expect(!label.contains(I18n.t("date.calendar.badge.adjacent_month", "Outside this month")))

        let outside = CalendarPopover.dayAccessibilityLabel(
            for: date(2026, 10, 26),
            in: month,
            selection: nil,
            today: date(2026, 11, 6),
            isSelectable: true
        )
        #expect(outside.hasPrefix(Display.dayLabel(date(2026, 10, 26), calendar: calendar)))
        #expect(outside.contains(I18n.t("date.calendar.badge.adjacent_month", "Outside this month")))
        #expect(!outside.contains(I18n.t("date.calendar.badge.unavailable", "Unavailable")))

        // 格式化按注入 Locale 出结果（F-0712）：zh 与 en 各自锁定。
        let zh = Locale(identifier: "zh_CN")
        let en = Locale(identifier: "en_US")
        #expect(Display.monthTitle(date(2026, 11, 6), calendar: calendar, locale: zh) == "2026年11月")
        #expect(Display.monthTitle(date(2026, 11, 6), calendar: calendar, locale: en) == "November 2026")
        #expect(Display.weekdaySymbols(calendar: calendar, locale: zh) == ["一", "二", "三", "四", "五", "六", "日"])
        #expect(Display.weekdaySymbols(calendar: calendar, locale: en) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(Display.date(date(2026, 11, 6), locale: zh) == "2026/11/6")
        #expect(Display.date(date(2026, 11, 6), locale: en) == "11/6/2026")
        #expect(Display.isoDate(date(2026, 11, 6)) == "2026-11-06")
        #expect(Display.isoDate(date(2026, 11, 6)) == Display.isoDate(date(2026, 11, 6)))
    }

    // MARK: - AC-S8-15 快捷项口径

    @Test func quickActionsFollowDesignRules() {
        let monday = date(2026, 11, 2)
        let wednesday = date(2026, 11, 4)

        #expect(DateQuickAction.today.date(selection: nil, now: wednesday, calendar: calendar) == wednesday)
        // 今天即周一 → 下一个周一为 +7 天。
        #expect(DateQuickAction.nextMonday.date(selection: nil, now: monday, calendar: calendar) == date(2026, 11, 9))
        #expect(DateQuickAction.nextMonday.date(selection: nil, now: wednesday, calendar: calendar) == date(2026, 11, 9))
        // +1 周以当前选中值为基准。
        #expect(
            DateQuickAction.plusWeek.date(selection: date(2026, 11, 6), now: monday, calendar: calendar)
                == date(2026, 11, 13)
        )
        // 早于最小可选日的快捷项禁用。
        #expect(
            !CalendarPopover.isWithinBounds(
                monday,
                minimumDate: date(2026, 11, 7),
                maximumDate: nil,
                calendar: calendar
            )
        )
        #expect(
            CalendarPopover.isWithinBounds(
                date(2026, 11, 7),
                minimumDate: date(2026, 11, 7),
                maximumDate: nil,
                calendar: calendar
            )
        )
    }

    // MARK: - M-8 单元格状态纯逻辑

    @Test func calendarDayStyleClassifiesSelectionTodayAndBounds() {
        let today = date(2026, 11, 6)
        let month = CalendarGrid.month(containing: today, calendar: calendar)
        let minimum = date(2026, 11, 7)

        // 当天：已选中 + 今天 + 本月 + 工作日，但因早于最小可选日而不可选。
        let todayStyle = CalendarPopover.style(
            for: today,
            in: month,
            selection: today,
            minimumDate: minimum,
            maximumDate: nil,
            today: today
        )
        #expect(!todayStyle.isSelectable)
        #expect(todayStyle.isSelected)
        #expect(todayStyle.isToday)
        #expect(todayStyle.isCurrentMonth)
        #expect(!todayStyle.isWeekend)

        // 次日（周六）：可选、周末、非今天、非选中。
        let saturday = CalendarPopover.style(
            for: minimum,
            in: month,
            selection: today,
            minimumDate: minimum,
            maximumDate: nil,
            today: today
        )
        #expect(saturday.isSelectable)
        #expect(saturday.isWeekend)
        #expect(!saturday.isToday)
        #expect(!saturday.isSelected)
        #expect(saturday.isCurrentMonth)

        // 上月尾巴：非本月但可点（点了顺带翻月）。
        let previousMonth = CalendarPopover.style(
            for: date(2026, 10, 26),
            in: month,
            selection: today,
            minimumDate: nil,
            maximumDate: nil,
            today: today
        )
        #expect(!previousMonth.isCurrentMonth)
        #expect(previousMonth.isSelectable)
    }

    // MARK: - M-2 预览行随候选日求值

    @Test func popoverPreviewFollowsCandidateDay() {
        let start = date(2026, 11, 6)
        let preview: (Date?) -> String? = { candidate in
            guard let candidate else { return nil }
            let days = ScheduleDateMath.dayOffset(from: start, to: candidate, calendar: calendar)
            return "\(Display.isoDate(start)) – \(Display.isoDate(candidate)) · \(days) 天"
        }

        let short = CalendarPopover.previewText(for: date(2026, 11, 9), using: preview)
        let long = CalendarPopover.previewText(for: date(2026, 11, 12), using: preview)
        #expect(short == "2026-11-06 – 2026-11-09 · 3 天")
        #expect(long == "2026-11-06 – 2026-11-12 · 6 天")
        #expect(short != long)
        #expect(CalendarPopover.previewText(for: nil, using: preview) == nil)
        #expect(CalendarPopover.previewText(for: date(2026, 11, 9), using: nil) == nil)
    }

    // MARK: - M-4 亚日持续时间的显示值夹取

    @Test func subDayDurationFinishIsClampedToMinimum() throws {
        let start = date(2026, 11, 6)
        let minimum = ScheduleDateMath.minimumFinish(start: start, kind: .task, calendar: calendar)
        #expect(minimum == date(2026, 11, 7))

        // 引擎口径：0.5 天 → 排期结束日是「起点 + 12 小时」，归一后仍是 11-06，
        // 早于最小可选日 11-07。
        let engineFinish = try #require(calendar.date(byAdding: .hour, value: 12, to: start))
        #expect(engineFinish < minimum)
        #expect(
            DateFieldValueMath.clampedFinish(engineFinish, minimumDate: minimum, calendar: calendar)
                == minimum
        )
        // 正常区间不受夹取影响。
        #expect(
            DateFieldValueMath.clampedFinish(
                date(2026, 11, 12),
                minimumDate: minimum,
                calendar: calendar
            ) == date(2026, 11, 12)
        )
        #expect(
            DateFieldValueMath.clampedFinish(engineFinish, minimumDate: nil, calendar: calendar)
                == start
        )

        // 夹取前后是两个不同画面：未夹取显示 11-06（死格日），夹取后显示 11-07。
        let clamped = try snapshot(
            row(label: "结束", value: minimum),
            width: 220, height: 56, scheme: .light
        )
        let unclamped = try snapshot(
            row(label: "结束", value: engineFinish),
            width: 220, height: 56, scheme: .light
        )
        #expect(clamped.distinctColorCount >= Threshold.distinctColors)
        #expect(clamped.differenceRatio(from: unclamped) > Threshold.contentChange)
    }
}
