import SwiftUI
import KairoPresentation

/// 日期字段的快捷项（弹层底部）。
enum DateQuickAction: CaseIterable, Hashable {
    case today
    case nextMonday
    case plusWeek

    var title: String {
        switch self {
        case .today: return I18n.t("date.quick.today", "Today")
        case .nextMonday: return I18n.t("date.quick.next_monday", "Next Monday")
        case .plusWeek: return I18n.t("date.quick.plus_week", "+1 week")
        }
    }

    /// 该快捷项要提交的日期。
    ///
    /// - `today`：今天；`nextMonday`：下一个周一（今天正是周一时为 +7 天）；
    /// - `plusWeek`：以字段当前值为基准 +7 天，无值时以今天为基准。
    func date(selection: Date?, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return today
        case .nextMonday:
            // Calendar.weekday：1 = 周日 … 2 = 周一。
            let weekday = calendar.component(.weekday, from: today)
            let offset = ((2 - weekday) % 7 + 7) % 7
            let days = offset == 0 ? 7 : offset
            return calendar.date(byAdding: .day, value: days, to: today) ?? today
        case .plusWeek:
            let base = calendar.startOfDay(for: selection ?? today)
            return calendar.date(byAdding: .day, value: 7, to: base) ?? base
        }
    }
}

/// 月历单元格的视觉与交互状态：渲染与无障碍共用同一份判定。
struct CalendarDayStyle: Equatable {
    /// 是否落在字段的可选区间内（越界日不可点、不可聚焦）。
    let isSelectable: Bool
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    let isWeekend: Bool
}

/// 可编辑日期字段行（日历弹层版）。
///
/// 替换检查器内既有 `DatePicker` 行：行内只显示 `YYYY-MM-DD`，编辑交给月历弹层。
/// 组件不持有 `WorkspaceStore`——值由调用方传入，提交经 `onCommit` 回到检查器接线点，
/// 使「视图只搬运日期，换算与写回在 Store」的分工成立。
struct DateFieldRow: View {
    /// 字段名（如「开始」「截止日期」）——由调用方给，组件不解释字段语义。
    let label: String
    /// 主值：行内渲染 `YYYY-MM-DD`。
    let value: Date?
    /// 无值时的占位文案。
    var placeholder: String = I18n.t("date.field.placeholder", "Not set")
    /// 副行灰字（如「计划开始 2026-11-10」）。
    var helper: String? = nil
    var isEnabled: Bool = true
    /// 禁用原因：显示为副行并以无障碍 hint 播报。
    var disabledReason: String? = nil
    /// 最小可选日（含）；由调用方按字段语义给出（如排他端点传「起点 + 1 天」）。
    var minimumDate: Date? = nil
    /// 最大可选日（含）；`nil` = 不限。
    var maximumDate: Date? = nil
    var allowsClear: Bool = false
    var quickActions: [DateQuickAction] = DateQuickAction.allCases
    /// 月历越界日（早于 minimumDate / 晚于 maximumDate）的 tooltip 与无障碍说明。
    /// 由调用方按字段语义给出——组件不知道字段含义，不得自造文案。
    var boundaryHint: String? = nil
    /// 弹层预览行文案（按字段语义由调用方给出，参数为候选日）；`nil` 时该行留白。
    var preview: ((Date?) -> String?)? = nil
    /// 提交：`nil` 只可能来自「清除」（`allowsClear` 为真时）。
    let onCommit: (Date?) -> Void

    @State private var isPopoverPresented = false
    /// 浏览月与选中解耦：翻月不改值，重开保留上月视图（设计 §3.2）。
    @State private var visibleMonth = Calendar.current.startOfDay(for: Date())
    @State private var knownValue: Date?
    @State private var hasKnownValue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(width: 68, alignment: .leading)
                Text(value.map { Display.isoDate($0) } ?? placeholder)
                    .font(.system(size: DesignTokens.bodyFontSize))
                    .monospacedDigit()
                    .foregroundStyle(isEnabled ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture(perform: togglePopover)
            .popover(
                isPresented: $isPopoverPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                CalendarPopover(
                    label: label,
                    selection: value,
                    minimumDate: minimumDate,
                    maximumDate: maximumDate,
                    allowsClear: allowsClear,
                    quickActions: quickActions,
                    preview: preview,
                    disabledDayHint: boundaryHint,
                    visibleMonth: $visibleMonth,
                    onPick: commit,
                    onDismiss: { isPopoverPresented = false }
                )
            }

            if isEnabled, let helper {
                Text(helper)
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(2)
            } else if !isEnabled, let disabledReason {
                Text(disabledReason)
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibilityLabelText(label: label, value: value))
        .accessibilityValue(value.map { Self.accessibilityDateText($0) } ?? placeholder)
        .accessibilityHint(isEnabled ? I18n.t("date.field.open_calendar", "Open the calendar to pick a date") : (disabledReason ?? I18n.t("date.field.open_calendar", "Open the calendar to pick a date")))
        .accessibilityAddTraits(isEnabled ? .isButton : [])
        .modifier(OptionalHelpModifier(text: isEnabled ? nil : disabledReason))
    }

    // MARK: - 交互

    private func togglePopover() {
        guard isEnabled else { return }
        guard !isPopoverPresented else {
            isPopoverPresented = false
            return
        }
        // 只有外部改动（撤销、画布拖拽、其他窗口）才把浏览月重置到当前值所在月，
        // 否则保留用户上次翻到的月份。
        let changedExternally = hasKnownValue && !isSameDay(knownValue, value)
        if !hasKnownValue || changedExternally {
            visibleMonth = CalendarGrid.month(containing: value ?? Date()).firstDay
        }
        knownValue = value
        hasKnownValue = true
        isPopoverPresented = true
    }

    private func commit(_ date: Date?) {
        knownValue = date
        hasKnownValue = true
        if let date {
            visibleMonth = CalendarGrid.month(containing: date).firstDay
        }
        isPopoverPresented = false
        onCommit(date)
    }

    private func isSameDay(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return Calendar.current.isDate(lhs, inSameDayAs: rhs)
        default: return false
        }
    }

    // MARK: - 文案

    /// 无障碍标签：「开始日期，2026年11月6日」/「开始日期，未设置」。
    static func accessibilityLabelText(
        label: String,
        value: Date?,
        calendar: Calendar = .current,
        locale: Locale = I18n.locale
    ) -> String {
        guard let value else {
            return I18n.t("date.field.accessible.unset", "%1$@: not set", label)
        }
        return I18n.t(
            "date.field.accessible.value",
            "%1$@: %2$@",
            label,
            accessibilityDateText(value, calendar: calendar, locale: locale)
        )
    }

    /// 无障碍播报用长日期：zh `2026年11月6日`，en `November 6, 2026`（F-0712 走本地化模板）。
    static func accessibilityDateText(
        _ date: Date,
        calendar: Calendar = .current,
        locale: Locale = I18n.locale
    ) -> String {
        Display.longDate(date, locale: locale)
    }
}

/// 日期字段的显示值口径（纯函数，供检查器与测试共用）。
enum DateFieldValueMath {
    /// 排他端点（finish）的显示值：与最小可选日取较晚者。
    ///
    /// 持续时间可小于 1 天（引擎接受任意 > 0），此时「起点 + duration」早于
    /// 最小可选日「起点 + 1 天」，直接显示会出现「已选中但不可选」的死格；
    /// 按设计 §1.4 的下限 1 天口径夹取到可选区间内。
    static func clampedFinish(
        _ finish: Date,
        minimumDate: Date?,
        calendar: Calendar = .current
    ) -> Date {
        let normalized = calendar.startOfDay(for: finish)
        guard let minimumDate else { return normalized }
        return max(normalized, calendar.startOfDay(for: minimumDate))
    }
}

/// 236×300 月历弹层：月份导航 / 星期表头 / 6×7 网格 / 预览行 / 快捷区。
///
/// 网格数据来自 `CalendarMonthGrid`（视图不自算日历）；颜色全部走 `DesignTokens`。
struct CalendarPopover: View {
    static let width: CGFloat = 236
    static let height: CGFloat = 300
    static let cellSize: CGFloat = 30

    /// 字段名，用于清除按钮与无障碍文案。
    let label: String
    let selection: Date?
    var minimumDate: Date? = nil
    var maximumDate: Date? = nil
    var allowsClear: Bool = false
    /// 清除按钮的显示条件覆盖；`nil` = 沿用 `allowsClear && selection != nil`。
    ///
    /// 供「显示值 ≠ 可清除值」的调用方使用（如大纲开始列：显示排期结果，只有意图起点可清除）。
    var canClear: Bool? = nil
    var quickActions: [DateQuickAction] = DateQuickAction.allCases
    /// 预览行文案（参数为候选日：焦点日优先，其次选中值）；`nil` 时留白（保持 300pt 总高）。
    var preview: ((Date?) -> String?)? = nil
    /// 越界格的无障碍说明与 tooltip；由调用方给字段级文案，组件不自造。
    var disabledDayHint: String? = nil

    /// 焦点跳格的最大步数：42 格（6×7）+ 余量，防止整月不可选时死循环。
    private static let maxFocusSteps = 62
    /// 「今天」基准，默认当前时刻（测试可注入固定日期）。
    var today: Date = Date()
    var calendar: Calendar = .current
    @Binding var visibleMonth: Date
    let onPick: (Date?) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isGridFocused: Bool
    @State private var focusedDay: Date?
    @State private var hoveredDay: Date?

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 30)
            weekdayHeader
                .frame(height: 18)
            grid
            previewRow
                .frame(height: 18)
            quickBar
                .frame(height: 30)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(width: Self.width, height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(DesignTokens.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DesignTokens.separator, lineWidth: 0.5)
        )
        .onExitCommand(perform: onDismiss)
        .onAppear {
            // 打开时焦点落在选中日；无选中值落今天（设计 §3.3）。
            focusedDay = calendar.startOfDay(for: selection ?? today)
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 0) {
            navButton(
                systemImage: "chevron.left",
                label: I18n.t("date.calendar.previous_month", "Previous month"),
                action: { shiftMonth(-1) }
            )
            Spacer(minLength: 0)
            Text(Display.monthTitle(visibleMonth, calendar: calendar))
                .font(.system(size: DesignTokens.bodyFontSize, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer(minLength: 0)
            navButton(
                systemImage: "chevron.right",
                label: I18n.t("date.calendar.next_month", "Next month"),
                action: { shiftMonth(1) }
            )
        }
    }

    private func navButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(Display.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(width: Self.cellSize, height: 18)
            }
        }
    }

    // MARK: - 网格

    private var grid: some View {
        let month = CalendarGrid.month(containing: visibleMonth, calendar: calendar)
        return VStack(spacing: 0) {
            ForEach(0..<CalendarMonthGrid.rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<CalendarMonthGrid.columns, id: \.self) { column in
                        dayCell(
                            month.days[row * CalendarMonthGrid.columns + column],
                            in: month
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(I18n.t("date.calendar.title", "%1$@ calendar", Display.monthTitle(visibleMonth, calendar: calendar)))
        .focusable()
        .focusEffectDisabled()
        .focused($isGridFocused)
        .onMoveCommand(perform: moveFocus)
        .onKeyPress(.return) {
            commitFocusedDay()
            return .handled
        }
        .onKeyPress(.space) {
            commitFocusedDay()
            return .handled
        }
        .onAppear { isGridFocused = true }
    }

    private func dayCell(_ day: Date, in month: CalendarMonthGrid) -> some View {
        let style = Self.style(
            for: day,
            in: month,
            selection: selection,
            minimumDate: minimumDate,
            maximumDate: maximumDate,
            today: today
        )
        return Text("\(month.calendar.component(.day, from: day))")
            .font(.system(size: DesignTokens.captionFontSize))
            .monospacedDigit()
            .foregroundStyle(textColor(style))
            .frame(width: Self.cellSize, height: Self.cellSize)
            .background {
                if style.isSelected {
                    RoundedRectangle(cornerRadius: 6).fill(DesignTokens.selection)
                } else if isHovered(day) && style.isSelectable {
                    RoundedRectangle(cornerRadius: 6).fill(DesignTokens.hoverOverlay)
                }
            }
            .overlay { decorations(style, day: day) }
            .contentShape(Rectangle())
            .onTapGesture {
                guard style.isSelectable else { return }
                pick(day)
            }
            .onHover { inside in
                if inside {
                    hoveredDay = day
                } else if let hoveredDay, month.isSameDay(hoveredDay, day) {
                    self.hoveredDay = nil
                }
            }
            .modifier(OptionalHelpModifier(text: style.isSelectable ? nil : disabledDayHint))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Self.dayAccessibilityLabel(
                    for: day,
                    in: month,
                    selection: selection,
                    today: today,
                    isSelectable: style.isSelectable
                )
            )
            .modifier(OptionalAccessibilityHint(text: style.isSelectable ? nil : disabledDayHint))
            .accessibilityAddTraits(style.isSelectable ? .isButton : [])
    }

    @ViewBuilder
    private func decorations(_ style: CalendarDayStyle, day: Date) -> some View {
        ZStack {
            // 今天：1pt accentStrong 描边（选中态优先，不叠加）。
            if style.isToday, !style.isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(DesignTokens.accentStrong, lineWidth: 1)
            }
            // 键盘焦点环：accentBase 内描 + focusRingOuter 外描。
            if isGridFocused, isFocusedDay(day) {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(DesignTokens.accentBase, lineWidth: 1.5)
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(DesignTokens.focusRingOuter, lineWidth: 3)
            }
        }
    }

    private func textColor(_ style: CalendarDayStyle) -> Color {
        if !style.isSelectable { return DesignTokens.textSecondary.opacity(0.3) }
        if style.isSelected {
            return DesignTokens.semanticText(DesignTokens.textPrimary, isSelected: true)
        }
        if style.isToday { return DesignTokens.accentStrong }
        if !style.isCurrentMonth { return DesignTokens.textSecondary.opacity(0.45) }
        if style.isWeekend { return DesignTokens.textSecondary }
        return DesignTokens.textPrimary
    }

    private func isHovered(_ day: Date) -> Bool {
        guard let hoveredDay else { return false }
        return calendar.isDate(hoveredDay, inSameDayAs: day)
    }

    private func isFocusedDay(_ day: Date) -> Bool {
        guard let focusedDay else { return false }
        return calendar.isDate(focusedDay, inSameDayAs: day)
    }

    // MARK: - 预览与快捷区

    private var previewRow: some View {
        Text(Self.previewText(for: focusedDay ?? selection, using: preview) ?? " ")
            .font(.system(size: DesignTokens.captionFontSize))
            .monospacedDigit()
            .foregroundStyle(DesignTokens.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickBar: some View {
        HStack(spacing: 10) {
            ForEach(quickActions, id: \.self) { action in
                let candidate = action.date(selection: selection, now: today, calendar: calendar)
                let isAvailable = Self.isWithinBounds(
                    candidate,
                    minimumDate: minimumDate,
                    maximumDate: maximumDate,
                    calendar: calendar
                )
                Button(action.title) {
                    pick(candidate)
                }
                .buttonStyle(.plain)
                .font(.system(size: DesignTokens.captionFontSize))
                .foregroundStyle(isAvailable ? DesignTokens.accentStrong : DesignTokens.textSecondary)
                .disabled(!isAvailable)
            }
            Spacer(minLength: 0)
            if canClear ?? (allowsClear && selection != nil) {
                Button(I18n.t("date.field.clear", "Clear")) {
                    onPick(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: DesignTokens.captionFontSize))
                .foregroundStyle(DesignTokens.textSecondary)
                .accessibilityLabel(I18n.t("date.field.clear_named", "Clear %1$@", fieldName))
            }
        }
        .frame(height: 30)
    }

    /// 无障碍播报用的字段名：直接用调用方给的标签，不再在本组件里拼「日期」后缀（F-0705）。
    private var fieldName: String { label
    }

    // MARK: - 交互

    private func shiftMonth(_ delta: Int) {
        let month = CalendarGrid.month(containing: visibleMonth, calendar: calendar)
        let shifted = month.month(offsetBy: delta).firstDay
        // 减弱动态效果时不做过渡动画。
        withAnimation(reduceMotion ? nil : Animation.easeInOut(duration: 0.12)) {
            visibleMonth = shifted
        }
    }

    private func pick(_ day: Date) {
        let normalized = calendar.startOfDay(for: day)
        // 点非本月日顺带翻月（设计 §3.2）。
        if !CalendarGrid.month(containing: visibleMonth, calendar: calendar).isInMonth(normalized) {
            visibleMonth = CalendarGrid.month(containing: normalized, calendar: calendar).firstDay
        }
        onPick(normalized)
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
        let delta: Int
        switch direction {
        case .left: delta = -1
        case .right: delta = 1
        case .up: delta = -7
        case .down: delta = 7
        default: return
        }
        let base = calendar.startOfDay(for: focusedDay ?? selection ?? today)
        guard var candidate = calendar.date(byAdding: .day, value: delta, to: base) else { return }
        // 越界日不可聚焦：沿移动方向跳到最近的可选日。
        var steps = 0
        while !isSelectable(candidate), steps < Self.maxFocusSteps {
            guard let next = calendar.date(byAdding: .day, value: delta, to: candidate) else { return }
            candidate = next
            steps += 1
        }
        guard isSelectable(candidate) else { return }
        focusedDay = candidate
        if !CalendarGrid.month(containing: visibleMonth, calendar: calendar).isInMonth(candidate) {
            visibleMonth = CalendarGrid.month(containing: candidate, calendar: calendar).firstDay
        }
    }

    private func commitFocusedDay() {
        guard let focusedDay, isSelectable(focusedDay) else { return }
        pick(focusedDay)
    }

    private func isSelectable(_ day: Date) -> Bool {
        Self.isWithinBounds(
            day,
            minimumDate: minimumDate,
            maximumDate: maximumDate,
            calendar: calendar
        )
    }

    // MARK: - 纯判定（渲染与无障碍共用，可单测）

    static func style(
        for day: Date,
        in month: CalendarMonthGrid,
        selection: Date?,
        minimumDate: Date?,
        maximumDate: Date?,
        today: Date
    ) -> CalendarDayStyle {
        let dayStart = month.calendar.startOfDay(for: day)
        return CalendarDayStyle(
            isSelectable: isWithinBounds(
                dayStart,
                minimumDate: minimumDate,
                maximumDate: maximumDate,
                calendar: month.calendar
            ),
            isSelected: selection.map { month.isSameDay(dayStart, $0) } ?? false,
            isToday: month.isSameDay(dayStart, today),
            isCurrentMonth: month.isInMonth(dayStart),
            isWeekend: month.isWeekend(dayStart)
        )
    }

    /// 是否落在 [minimumDate, maximumDate] 内（含两端，按整日比较）。
    static func isWithinBounds(
        _ day: Date,
        minimumDate: Date?,
        maximumDate: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        if let minimumDate, dayStart < calendar.startOfDay(for: minimumDate) { return false }
        if let maximumDate, dayStart > calendar.startOfDay(for: maximumDate) { return false }
        return true
    }

    /// 预览行求值：候选日为焦点日优先、其次选中值。
    ///
    /// 每次渲染都会重算（M-2）——方向键移动焦点时区间与天数随之更新，
    /// 而不是在打开瞬间固化。
    static func previewText(for candidate: Date?, using preview: ((Date?) -> String?)?) -> String? {
        preview?(candidate)
    }

    /// 单元格无障碍标签：「11 月 2 日，星期日，今天，已选中，不在本月，不可选」。
    static func dayAccessibilityLabel(
        for day: Date,
        in month: CalendarMonthGrid,
        selection: Date?,
        today: Date,
        isSelectable: Bool
    ) -> String {
        var parts = [Display.dayLabel(day, calendar: month.calendar)]
        if month.isSameDay(day, today) { parts.append(I18n.t("date.quick.today", "Today")) }
        if let selection, month.isSameDay(day, selection) { parts.append(I18n.t("date.calendar.badge.selected", "Selected")) }
        if !month.isInMonth(day) { parts.append(I18n.t("date.calendar.badge.adjacent_month", "Outside this month")) }
        if !isSelectable { parts.append(I18n.t("date.calendar.badge.unavailable", "Unavailable")) }
        return parts.joined(separator: I18n.t("date.calendar.accessible.separator", ", "))
    }
}

/// 只在需要时附加 tooltip（空文案不生成 tooltip）。
private struct OptionalHelpModifier: ViewModifier {
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

/// 只在需要时附加无障碍 hint。
private struct OptionalAccessibilityHint: ViewModifier {
    let text: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let text {
            content.accessibilityHint(text)
        } else {
            content
        }
    }
}
