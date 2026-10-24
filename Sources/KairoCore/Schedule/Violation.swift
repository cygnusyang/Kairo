import Foundation

/// 时限方向（F-30 违例参数）：违例文案需要指明是哪一侧的时限出问题。
public enum ConstraintKind: String, Codable, Hashable, Sendable {
    case startNoEarlierThan
    case startNoLaterThan
    case endNoEarlierThan
    case endNoLaterThan
}

/// 时限冲突的形态（F-30-05）：最晚窗口早于时限，还是窗口装不下持续时间。
public enum ConstraintConflict: String, Codable, Hashable, Sendable {
    /// 最晚开始 / 结束早于时限（相关性链把窗口压得过早）。
    case latestBeforeConstraint
    /// 时限给出的窗口容不下任务持续时间。
    case windowDoesNotFit
}

/// 违例语义（F-0704 / 设计 §B）：规则 + 参数，不含任何自然语言。
///
/// 中文 / 英文文案由三端各自渲染：UI 走 String Catalog，CLI 与 MCP 各持渲染器
/// （阶段一逐字等于 v0.8.5 文案）。`taskTitle` 为 `nil` 表示任务已不在当前项目里
/// （例如刚被删除），由渲染层决定回退说法，核心层不再写「未知任务」。
public enum ViolationReason: Codable, Hashable, Sendable {
    /// F-30-08：任务处于相关性环中。
    case cycle(taskTitle: String?)
    /// F-30-13：任务结束晚于项目结束。
    case taskAfterProjectEnd(taskTitle: String?)
    /// F-30-14：任务开始早于项目开始。
    case taskBeforeProjectStart(taskTitle: String?)
    /// F-30-03：开始侧与结束侧时限相距过近，容不下持续时间。
    case constraintWindowTooNarrow(taskTitle: String?, windowDays: Int, requiredDays: Int)
    /// F-30-06：最晚开始早于最早开始（负宽延），无法安排。
    case negativeSlack(taskTitle: String?)
    /// F-30-05：时限与相关性链冲突（最晚窗口早于时限 / 窗口装不下持续时间）。
    case constraintConflict(taskTitle: String?, kind: ConstraintKind, conflict: ConstraintConflict)
    /// F-30-04：先决条件把开始 / 结束推过时限。
    case constraintUnmetByPrerequisite(taskTitle: String?, kind: ConstraintKind)

    /// 与 `KairoErrorCode` 的稳定映射（1:1，接口层按此输出 `code`）。
    public var code: KairoErrorCode {
        switch self {
        case .cycle: return .scheduleCycle
        case .taskAfterProjectEnd: return .taskAfterProjectEnd
        case .taskBeforeProjectStart: return .taskBeforeProjectStart
        case .constraintWindowTooNarrow: return .constraintWindowTooNarrow
        case .negativeSlack: return .negativeSlack
        case .constraintConflict: return .constraintVsDependency
        case .constraintUnmetByPrerequisite: return .constraintVsPrerequisite
        }
    }

    /// 涉及任务标题；任务已不在项目里时为 `nil`。
    public var taskTitle: String? {
        switch self {
        case .cycle(let title),
             .taskAfterProjectEnd(let title),
             .taskBeforeProjectStart(let title),
             .constraintWindowTooNarrow(let title, _, _),
             .negativeSlack(let title),
             .constraintConflict(let title, _, _),
             .constraintUnmetByPrerequisite(let title, _):
            return title
        }
    }
}

/// 违例（F-30-01）：排期 / 约束逻辑问题的一条记录。
///
/// 只携带语义（`reason`）与稳定码（`code`），不含自然语言——快照要跨 UI / CLI / MCP
/// 三端复用，一旦携带中文，接口层的语言策略就被呈现层绑死（ADR-013）。
public struct Violation: Codable, Hashable, Sendable {
    public enum Severity: String, Codable, Sendable {
        case error
        case warning
    }

    /// 违例语义与参数。
    public var reason: ViolationReason
    /// 涉及任务（可能为空，如仅项目级违例）。
    public var taskID: UUID?
    /// 严重级别：error = 阻断安排的问题；warning = 提示。
    public var severity: Severity

    /// 稳定错误码（由 `reason` 推导，接口层序列化的 `code` 字段）。
    public var code: KairoErrorCode { reason.code }

    public init(reason: ViolationReason, taskID: UUID? = nil, severity: Severity = .error) {
        self.reason = reason
        self.taskID = taskID
        self.severity = severity
    }
}
