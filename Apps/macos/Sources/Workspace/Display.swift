import Foundation
import KairoCommands
import KairoCore
import KairoPresentation

/// 视图层文案与格式化：术语与核心层一致，同一事物全篇同一名称。
enum Display {
    /// 空值占位符：日期 / 时长 / 读数缺失时统一用它。
    static let placeholder = "—"

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/M/d"
        return formatter
    }()

    static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter
    }()

    static func date(_ value: Date?) -> String {
        guard let value else { return "—" }
        return dateFormatter.string(from: value)
    }

    static func shortDate(_ value: Date?) -> String {
        guard let value else { return "—" }
        return shortDateFormatter.string(from: value)
    }

    /// 检查器日期字段的行内格式 `2026-11-06`。
    ///
    /// 与 `date`（`yyyy/M/d`）分开：大纲列、违例文案与 CLI 输出沿用既有格式，
    /// 只有日历字段行用 ISO 口径（F-14-10 / R7）。
    static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func isoDate(_ value: Date?) -> String {
        guard let value else { return "—" }
        return isoDateFormatter.string(from: value)
    }

    /// 月历头部「2026 年 11 月」。
    static func monthTitle(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0) 年 \(parts.month ?? 1) 月"
    }

    /// 星期表头短名，按 `calendar.firstWeekday` 起排（周首为周一则首项为「一」）。
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        // Calendar.weekday：1 = 周日 … 7 = 周六。
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let first = calendar.firstWeekday
        return (0..<7).map { index in
            names[(first - 1 + index) % 7]
        }
    }

    /// 无障碍日期标签「11 月 2 日，星期日」。
    static func dayLabel(_ day: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day, .weekday], from: day)
        let names = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        let weekday = parts.weekday ?? 1
        let name = names[min(max(weekday - 1, 0), names.count - 1)]
        return "\(parts.month ?? 0) 月 \(parts.day ?? 0) 日，\(name)"
    }

    static func duration(_ days: Double?) -> String {
        guard let days else { return "—" }
        if abs(days.rounded() - days) < 0.0001 {
            return "\(Int(days)) 天"
        }
        return String(format: "%.1f 天", days)
    }

    static func percent(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    /// 大纲列名：列显隐菜单与「显示/隐藏X列」命令共用同一份文案（F-14-20）。
    static func outlineColumnTitle(_ column: OutlineColumn) -> String {
        switch column {
        case .status: return "状态"
        case .violation: return "违例"
        case .number: return "序号"
        case .title: return "任务说明"
        case .predecessors: return "前置"
        case .start: return "开始"
        case .finish: return "结束"
        case .duration: return "持续"
        case .assignee: return "负责人"
        case .progress: return "完成"
        }
    }

    static func statusTitle(_ status: TaskStatus) -> String {
        switch status {
        case .pending: return "待办"
        case .inProgress: return "进行中"
        case .blocked: return "阻塞"
        case .done: return "完成"
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
        case .low: return "低"
        case .normal: return "普通"
        case .high: return "高"
        case .critical: return "紧急"
        }
    }

    static func kindTitle(_ kind: TaskKind) -> String {
        switch kind {
        case .task: return "任务"
        case .group: return "群组"
        case .milestone: return "里程碑"
        }
    }

    static func dependencyTitle(_ type: TaskDependency.DependencyType) -> String {
        switch type {
        case .fs: return "完成 → 开始"
        case .ff: return "完成 → 完成"
        case .ss: return "开始 → 开始"
        case .sf: return "开始 → 完成"
        }
    }

    static func unscheduledReason(_ reason: UnscheduledReason?) -> String {
        switch reason {
        case .cycle: return "依赖环"
        case .emptyGroup: return "空群组"
        case .unavailable: return "不可排期"
        case nil: return "未排期"
        }
    }

    static func directionTitle(_ direction: ScheduleDirection) -> String {
        switch direction {
        case .forward: return "尽快开始（ASAP）"
        case .backward: return "尽快结束（ALAP）"
        }
    }

    static func scheduleTitle(_ policy: SchedulingPolicy) -> String {
        policy == .asap ? "ASAP（尽早）" : "ALAP（尽晚）"
    }

    static func healthTitle(_ health: ProjectSummary.Health) -> String {
        switch health {
        case .green: return "健康"
        case .orange: return "注意"
        case .red: return "风险"
        }
    }

    static func saveStateTitle(_ state: SaveState) -> String {
        switch state {
        case .saved: return "已保存"
        case .unsaved: return "未保存"
        case .failed: return "保存失败"
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
