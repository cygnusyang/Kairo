import Foundation
import KairoCore
import KairoPresentation

/// 违例与规则名的视图层渲染（F-0705）：快照只给码与语义参数，文案全部走 String Catalog。
///
/// 核心层与呈现层已删除 `Violation.message` / `RuleCategory.name`（ADR-013）——
/// 同一份语义数据要给 UI、CLI、MCP 三端用，文案只能留在各自的渲染层。
enum ViolationText {
    /// 违例句整句（任务标题缺失时用「未知任务」兜底，与 v0.8.5 一致）。
    static func message(_ reason: ViolationReason) -> String {
        let title = reason.taskTitle ?? I18n.t("inspector.violation.unknown_task", "Unknown task")
        switch reason {
        case .cycle:
            return I18n.t(
                "violation.cycle.message",
                "Task “%1$@” is part of a dependency cycle, so its order cannot be determined",
                title
            )
        case .taskAfterProjectEnd:
            return I18n.t(
                "violation.task_after_project_end.message",
                "Task “%1$@” ends after the project end date",
                title
            )
        case .taskBeforeProjectStart:
            return I18n.t(
                "violation.task_before_project_start.message",
                "Task “%1$@” starts before the project start date",
                title
            )
        case .constraintWindowTooNarrow(_, let windowDays, let requiredDays):
            return I18n.t(
                "violation.constraint_window_too_narrow.message",
                "Task “%1$@”: its start and end constraints are only %2$ld days apart and cannot hold the %3$ld-day duration",
                title,
                windowDays,
                requiredDays
            )
        case .negativeSlack:
            return I18n.t(
                "violation.negative_slack.message",
                "Task “%1$@” cannot be scheduled: latest start is before earliest start (negative slack)",
                title
            )
        case .constraintConflict(_, let kind, let conflict):
            return I18n.t(
                "violation.constraint_conflict.message",
                "Task “%1$@”: its “%2$@” constraint conflicts with the dependency chain: %3$@",
                title,
                kindTitle(kind),
                conflictDetail(kind: kind, conflict: conflict)
            )
        case .constraintUnmetByPrerequisite(_, let kind):
            return I18n.t(
                "violation.constraint_unmet_by_prerequisite.message",
                "Task “%1$@” cannot meet its “%2$@” constraint because of prerequisites",
                title,
                kindTitle(kind)
            )
        case .startAfterProjectWindow(_, let taskStart, let projectStart, let projectEnd):
            return I18n.t(
                "violation.start_after_project_window.message",
                "Task “%1$@” starts on %2$@, outside the project window (%3$@ – %4$@); adjust the task start date",
                title,
                Display.isoDate(taskStart),
                Display.isoDate(projectStart),
                Display.isoDate(projectEnd)
            )
        }
    }

    /// 规则名：键 `violation.rule.<规则码>`；规则码取自 `ViolationEngine.RuleCategory.code`
    /// 与 F-0715 的 `start_after_project_window`（两个来源共用一套键空间）。
    static func ruleName(_ code: String) -> String {
        I18n.t("violation.rule.\(code)", fallbackRuleName(code))
    }

    /// 规则码对应的规则名（同一条违例的标题与空态规则清单共用）。
    static func ruleName(for reason: ViolationReason) -> String {
        ruleName(ruleCode(reason))
    }

    /// 违例语义 → 规则码（`RuleCategory.code` 口径）。
    static func ruleCode(_ reason: ViolationReason) -> String {
        switch reason {
        case .cycle: return "cycle"
        case .taskAfterProjectEnd: return "task_ends_after_project_end"
        case .taskBeforeProjectStart: return "task_starts_before_project_start"
        case .constraintWindowTooNarrow: return "constraint_window_too_narrow"
        case .negativeSlack: return "cannot_schedule_asap_alap"
        case .constraintConflict: return "constraint_is_dependency"
        case .constraintUnmetByPrerequisite: return "constraint_is_prerequisite"
        case .startAfterProjectWindow: return "start_after_project_window"
        }
    }

    /// 时限方向名（`「开始不早于」时限` 里的那段）。
    static func kindTitle(_ kind: ConstraintKind) -> String {
        switch kind {
        case .startNoEarlierThan:
            return I18n.t("violation.kind.start_no_earlier_than", "Start no earlier than")
        case .startNoLaterThan:
            return I18n.t("violation.kind.start_no_later_than", "Start no later than")
        case .endNoEarlierThan:
            return I18n.t("violation.kind.end_no_earlier_than", "End no earlier than")
        case .endNoLaterThan:
            return I18n.t("violation.kind.end_no_later_than", "End no later than")
        }
    }

    private static func conflictDetail(kind: ConstraintKind, conflict: ConstraintConflict) -> String {
        switch conflict {
        case .windowDoesNotFit:
            return I18n.t(
                "violation.constraint_conflict.window_does_not_fit",
                "the window cannot hold the task duration"
            )
        case .latestBeforeConstraint:
            switch kind {
            case .startNoEarlierThan, .startNoLaterThan:
                return I18n.t(
                    "violation.constraint_conflict.latest_start_before_constraint",
                    "latest start is before the constraint"
                )
            case .endNoEarlierThan, .endNoLaterThan:
                return I18n.t(
                    "violation.constraint_conflict.latest_end_before_constraint",
                    "latest end is before the constraint"
                )
            }
        }
    }

    /// 调用点英文兜底：与 Catalog 里的 en 源串逐字相同（§D.5 的两处英文由评审保证不漂移）。
    private static func fallbackRuleName(_ code: String) -> String {
        switch code {
        case "cycle": return "Dependency cycle"
        case "task_ends_after_project_end": return "Task ends after project end"
        case "task_starts_before_project_start": return "Task starts before project start"
        case "constraint_window_too_narrow": return "Constraint window too narrow"
        case "cannot_schedule_asap_alap": return "Cannot schedule (negative slack)"
        case "constraint_is_dependency": return "Constraint conflicts with dependency chain"
        case "constraint_is_prerequisite": return "Prerequisite blocks constraint"
        case "start_after_project_window": return "Start outside project window"
        default: return code
        }
    }
}
