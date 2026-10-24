import Foundation
import KairoCommands
import KairoCore
import KairoPresentation

/// 视图层文案与格式化：术语与核心层一致，同一事物全篇同一名称。
enum Display {
    /// 空值占位符：日期 / 时长 / 读数缺失时统一用它。
    static let placeholder = "—"

    // MARK: - 日期（F-0712：展示格式一律按生效 Locale 走模板）

    /// 模板 → 已本地化的 DateFormatter 缓存。
    ///
    /// `setLocalizedDateFormatFromTemplate` 每次调用都要走一遍 ICU，逐帧渲染成本高；
    /// 缓存键带上 Locale，两种语言共存时互不覆盖。
    private final class FormatterCache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String: DateFormatter] = [:]

        func formatter(template: String, locale: Locale) -> DateFormatter {
            let key = "\(template)|\(locale.identifier)"
            lock.lock()
            defer { lock.unlock() }
            if let cached = storage[key] { return cached }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(template)
            storage[key] = formatter
            return formatter
        }
    }

    private static let formatters = FormatterCache()

    private static func text(_ date: Date, template: String, locale: Locale) -> String {
        formatters.formatter(template: template, locale: locale).string(from: date)
    }

    /// 完整日期（大纲列、违例参数）：zh `2026/11/6`，en `11/6/2026`。
    static func date(_ value: Date?, locale: Locale = I18n.locale) -> String {
        guard let value else { return placeholder }
        return text(value, template: "yMd", locale: locale)
    }

    /// 短日期（状态栏可见区间）：zh `11/6`，en `11/6`。
    static func shortDate(_ value: Date?, locale: Locale = I18n.locale) -> String {
        guard let value else { return placeholder }
        return text(value, template: "Md", locale: locale)
    }

    /// 无障碍用长日期：zh `2026年11月6日`，en `November 6, 2026`。
    static func longDate(_ value: Date?, locale: Locale = I18n.locale) -> String {
        guard let value else { return placeholder }
        return text(value, template: "yMMMMd", locale: locale)
    }

    /// 甘特预览的月日：zh `11月6日`，en `Nov 6`。
    static func shortMonthDay(_ value: Date, locale: Locale = I18n.locale) -> String {
        text(value, template: "MMMd", locale: locale)
    }

    /// 提示条里的时刻（外部更新提示）：zh `17:32`，en `5:32 PM`。
    ///
    /// 判定为**展示格式**（F-0712）：只出现在用户可见的 notice 里，不参与任何比较或持久化。
    static func time(_ value: Date, locale: Locale = I18n.locale) -> String {
        value.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }

    /// 检查器日期字段的行内格式 `2026-11-06`。
    ///
    /// **判定为契约格式，不本地化**（F-0712）：`.kairo` 内容、命令行回执、MCP 参数与
    /// 无障碍播报都用这个口径，换语言不得改变字节。故固定 `en_US_POSIX` + `yyyy-MM-dd`，
    /// 由 `Tests/AppTests` 锁死两语言输出一致。
    static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func isoDate(_ value: Date?) -> String {
        guard let value else { return placeholder }
        return isoDateFormatter.string(from: value)
    }

    /// 月历头部：zh `2026年11月`，en `November 2026`。
    static func monthTitle(
        _ date: Date,
        calendar: Calendar = .current,
        locale: Locale = I18n.locale
    ) -> String {
        text(date, template: "yMMMM", locale: locale)
    }

    /// 星期表头短名，按 `calendar.firstWeekday` 起排（周首为周一则首项为「一」/「M」）。
    ///
    /// 名称取自 Calendar 的本地化符号表（zh `日一二…`，en `S M T…`），顺序仍由首周日决定。
    static func weekdaySymbols(
        calendar: Calendar = .current,
        locale: Locale = I18n.locale
    ) -> [String] {
        var localized = calendar
        localized.locale = locale
        let names = localized.veryShortWeekdaySymbols
        let first = localized.firstWeekday
        return (0..<7).map { index in
            names[(first - 1 + index) % 7]
        }
    }

    /// 无障碍日期标签：zh `11月2日，星期日`，en `November 2, Monday`。
    static func dayLabel(
        _ day: Date,
        calendar: Calendar = .current,
        locale: Locale = I18n.locale
    ) -> String {
        I18n.t(
            "date.label.compose",
            "%1$@, %2$@",
            text(day, template: "MMMMd", locale: locale),
            text(day, template: "EEEE", locale: locale)
        )
    }

    /// 时长：zh `3天` / `1.5天`，en `3 days` / `1.5 days`。
    ///
    /// 用 `Duration.UnitsFormatStyle`（Foundation 的本地化单位风格）而不是拼接中文单位：
    /// 单位词与单复数由 ICU 决定，视图层不再持有单位文案。
    static func duration(_ days: Double?, locale: Locale = I18n.locale) -> String {
        guard let days, days.isFinite else { return placeholder }
        let isWhole = abs(days.rounded() - days) < 0.0001
        let fractional: Duration.UnitsFormatStyle.FractionalPartDisplayStrategy =
            isWhole ? .hide() : .show(length: 1)
        let style = Duration.UnitsFormatStyle(
            allowedUnits: [.days],
            width: .wide,
            maximumUnitCount: 1,
            fractionalPart: fractional
        ).locale(locale)
        return Duration.seconds(days * 86_400).formatted(style)
    }

    static func percent(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    /// 大纲列名：列显隐菜单与「显示/隐藏X列」命令共用同一份文案（F-14-20）。
    static func outlineColumnTitle(_ column: OutlineColumn) -> String {
        switch column {
        case .status: return I18n.t("column.status", "Status")
        case .violation: return I18n.t("column.violation", "Violations")
        case .number: return I18n.t("column.number", "#")
        case .title: return I18n.t("column.title", "Task")
        case .predecessors: return I18n.t("column.predecessors", "Predecessors")
        case .start: return I18n.t("column.start", "Start")
        case .finish: return I18n.t("column.finish", "Finish")
        case .duration: return I18n.t("column.duration", "Duration")
        case .assignee: return I18n.t("column.assignee", "Assignee")
        case .progress: return I18n.t("column.progress", "Progress")
        }
    }

    static func statusTitle(_ status: TaskStatus) -> String {
        switch status {
        case .pending: return I18n.t("outline.status.pending", "To do")
        case .inProgress: return I18n.t("outline.status.in_progress", "In progress")
        case .blocked: return I18n.t("outline.status.blocked", "Blocked")
        case .done: return I18n.t("outline.status.done", "Done")
        }
    }

    static func statusSymbol(_ status: TaskStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .blocked: return "pause.circle"
        case .done: return "checkmark.circle.fill"
        }
    }

    static func priorityTitle(_ priority: TaskPriority) -> String {
        switch priority {
        case .low: return I18n.t("outline.priority.low", "Low")
        case .normal: return I18n.t("outline.priority.normal", "Normal")
        case .high: return I18n.t("outline.priority.high", "High")
        case .critical: return I18n.t("outline.priority.critical", "Critical")
        }
    }

    static func kindTitle(_ kind: TaskKind) -> String {
        switch kind {
        case .task: return I18n.t("outline.kind.task", "Task")
        case .group: return I18n.t("outline.kind.group", "Group")
        case .milestone: return I18n.t("outline.kind.milestone", "Milestone")
        }
    }

    static func dependencyTitle(_ type: TaskDependency.DependencyType) -> String {
        switch type {
        case .fs: return I18n.t("inspector.dependency.fs", "Finish → Start")
        case .ff: return I18n.t("inspector.dependency.ff", "Finish → Finish")
        case .ss: return I18n.t("inspector.dependency.ss", "Start → Start")
        case .sf: return I18n.t("inspector.dependency.sf", "Start → Finish")
        }
    }

    static func unscheduledReason(_ reason: UnscheduledReason?) -> String {
        switch reason {
        case .cycle: return I18n.t("outline.unscheduled.cycle", "Dependency cycle")
        case .emptyGroup: return I18n.t("outline.unscheduled.empty_group", "Empty group")
        case .unavailable: return I18n.t("outline.unscheduled.unavailable", "Cannot schedule")
        case nil: return I18n.t("outline.unscheduled.none", "Not scheduled")
        }
    }

    static func directionTitle(_ direction: ScheduleDirection) -> String {
        switch direction {
        case .forward: return I18n.t("inspector.direction.forward", "As soon as possible (ASAP)")
        case .backward: return I18n.t("inspector.direction.backward", "As late as possible (ALAP)")
        }
    }

    static func scheduleTitle(_ policy: SchedulingPolicy) -> String {
        policy == .asap ? I18n.t("inspector.policy.asap", "ASAP (as early as possible)") : I18n.t("inspector.policy.alap", "ALAP (as late as possible)")
    }

    static func healthTitle(_ health: ProjectSummary.Health) -> String {
        switch health {
        case .green: return I18n.t("statusbar.health.green", "Healthy")
        case .orange: return I18n.t("statusbar.health.orange", "Attention")
        case .red: return I18n.t("statusbar.health.red", "At risk")
        }
    }

    static func saveStateTitle(_ state: SaveState) -> String {
        switch state {
        case .saved: return I18n.t("statusbar.save.saved", "Saved")
        case .unsaved: return I18n.t("statusbar.save.unsaved", "Unsaved")
        case .failed: return I18n.t("statusbar.save.failed", "Save failed")
        }
    }

    // MARK: - 缩放指示（F-0705：快照只给档位枚举与日宽读数）

    /// 缩放档位名。
    static func zoomPresetTitle(_ preset: ZoomPreset) -> String {
        switch preset {
        case .custom: return I18n.t("statusbar.zoom.preset.custom", "Custom")
        case .fit: return I18n.t("statusbar.zoom.preset.fit", "Fit to project")
        case .day: return I18n.t("statusbar.zoom.preset.day", "Day")
        case .week: return I18n.t("statusbar.zoom.preset.week", "Week")
        case .month: return I18n.t("statusbar.zoom.preset.month", "Month")
        }
    }

    /// 日宽读数：整数不带小数位（`12 点/天`），非整数保留 1 位（`12.5 点/天`）。
    ///
    /// `nil` 与非有限值出占位符：`Int(_:)` 对 NaN / ±∞ 会 trap，不能直接转换。
    static func pointsPerDay(_ value: Double?) -> String {
        guard let value, value.isFinite else { return placeholder }
        let rounded = (value * 10).rounded() / 10
        let number: String
        if rounded == rounded.rounded(), rounded.magnitude <= 1e15 {
            number = String(Int(rounded))
        } else {
            number = String(format: "%.1f", rounded)
        }
        return I18n.t("statusbar.zoom.points_per_day", "%1$@ pts/day", number)
    }

    /// 状态栏缩放指示：档位 + 实际日宽（如「自定义 · 20 点/天」）；读数缺失时只出档位。
    static func zoomIndicator(_ zoom: ZoomIndicator) -> String {
        let preset = zoomPresetTitle(zoom.preset)
        guard zoom.pointsPerDay != nil else { return preset }
        return I18n.t("statusbar.zoom.indicator", "%1$@ · %2$@", preset, pointsPerDay(zoom.pointsPerDay))
    }

    // MARK: - 日期字段禁用原因（F-0705：可用性由呈现层给语义）

    /// 日期字段不可编辑的解释；可编辑时返回 nil（不显示解释）。
    static func dateFieldDisabledReason(_ availability: DateFieldAvailability) -> String? {
        switch availability {
        case .editable:
            return nil
        case .disabled(let reason):
            switch reason {
            case .aggregate:
                return I18n.t(
                    "date.field.disabled.aggregate",
                    "Group fields are aggregated from subtasks and read-only"
                )
            case .milestone:
                return I18n.t("date.field.disabled.milestone", "Milestones have no duration")
            case .unscheduled(let why):
                guard let why else {
                    return I18n.t("date.field.disabled.unscheduled", "Not scheduled")
                }
                return I18n.t(
                    "date.field.disabled.unscheduled_with_reason",
                    "Not scheduled (%1$@); the end date cannot be set",
                    unscheduledReason(why)
                )
            }
        }
    }

    // MARK: - 载入警告（F-0705：会话只给码与参数）

    /// 载入警告的提示文案；码没有对应文案时回落码本身（不静默吞掉警告）。
    static func loadWarning(_ warning: LoadWarning) -> String {
        switch warning.code {
        case .groupPromoted:
            return I18n.t(
                "alert.load.group_promoted",
                "Task “%1$@” has subtasks and was treated as a group",
                warning.taskTitle ?? I18n.t("inspector.violation.unknown_task", "Unknown task")
            )
        default:
            return warning.code.rawValue
        }
    }
}
