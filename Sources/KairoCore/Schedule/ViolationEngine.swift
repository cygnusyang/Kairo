import Foundation

/// 违例引擎（ADR-007：违例规则集独立于调度，在调度纯函数输出上检测）。
/// 基础集 8 条（F-30-03/04/05/06/08/13/14），规则语义见 docs/features/02-inspectors-scheduling.md。
///
/// 输出只带语义（`ViolationReason` + 参数）与稳定码（`KairoErrorCode`），不含自然语言：
/// 文案由 UI / CLI / MCP 三端各自渲染（F-0704）。
///
/// 单时限模型下的违例判定映射（每任务至多一个时限）：
///   startNoEarlierThan(x)：F-30-05，最晚开始 < x（相关性链把窗口压得过早）。
///   startNoLaterThan(x)  ：F-30-04，最早开始 > x（先决条件把开始推到时限之后）；
///                          F-30-05，x + 持续 > 最晚结束（时限与相关性链窗口冲突）。
///   endNoEarlierThan(x)  ：F-30-05，最晚结束 < x；x − 持续 < 最早开始（同上）。
///   endNoLaterThan(x)    ：F-30-04，最早结束 > x。
/// 双时限模型：任务同时带开始侧与结束侧时限且窗口 < 持续时间 → F-30-03（时限靠得太近）。
///
/// 日期算术与调度同源：一律按日历日（`Calendar` 整日加减），不按 86 400 秒折算——
/// 跨夏令时切换时秒折算会让窗口宽窄 1 小时，产生误报 / 漏报（F-0716 / D-023）。
public enum ViolationEngine {
    /// 规则目录（F-30）：违例页空态与检查器从同一来源读取，界面不复制规则清单。
    ///
    /// `code` 为既有规则码（v0.8.5 起被快照与 MCP 消费，不改值）；规则的人类可读名称
    /// 由视图按 `violation.rule.<code>` 查 Catalog，核心层不再携带文案。
    public struct RuleCategory: Codable, Hashable, Sendable {
        public var code: String
        public var severity: Violation.Severity

        public init(code: String, severity: Violation.Severity) {
            self.code = code
            self.severity = severity
        }
    }

    public static let ruleCategories: [RuleCategory] = [
        .init(code: "cycle", severity: .error),
        .init(code: "task_ends_after_project_end", severity: .error),
        .init(code: "task_starts_before_project_start", severity: .error),
        .init(code: "constraint_window_too_narrow", severity: .error),
        .init(code: "cannot_schedule_asap_alap", severity: .error),
        .init(code: "constraint_is_dependency", severity: .error),
        .init(code: "constraint_is_prerequisite", severity: .error),
        // F-0715 / D-022：开始日落在项目窗口外。v0.9.0 起新增的第 8 条规则——
        // 旧实现把这种情形报成 cycle/负宽延，规则目录里没有对应条目；
        // 违例页空态清单因此多一行，属**有意行为变更**（不是为迁就测试而改）。
        .init(code: "task_starts_outside_project_window", severity: .error)
    ]

    public static func check(
        result: ScheduleResult,
        tasks: [TaskItem],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [Violation] {
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var violations: [Violation] = []
        violations += cycleViolations(result: result, byID: byID)
        violations += projectBoundaryViolations(result: result, byID: byID)
        violations += negativeSlackViolations(result: result, byID: byID, calendar: calendar)
        violations += constraintViolations(result: result, byID: byID, calendar: calendar)
        violations += constraintWindowViolations(result: result, byID: byID, calendar: calendar)
        return violations
    }

    /// 任务标题；任务不在当前清单里时为 `nil`（渲染层决定回退说法）。
    private static func title(_ id: UUID?, _ byID: [UUID: TaskItem]) -> String? {
        guard let id, let task = byID[id] else { return nil }
        return task.title
    }

    // MARK: - F-30-08 环

    private static func cycleViolations(result: ScheduleResult, byID: [UUID: TaskItem]) -> [Violation] {
        result.cycleTaskIDs.map { id in
            Violation(
                reason: .cycle(taskTitle: title(id, byID)),
                taskID: id
            )
        }
    }

    // MARK: - F-30-13 / F-30-14 项目边界

    private static func projectBoundaryViolations(result: ScheduleResult, byID: [UUID: TaskItem]) -> [Violation] {
        var violations: [Violation] = []
        if let end = result.projectEnd {
            for s in result.tasks where s.scheduledFinish > end {
                violations.append(Violation(
                    reason: .taskAfterProjectEnd(taskTitle: title(s.taskID, byID)),
                    taskID: s.taskID
                ))
            }
        }
        if let start = result.projectStart {
            for s in result.tasks where s.scheduledStart < start {
                violations.append(Violation(
                    reason: .taskBeforeProjectStart(taskTitle: title(s.taskID, byID)),
                    taskID: s.taskID
                ))
            }
        }
        return violations
    }

    // MARK: - F-30-03 时限靠得太近（开始侧与结束侧时限窗口容不下持续时间）

    private static func constraintWindowViolations(
        result: ScheduleResult,
        byID: [UUID: TaskItem],
        calendar: Calendar
    ) -> [Violation] {
        result.tasks.compactMap { s in
            guard let task = byID[s.taskID], task.constraint != nil else { return nil }
            guard let windowDays = Self.constraintWindowDays(for: task, calendar: calendar) else {
                return nil
            }
            guard windowDays < s.durationDays else { return nil }
            return Violation(
                reason: .constraintWindowTooNarrow(
                    taskTitle: task.title,
                    windowDays: Int(windowDays),
                    requiredDays: Int(s.durationDays)
                ),
                taskID: s.taskID
            )
        }
    }

    /// 同时存在开始侧与结束侧时限时，返回两者间隔（日历日）；否则 nil。
    private static func constraintWindowDays(for task: TaskItem, calendar: Calendar) -> Double? {
        guard let c = task.constraint else { return nil }
        let startSide: Date?
        let endSide: Date?
        switch c {
        case .startNoEarlierThan(let d), .startNoLaterThan(let d):
            startSide = d
            endSide = nil
        case .endNoEarlierThan(let d), .endNoLaterThan(let d):
            startSide = nil
            endSide = d
        }
        // 单侧时限无窗口概念（另一侧来自相关性传播），交由 F-30-04/05 处理。
        guard let start = startSide ?? task.startDate, let end = endSide ?? task.dueDate else {
            return nil
        }
        return daysBetween(start, end, in: calendar)
    }

    // MARK: - F-30-06 负宽延（无法安排 ASAP/ALAP）

    private static func negativeSlackViolations(
        result: ScheduleResult,
        byID: [UUID: TaskItem],
        calendar: Calendar
    ) -> [Violation] {
        result.tasks.compactMap { s in
            guard s.totalSlackDays < 0 else { return nil }
            // F-0715 / D-022：任务开始日落在项目窗口外时，负宽延是用户输入的后果，
            // 不是相关性链的后果——归因改抛 `startAfterProjectWindow`，参数带具体日期。
            if let attribution = windowEscape(
                scheduled: s, task: byID[s.taskID], result: result, calendar: calendar
            ) {
                return Violation(reason: attribution, taskID: s.taskID)
            }
            return Violation(
                reason: .negativeSlack(taskTitle: title(s.taskID, byID)),
                taskID: s.taskID
            )
        }
    }

    /// 任务开始日是否落在项目窗口外；落在窗口外时返回归因（含具体日期）。
    ///
    /// 判定基准优先取用户输入（`TaskItem.startDate`），没有输入时退回排期的最早开始：
    /// 前者是「用户写了窗口外的日期」，后者是「时限 / 相关性把任务挤出窗口」，
    /// 两者都属于输入致因，但都不能归给「无法安排」。
    private static func windowEscape(
        scheduled: ScheduledTask,
        task: TaskItem?,
        result: ScheduleResult,
        calendar: Calendar
    ) -> ViolationReason? {
        guard let projectStart = result.projectStart, let projectEnd = result.projectEnd else {
            return nil
        }
        let taskStart = task?.startDate.map { calendar.startOfDay(for: $0) }
            ?? scheduled.earliestStart
        guard taskStart > projectEnd || taskStart < projectStart else { return nil }
        return .startAfterProjectWindow(
            taskTitle: task?.title,
            taskStart: taskStart,
            projectStart: projectStart,
            projectEnd: projectEnd
        )
    }

    // MARK: - F-30-03 / 04 / 05 时限

    private static func constraintViolations(
        result: ScheduleResult,
        byID: [UUID: TaskItem],
        calendar: Calendar
    ) -> [Violation] {
        var violations: [Violation] = []
        for s in result.tasks {
            guard let task = byID[s.taskID], let c = task.constraint else { continue }
            let x = calendar.startOfDay(for: c.date)
            switch c {
            case .startNoEarlierThan:
                if s.latestStart < x {
                    violations.append(Violation(
                        reason: .constraintConflict(
                            taskTitle: task.title,
                            kind: .startNoEarlierThan,
                            conflict: .latestBeforeConstraint
                        ),
                        taskID: s.taskID
                    ))
                }
            case .startNoLaterThan:
                if s.earliestStart > x {
                    violations.append(Violation(
                        reason: .constraintUnmetByPrerequisite(
                            taskTitle: task.title,
                            kind: .startNoLaterThan
                        ),
                        taskID: s.taskID
                    ))
                }
                if addDays(x, s.durationDays, in: calendar) > s.latestFinish {
                    violations.append(Violation(
                        reason: .constraintConflict(
                            taskTitle: task.title,
                            kind: .startNoLaterThan,
                            conflict: .windowDoesNotFit
                        ),
                        taskID: s.taskID
                    ))
                }
            case .endNoEarlierThan:
                if s.latestFinish < x {
                    violations.append(Violation(
                        reason: .constraintConflict(
                            taskTitle: task.title,
                            kind: .endNoEarlierThan,
                            conflict: .latestBeforeConstraint
                        ),
                        taskID: s.taskID
                    ))
                }
                if addDays(x, -s.durationDays, in: calendar) < s.earliestStart {
                    violations.append(Violation(
                        reason: .constraintConflict(
                            taskTitle: task.title,
                            kind: .endNoEarlierThan,
                            conflict: .windowDoesNotFit
                        ),
                        taskID: s.taskID
                    ))
                }
            case .endNoLaterThan:
                if s.earliestFinish > x {
                    violations.append(Violation(
                        reason: .constraintUnmetByPrerequisite(
                            taskTitle: task.title,
                            kind: .endNoLaterThan
                        ),
                        taskID: s.taskID
                    ))
                }
            }
        }
        return violations
    }

    // MARK: - 日历日算术（与 ScheduleEngine 同口径）

    /// 一天的秒数：仅用于小数天余量与日历换算失败时的兜底，不参与整日算术。
    private static let secondsPerDay: Double = 86_400

    /// 按日历日加减（夏令时安全）：整日部分走 `Calendar`，跨 DST 后仍落在本地零点。
    private static func addDays(_ date: Date, _ days: Double, in calendar: Calendar) -> Date {
        let wholeDays = days.rounded(.towardZero)
        let base: Date
        if let whole = Int(exactly: wholeDays), whole != 0,
           let shifted = calendar.date(byAdding: .day, value: whole, to: date) {
            base = shifted
        } else {
            base = date.addingTimeInterval(wholeDays * secondsPerDay)
        }
        let remainder = days - wholeDays
        return remainder == 0 ? base : base.addingTimeInterval(remainder * secondsPerDay)
    }

    /// 日历日差：整日部分取 `Calendar` 的日差（跨 DST 仍是 N 天），余量按 86 400 秒折算。
    private static func daysBetween(_ from: Date, _ to: Date, in calendar: Calendar) -> Double {
        let wholeDays = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        guard let shifted = calendar.date(byAdding: .day, value: wholeDays, to: from) else {
            return to.timeIntervalSince(from) / secondsPerDay
        }
        return Double(wholeDays) + to.timeIntervalSince(shifted) / secondsPerDay
    }
}
