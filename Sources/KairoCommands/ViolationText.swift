import Foundation
import KairoCore

/// 违例的人类可读文案：唯一实现在命令层，CLI 与 MCP 共用同一份，避免两套文案漂移。
///
/// zh-Hans 列逐字等于 v0.8.5 的 ViolationEngine 消息模板（startAfterProjectWindow 除外，
/// 该归因为 v0.9.0 新增，中文与视图 Catalog 的 violation.start_after_project_window.message 对齐）。
/// 核心层与呈现层不持有自然语言（ADR-013）：快照只带 ViolationReason，文本在此渲染。
public enum ViolationText {
    public enum Language: Sendable {
        case zhHans
        case en
    }

    public static func text(_ violation: Violation, language: Language) -> String {
        text(violation.reason, language: language)
    }

    public static func text(_ reason: ViolationReason, language: Language) -> String {
        switch reason {
        case .cycle(let title):
            return t(language,
                     "任务「\(taskTitle(title, language))」处于相关性环中，无法确定先后顺序",
                     "task \"\(taskTitle(title, language))\" is in a dependency cycle; its order cannot be determined")
        case .taskAfterProjectEnd(let title):
            return t(language,
                     "任务「\(taskTitle(title, language))」的结束日期晚于项目结束日期",
                     "task \"\(taskTitle(title, language))\" finishes after the project end date")
        case .taskBeforeProjectStart(let title):
            return t(language,
                     "任务「\(taskTitle(title, language))」的开始日期早于项目开始日期",
                     "task \"\(taskTitle(title, language))\" starts before the project start date")
        case .constraintWindowTooNarrow(let title, let windowDays, let requiredDays):
            return t(language,
                     "任务「\(taskTitle(title, language))」的开始时限与结束时限相距过近（\(windowDays) 天），"
                        + "无法容纳持续时间（\(requiredDays) 天）",
                     "task \"\(taskTitle(title, language))\" has start and end constraints only \(windowDays) day(s) apart, "
                        + "which cannot fit its \(requiredDays) day duration")
        case .negativeSlack(let title):
            return t(language,
                     "任务「\(taskTitle(title, language))」无法安排：最晚开始早于最早开始（负宽延）",
                     "task \"\(taskTitle(title, language))\" cannot be scheduled: latest start precedes earliest start (negative slack)")
        case .constraintConflict(let title, let kind, let conflict):
            let relation = conflict == .latestBeforeConstraint
                ? t(language, "最晚\(side(kind, language))早于时限", "latest \(side(kind, language)) is earlier than the constraint")
                : t(language, "窗口无法容纳任务持续时间", "the window cannot fit the task duration")
            return t(language,
                     "任务「\(taskTitle(title, language))」的「\(constraintName(kind, language))」时限与相关性链冲突：\(relation)",
                     "task \"\(taskTitle(title, language))\" \"\(constraintName(kind, language))\" constraint conflicts with the dependency "
                        + "chain: \(relation)")
        case .constraintUnmetByPrerequisite(let title, let kind):
            return t(language,
                     "任务「\(taskTitle(title, language))」因先决条件无法满足「\(constraintName(kind, language))」时限",
                     "task \"\(taskTitle(title, language))\" cannot satisfy its \"\(constraintName(kind, language))\" constraint because of "
                        + "predecessors")
        case .startAfterProjectWindow(let title, let taskStart, let projectStart, let projectEnd):
            return t(language,
                     "任务「\(taskTitle(title, language))」的开始日期 \(calendarDay(taskStart)) 晚于项目可排窗口"
                        + "（\(calendarDay(projectStart)) – \(calendarDay(projectEnd))），请调整任务开始日期",
                     "Task \"\(taskTitle(title, language))\" starts on \(calendarDay(taskStart)), outside the project window "
                        + "(\(calendarDay(projectStart)) – \(calendarDay(projectEnd))); adjust the task start date")
        }
    }

    /// 日历日文本（yyyy-MM-dd）：契约格式，不随语言变化（en_US_POSIX）。
    public static func calendarDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private static func t(_ language: Language, _ zh: String, _ en: String) -> String {
        language == .zhHans ? zh : en
    }

    private static func taskTitle(_ title: String?, _ language: Language) -> String {
        title ?? t(language, "未知任务", "unknown task")
    }

    private static func constraintName(_ kind: ConstraintKind, _ language: Language) -> String {
        switch kind {
        case .startNoEarlierThan: return t(language, "开始不早于", "start no earlier than")
        case .startNoLaterThan: return t(language, "开始不晚于", "start no later than")
        case .endNoEarlierThan: return t(language, "结束不早于", "end no earlier than")
        case .endNoLaterThan: return t(language, "结束不晚于", "end no later than")
        }
    }

    private static func side(_ kind: ConstraintKind, _ language: Language) -> String {
        switch kind {
        case .startNoEarlierThan, .startNoLaterThan: return t(language, "开始", "start")
        case .endNoEarlierThan, .endNoLaterThan: return t(language, "结束", "finish")
        }
    }
}
