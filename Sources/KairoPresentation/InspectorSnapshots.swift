import Foundation
import KairoCore

/// 依赖行（前置/后继只读列表）。
public struct DependencyRow: Identifiable, Hashable, Sendable {
    public var id: UUID { taskID }
    public var taskID: UUID
    public var title: String
    public var type: TaskDependency.DependencyType
    public var lagDays: Double
    public var isScheduled: Bool

    public init(
        taskID: UUID,
        title: String,
        type: TaskDependency.DependencyType,
        lagDays: Double,
        isScheduled: Bool
    ) {
        self.taskID = taskID
        self.title = title
        self.type = type
        self.lagDays = lagDays
        self.isScheduled = isScheduled
    }
}

/// 最近完成条目。
public struct CompletedTask: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var completedAt: Date

    public init(id: UUID, title: String, completedAt: Date) {
        self.id = id
        self.title = title
        self.completedAt = completedAt
    }
}

/// 项目页内容。
public struct ProjectInspector: Hashable, Sendable {
    public var title: String
    public var projectStart: Date?
    public var projectEnd: Date?
    public var direction: ScheduleDirection
    public var summary: ProjectSummary
    public var recentCompletions: [CompletedTask]
    public var saveState: SaveState

    public init(
        title: String,
        projectStart: Date? = nil,
        projectEnd: Date? = nil,
        direction: ScheduleDirection,
        summary: ProjectSummary,
        recentCompletions: [CompletedTask] = [],
        saveState: SaveState
    ) {
        self.title = title
        self.projectStart = projectStart
        self.projectEnd = projectEnd
        self.direction = direction
        self.summary = summary
        self.recentCompletions = recentCompletions
        self.saveState = saveState
    }
}

/// 任务页内容。群组字段只读并标注聚合。
public struct TaskInspector: Hashable, Sendable {
    public var taskID: UUID
    public var title: String
    public var kind: TaskKind
    public var status: TaskStatus
    public var priority: TaskPriority
    public var tags: [String]
    public var assignee: String?
    public var notes: String
    public var scheduledStart: Date?
    public var scheduledFinish: Date?
    /// 「开始」字段的用户意图（排期结果见 scheduledStart）；群组为 nil。
    public var startDate: Date?
    public var durationDays: Double?
    public var effortHours: Double?
    public var slackDays: Double?
    public var dueDate: Date?
    public var deadlineRisk: Bool
    public var isOverdue: Bool
    public var progress: Double
    public var completedAt: Date?
    public var constraint: SchedulingConstraint?
    public var schedulingPolicy: SchedulingPolicy
    public var isAggregate: Bool
    public var hasSchedule: Bool
    public var unscheduledReason: UnscheduledReason?
    public var predecessors: [DependencyRow]
    public var successors: [DependencyRow]
    public var violations: [Violation]
    public var assignmentNames: [String]

    public init(
        taskID: UUID,
        title: String,
        kind: TaskKind,
        status: TaskStatus,
        priority: TaskPriority,
        tags: [String] = [],
        assignee: String? = nil,
        notes: String = "",
        scheduledStart: Date? = nil,
        scheduledFinish: Date? = nil,
        durationDays: Double? = nil,
        effortHours: Double? = nil,
        slackDays: Double? = nil,
        dueDate: Date? = nil,
        deadlineRisk: Bool = false,
        isOverdue: Bool = false,
        progress: Double = 0,
        completedAt: Date? = nil,
        constraint: SchedulingConstraint? = nil,
        schedulingPolicy: SchedulingPolicy = .asap,
        isAggregate: Bool = false,
        hasSchedule: Bool = false,
        unscheduledReason: UnscheduledReason? = nil,
        predecessors: [DependencyRow] = [],
        successors: [DependencyRow] = [],
        violations: [Violation] = [],
        assignmentNames: [String] = [],
        startDate: Date? = nil
    ) {
        self.taskID = taskID
        self.title = title
        self.kind = kind
        self.status = status
        self.priority = priority
        self.tags = tags
        self.assignee = assignee
        self.notes = notes
        self.scheduledStart = scheduledStart
        self.scheduledFinish = scheduledFinish
        self.startDate = startDate
        self.durationDays = durationDays
        self.effortHours = effortHours
        self.slackDays = slackDays
        self.dueDate = dueDate
        self.deadlineRisk = deadlineRisk
        self.isOverdue = isOverdue
        self.progress = progress
        self.completedAt = completedAt
        self.constraint = constraint
        self.schedulingPolicy = schedulingPolicy
        self.isAggregate = isAggregate
        self.hasSchedule = hasSchedule
        self.unscheduledReason = unscheduledReason
        self.predecessors = predecessors
        self.successors = successors
        self.violations = violations
        self.assignmentNames = assignmentNames
    }
}

/// 违例页条目（F-0704）：只带码 + 语义 + 参数，标题与原因文案由视图按 Catalog 渲染。
///
/// name / message 两个中文整句字段已删除——快照跨 UI / CLI / MCP 复用，
/// 携带文案会把接口层的语言策略绑死在呈现层（ADR-013）。
public struct ViolationItem: Identifiable, Hashable, Sendable {
    /// 同一任务可能出多条同码违例（如「结束不早于」同时触发两条冲突），
    /// 故 ID 带上 reason 的全部参数，不能只用码。
    public var id: String {
        "\(code.rawValue)-\(taskID?.uuidString ?? "project")-\(String(describing: reason))"
    }
    public var code: KairoErrorCode
    public var reason: ViolationReason
    public var severity: Violation.Severity
    public var taskID: UUID?
    public var taskTitle: String?

    public init(
        code: KairoErrorCode,
        reason: ViolationReason,
        severity: Violation.Severity,
        taskID: UUID? = nil,
        taskTitle: String? = nil
    ) {
        self.code = code
        self.reason = reason
        self.severity = severity
        self.taskID = taskID
        self.taskTitle = taskTitle
    }
}

/// 违例页内容：按 error / warning 分组；空态列出已检查规则类别。
public struct ViolationInspector: Hashable, Sendable {
    public struct Group: Identifiable, Hashable, Sendable {
        public var id: Violation.Severity { severity }
        public var severity: Violation.Severity
        public var items: [ViolationItem]

        public init(severity: Violation.Severity, items: [ViolationItem]) {
            self.severity = severity
            self.items = items
        }
    }

    public var groups: [Group]
    public var errorCount: Int
    public var warningCount: Int
    public var checkedRules: [ViolationEngine.RuleCategory]

    public init(
        groups: [Group],
        errorCount: Int,
        warningCount: Int,
        checkedRules: [ViolationEngine.RuleCategory] = ViolationEngine.ruleCategories
    ) {
        self.groups = groups
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.checkedRules = checkedRules
    }
}

/// 检查器快照。
public struct InspectorSnapshot: Hashable, Sendable {
    public enum Content: Hashable, Sendable {
        case project(ProjectInspector)
        case task(TaskInspector)
        case violations(ViolationInspector)
    }

    public var content: Content
    public var tab: InspectorTab
    public var locked: Bool
    /// 选择漂移：锁定任务已删除或外部重载后缺失。
    public var selectionMissing: Bool

    public init(
        content: Content,
        tab: InspectorTab,
        locked: Bool = false,
        selectionMissing: Bool = false
    ) {
        self.content = content
        self.tab = tab
        self.locked = locked
        self.selectionMissing = selectionMissing
    }
}
