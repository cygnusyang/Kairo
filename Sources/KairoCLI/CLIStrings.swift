import Foundation
import KairoCore

/// CLI 人类可读文案（F-0707 · 设计 §3「CLI / MCP 各自渲染」）。
///
/// 为什么是一张代码内的表而不是 String Catalog：\`dist/KairoCLI\` 是裸可执行文件，
/// 没有 \`Info.plist\` 与 \`.lproj\` 宿主，Catalog 取不到译文（设计 §7.4）。
///
/// **阶段一约束**：\`zh-Hans\` 列逐字等于 v0.8.5 的输出（含全角括号、全角冒号与
/// 「」引号），既有中文脚本与断言继续命中；\`en\` 列为新增，一律半角标点。
///
/// 边界：\`KairoCommands\` 的 \`SessionError.message\` 阶段一仍是中文（设计 §A.2），
/// CLI 直接透传、不在本表重写——本表只负责 CLI 自己拼的文案。
struct CLIStrings: Sendable {
    let language: CLILanguage

    init(language: CLILanguage) { self.language = language }

    /// 成对书写中英文，避免两处 switch 各自漂移。
    private func t(_ zh: @autoclosure () -> String, _ en: @autoclosure () -> String) -> String {
        language == .zhHans ? zh() : en()
    }

    // MARK: - 通用前缀

    /// 用法错误的行首（退出码 2）。
    func usagePrefix(_ message: String) -> String {
        t("用法错误：" + message, "usage error: " + message)
    }

    /// 运行时错误的行首（退出码 1）。
    func errorPrefix(_ message: String) -> String {
        t("错误：" + message, "error: " + message)
    }

    // MARK: - 操作数名（用法错误的 <占位> 与其后紧跟的名词）

    var operandTitle: String { t("标题", "title") }
    var operandFilePath: String { t("文件路径", "file path") }
    var operandTaskID: String { t("任务 ID", "task ID") }
    var operandJSONFile: String { t("JSON 文件", "JSON file") }
    var operandResourceName: String { t("资源名称", "resource name") }
    var operandProjectStart: String { t("项目开始", "project start") }
    var operandProjectEnd: String { t("项目结束", "project end") }
    var operandLanguageValue: String { t("--lang 的值", "--lang value") }

    // MARK: - 参数与选项校验

    func missingOperand(_ name: String) -> String {
        t("缺少参数：<\(name)>", "missing argument: <\(name)>")
    }

    func unknownOption(_ item: String, allowed: [String]) -> String {
        let list = allowed.joined(separator: " ")
        return t("未知选项：\(item)（可用：\(list)）", "unknown option: \(item) (allowed: \(list))")
    }

    func unknownCommand(group: String, command: String) -> String {
        t("未知命令：\(group) \(command)", "unknown command: \(group) \(command)")
    }

    /// 空子命令 / 空命令组的占位（未知命令提示用）。
    var emptyLabel: String { t("(空)", "(empty)") }

    func missingLanguageValue() -> String {
        let list = CLILanguage.allowedValues.joined(separator: "/")
        return t(
            "缺少参数：<--lang 的值>（可选 \(list)）",
            "missing argument: <--lang value> (allowed: \(list))"
        )
    }

    func invalidLanguage(_ raw: String) -> String {
        let list = CLILanguage.allowedValues.joined(separator: "/")
        return t("无效语言：\(raw)（可选 \(list)）", "invalid language: \(raw) (allowed: \(list))")
    }

    func invalidDateOption(field: String, raw: String) -> String {
        t(
            "无效的\(field)日期：\(raw)（ISO8601 或 YYYY-MM-DD）",
            "invalid \(field) date: \(raw) (ISO8601 or YYYY-MM-DD)"
        )
    }

    // MARK: - 枚举参数（CLIEnums）

    func invalidKind(_ raw: String) -> String {
        t("无效类型：\(raw)（可选 task/group/milestone）", "invalid kind: \(raw) (expected task/group/milestone)")
    }

    func invalidPriority(_ raw: String) -> String {
        t(
            "无效优先级：\(raw)（可选 low/normal/high/critical）",
            "invalid priority: \(raw) (expected low/normal/high/critical)"
        )
    }

    func invalidStatus(_ raw: String) -> String {
        t(
            "无效状态：\(raw)（可选 pending/in_progress/done/blocked）",
            "invalid status: \(raw) (expected pending/in_progress/done/blocked)"
        )
    }

    func invalidSchedulingPolicy(_ raw: String) -> String {
        t("无效调度策略：\(raw)（可选 asap/alap）", "invalid scheduling policy: \(raw) (expected asap/alap)")
    }

    func invalidConstraintSpec(_ raw: String) -> String {
        t(
            "无效时限：\(raw)（格式 type:日期，如 startNoLaterThan:2026-11-05 或 ISO8601 完整形式）",
            "invalid constraint: \(raw) (format type:date, e.g. startNoLaterThan:2026-11-05 or full ISO8601)"
        )
    }

    func invalidConstraintType(_ raw: String) -> String {
        let kinds = "startNoEarlierThan/startNoLaterThan/endNoEarlierThan/endNoLaterThan"
        return t(
            "无效时限类型：\(raw)（可选 \(kinds)）",
            "invalid constraint type: \(raw) (expected \(kinds))"
        )
    }

    func invalidResourceKind(_ raw: String) -> String {
        t(
            "无效资源类型：\(raw)（可选 person/equipment/material/group）",
            "invalid resource kind: \(raw) (expected person/equipment/material/group)"
        )
    }

    func invalidAssignment(_ spec: String) -> String {
        t(
            "无效分配：\(spec)（格式 资源ID或前缀[:单位]）",
            "invalid assignment: \(spec) (format resourceID-or-prefix[:units])"
        )
    }

    func invalidAssignmentUnits(_ raw: String) -> String {
        t("无效分配单位：\(raw)（应为正数）", "invalid assignment units: \(raw) (must be positive)")
    }

    func invalidDependencySpec(_ spec: String) -> String {
        t(
            "无效相关性规格：\(spec)（格式 predecessorID[:type[:lag]]）",
            "invalid dependency: \(spec) (format predecessorID[:type[:lag]])"
        )
    }

    func invalidDependencyType(_ raw: String) -> String {
        t("无效相关性类型：\(raw)（可选 fs/ff/ss/sf）", "invalid dependency type: \(raw) (expected fs/ff/ss/sf)")
    }

    // MARK: - 标识解析（任务 / 资源前缀）

    func taskIDPrefixTooShort(_ raw: String) -> String {
        t("任务 ID 前缀至少 4 位：\(raw)", "task ID prefix must be at least 4 characters: \(raw)")
    }

    func taskNotFound(_ raw: String) -> String {
        t("找不到任务：\(raw)", "task not found: \(raw)")
    }

    func taskIDPrefixAmbiguous(_ raw: String, matches: Int) -> String {
        t(
            "任务 ID 前缀不唯一（\(matches) 个匹配）：\(raw)",
            "task ID prefix is ambiguous (\(matches) matches): \(raw)"
        )
    }

    func resourceIDPrefixTooShort(_ raw: String) -> String {
        t("资源 ID 前缀至少 4 位：\(raw)", "resource ID prefix must be at least 4 characters: \(raw)")
    }

    func resourceNotFound(_ raw: String) -> String {
        t("找不到资源：\(raw)", "resource not found: \(raw)")
    }

    func resourceIDPrefixAmbiguous(_ raw: String, matches: Int) -> String {
        t(
            "资源 ID 前缀不唯一（\(matches) 个匹配）：\(raw)",
            "resource ID prefix is ambiguous (\(matches) matches): \(raw)"
        )
    }

    // MARK: - 输入文件解析失败（CLI 自己读的用户文件）

    func unparseableWBS(_ path: String) -> String {
        t("无法解析 WBS JSON：\(path)", "cannot parse WBS JSON: \(path)")
    }

    func unparseableBatch(_ path: String) -> String {
        t("无法解析批量回写 JSON：\(path)", "cannot parse batch update JSON: \(path)")
    }

    func batchFailures(_ count: Int) -> String {
        t("批量回写存在 \(count) 条失败", "batch update failed for \(count) entr\(count == 1 ? "y" : "ies")")
    }

    // MARK: - project

    func projectCreated(id: String, title: String) -> String {
        t("已创建项目：\(id)「\(title)」", "project created: \(id) \"\(title)\"")
    }

    func saved(path: String) -> String {
        t("已保存：\(path)", "saved: \(path)")
    }

    func updatedAt(_ timestamp: String) -> String {
        t("更新于：\(timestamp)", "updated at: \(timestamp)")
    }

    func projectLine(_ title: String) -> String {
        t("项目：\(title)", "project: \(title)")
    }

    func projectIDLine(_ id: String) -> String {
        t("项目ID：\(id)", "project id: \(id)")
    }

    func taskCountLine(_ count: Int) -> String {
        t("任务数：\(count)", "tasks: \(count)")
    }

    /// 保存/新建的格式版本行（FR-KAIRO-FMT-6）。
    func formatVersionLine(written: Int, upgradedFrom: Int?) -> String {
        if let upgradedFrom, upgradedFrom < written {
            return t(
                "格式版本：v\(written)（已从 v\(upgradedFrom) 升级）",
                "format version: v\(written) (upgraded from v\(upgradedFrom))"
            )
        }
        return t("格式版本：v\(written)", "format version: v\(written)")
    }

    /// 打开时的来源版本行。
    func sourceVersionLine(source: Int, current: Int) -> String {
        let line = t(
            "源格式版本：v\(source)（当前 v\(current)）",
            "source format version: v\(source) (current v\(current))"
        )
        return source < current ? line + t("，保存后升级", ", will upgrade on save") : line
    }

    // MARK: - task

    func taskCreated(id: String, title: String) -> String {
        t("已创建任务：\(id) \(title)", "task created: \(id) \(title)")
    }

    func taskUpdated(id: String, title: String) -> String {
        t("已更新任务：\(id) \(title)", "task updated: \(id) \(title)")
    }

    func taskDeleted(id: String) -> String {
        t("已删除任务：\(id)", "task deleted: \(id)")
    }

    func taskDeletedWithSubtasks(id: String, subtasks: Int) -> String {
        t(
            "已删除任务及其 \(subtasks) 个子任务：\(id)",
            "task deleted with \(subtasks) sub\(subtasks == 1 ? "task" : "tasks"): \(id)"
        )
    }

    // MARK: - wbs

    func importedTasks(_ total: Int) -> String {
        t("已导入 \(total) 个任务", "imported \(total) task\(total == 1 ? "" : "s")")
    }

    // MARK: - schedule

    func scheduleComputed(_ count: Int) -> String {
        t("已计算排期：\(count) 个任务", "schedule computed: \(count) task\(count == 1 ? "" : "s")")
    }

    func scheduleLine(
        id: String,
        title: String,
        start: String,
        finish: String,
        duration: String,
        policy: String
    ) -> String {
        // 英文单复数：duration 是格式化后的整/小数文本，仅 "1" 取单数。
        let unit = duration == "1" ? "day" : "days"
        return t(
            "  \(id) \(title)  \(start) → \(finish)（\(duration) 天，\(policy)）",
            "  \(id) \(title)  \(start) → \(finish) (\(duration) \(unit), \(policy))"
        )
    }

    func criticalPathHeader(count: Int, slackLimit: String) -> String {
        t(
            "重要路径：\(count) 个任务（宽延限制 \(slackLimit) 天）",
            "critical path: \(count) task\(count == 1 ? "" : "s") (slack limit \(slackLimit) days)"
        )
    }

    func criticalPathLine(
        id: String,
        title: String,
        mark: String,
        totalSlack: String,
        freeSlack: String
    ) -> String {
        t(
            "  \(id) \(title)\(mark)  总宽延 \(totalSlack) 天 / 自由宽延 \(freeSlack) 天",
            "  \(id) \(title)\(mark)  total slack \(totalSlack) days / free slack \(freeSlack) days"
        )
    }

    // MARK: - violations

    var noViolations: String { t("无违例", "no violations") }

    func violationCount(_ count: Int) -> String {
        t("违例：\(count) 条", "violations: \(count)")
    }

    func violationLine(severity: String, code: String, text: String) -> String {
        t("  [\(severity)] \(code)：\(text)", "  [\(severity)] \(code): \(text)")
    }

    /// 严重级别标签（违例行首）。
    func severityLabel(_ severity: Violation.Severity) -> String {
        switch severity {
        case .error: return t("错误", "error")
        case .warning: return t("警告", "warning")
        }
    }

    /// 违例文案：由 \`ViolationReason\` 的语义与参数渲染，核心层不再携带自然语言。
    ///
    /// \`zh-Hans\` 列逐字等于 v0.8.5 的 \`ViolationEngine\` 消息模板；
    /// \`startAfterProjectWindow\`（F-0715 / D-022）是本版新增归因，v0.8.5 无对应文案，
    /// 中文按「点明用户输入致因」的要求新写。
    func violationText(_ violation: Violation) -> String {
        switch violation.reason {
        case .cycle(let title):
            return t(
                "任务「\(taskTitle(title))」处于相关性环中，无法确定先后顺序",
                "task \"\(taskTitle(title))\" is in a dependency cycle; its order cannot be determined"
            )
        case .taskAfterProjectEnd(let title):
            return t(
                "任务「\(taskTitle(title))」的结束日期晚于项目结束日期",
                "task \"\(taskTitle(title))\" finishes after the project end date"
            )
        case .taskBeforeProjectStart(let title):
            return t(
                "任务「\(taskTitle(title))」的开始日期早于项目开始日期",
                "task \"\(taskTitle(title))\" starts before the project start date"
            )
        case .constraintWindowTooNarrow(let title, let windowDays, let requiredDays):
            return t(
                "任务「\(taskTitle(title))」的开始时限与结束时限相距过近（\(windowDays) 天），"
                    + "无法容纳持续时间（\(requiredDays) 天）",
                "task \"\(taskTitle(title))\" has start and end constraints only \(windowDays) day(s) apart, "
                    + "which cannot fit its \(requiredDays) day duration"
            )
        case .negativeSlack(let title):
            return t(
                "任务「\(taskTitle(title))」无法安排：最晚开始早于最早开始（负宽延）",
                "task \"\(taskTitle(title))\" cannot be scheduled: latest start precedes earliest start (negative slack)"
            )
        case .constraintConflict(let title, let kind, let conflict):
            let relation = conflict == .latestBeforeConstraint
                ? t("最晚\(side(kind))早于时限", "latest \(side(kind)) is earlier than the constraint")
                : t("窗口无法容纳任务持续时间", "the window cannot fit the task duration")
            return t(
                "任务「\(taskTitle(title))」的「\(constraintName(kind))」时限与相关性链冲突：\(relation)",
                "task \"\(taskTitle(title))\" \"\(constraintName(kind))\" constraint conflicts with the dependency "
                    + "chain: \(relation)"
            )
        case .constraintUnmetByPrerequisite(let title, let kind):
            return t(
                "任务「\(taskTitle(title))」因先决条件无法满足「\(constraintName(kind))」时限",
                "task \"\(taskTitle(title))\" cannot satisfy its \"\(constraintName(kind))\" constraint because of "
                    + "predecessors"
            )
        case .startAfterProjectWindow(let title, let taskStart, let projectStart, let projectEnd):
            let start = Self.calendarDay(taskStart)
            let windowStart = Self.calendarDay(projectStart)
            let windowEnd = Self.calendarDay(projectEnd)
            return t(
                "任务「\(taskTitle(title))」的开始日期（\(start)）晚于项目可排窗口"
                    + "（项目：\(windowStart) 至 \(windowEnd)）",
                "task \"\(taskTitle(title))\" starts on \(start), outside the schedulable project window "
                    + "(\(windowStart) to \(windowEnd))"
            )
        }
    }

    /// 任务标题缺失时的回退（任务已被删除等）。
    var unknownTask: String { t("未知任务", "unknown task") }

    private func taskTitle(_ title: String?) -> String {
        title ?? unknownTask
    }

    /// 时限方向的中文名（v0.8.5 文案用「开始不早于」这类整词）。
    private func constraintName(_ kind: ConstraintKind) -> String {
        switch kind {
        case .startNoEarlierThan: return t("开始不早于", "start no earlier than")
        case .startNoLaterThan: return t("开始不晚于", "start no later than")
        case .endNoEarlierThan: return t("结束不早于", "end no earlier than")
        case .endNoLaterThan: return t("结束不晚于", "end no later than")
        }
    }

    /// 「最晚开始 / 最晚结束」里的名词。
    private func side(_ kind: ConstraintKind) -> String {
        switch kind {
        case .startNoEarlierThan, .startNoLaterThan: return t("开始", "start")
        case .endNoEarlierThan, .endNoLaterThan: return t("结束", "finish")
        }
    }

    /// 日历日文本（\`yyyy-MM-dd\`）：契约格式，不随语言变化（\`en_US_POSIX\`）。
    static func calendarDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    // MARK: - status（单条 / 批量）

    func statusWritten(id: String, title: String, status: String, progress: Int) -> String {
        t(
            "已回写：\(id) \(title)（\(status)，进度 \(progress)%）",
            "status written: \(id) \(title) (\(status), progress \(progress)%)"
        )
    }

    func completedAt(_ timestamp: String) -> String {
        t("完成于：\(timestamp)", "completed at: \(timestamp)")
    }

    func groupProgress(_ percent: Int) -> String {
        t("完成度聚合：\(percent)%", "group progress: \(percent)%")
    }

    func batchEntryFailed(label: String, reason: String) -> String {
        t("失败：\(label) \(reason)", "failed: \(label) \(reason)")
    }

    var unknownError: String { t("未知错误", "unknown error") }

    func batchSummary(succeeded: Int, failed: Int) -> String {
        t(
            "批量结果：成功 \(succeeded) 条，失败 \(failed) 条",
            "batch result: \(succeeded) succeeded, \(failed) failed"
        )
    }

    // MARK: - resource

    func resourceAdded(id: String, name: String, kind: String, units: String, efficiency: String) -> String {
        t(
            "已添加资源：\(id) \(name)（\(kind)，单位 \(units)，效率 \(efficiency)）",
            "resource added: \(id) \(name) (\(kind), units \(units), efficiency \(efficiency))"
        )
    }

    func resourceLine(id: String, name: String, kind: String, units: String, efficiency: String) -> String {
        t(
            "\(id) \(name)（\(kind)，单位 \(units)，效率 \(efficiency)）",
            "\(id) \(name) (\(kind), units \(units), efficiency \(efficiency))"
        )
    }

    // MARK: - task list / detail

    func taskListLine(
        id: String,
        title: String,
        kind: String?,
        status: String,
        priority: String?,
        effort: String?,
        duration: String?,
        tags: [String]
    ) -> String {
        var parts: [String] = [id, title]
        if let kind { parts.append("[\(kind)]") }
        var extras: [String] = [status]
        if let priority { extras.append(priority) }
        if let effort { extras.append(t("投入 \(effort) 小时", "effort \(effort) h")) }
        if let duration {
            extras.append(t("持续 \(duration) 天", "duration \(duration) \(duration == "1" ? "day" : "days")"))
        }
        if !tags.isEmpty { extras.append(tags.map { "#\($0)" }.joined(separator: " ")) }
        parts.append(extras.joined(separator: " · "))
        return parts.joined(separator: " ")
    }

    var detailTask: String { t("任务：", "task: ") }
    var detailID: String { t("ID：", "id: ") }
    var detailKind: String { t("类型：", "kind: ") }
    var detailStatus: String { t("状态：", "status: ") }
    var detailAssignee: String { t("负责人：", "assignee: ") }
    var detailPriority: String { t("优先级：", "priority: ") }
    var detailEffort: String { t("投入：", "effort: ") }
    var detailDuration: String { t("持续：", "duration: ") }
    var detailTags: String { t("标签：", "tags: ") }
    var detailProgress: String { t("进度：", "progress: ") }
    var detailDependencies: String { t("相关性：", "dependencies: ") }
    var detailAssignments: String { t("分配：", "assignments: ") }
    var detailNotes: String { t("备注：", "notes: ") }

    func hoursUnit(_ effort: String) -> String { t("\(effort) 小时", "\(effort) h") }
    func daysUnit(_ days: String) -> String { t("\(days) 天", "\(days) \(days == "1" ? "day" : "days")") }
    func lagSuffix(_ lag: String) -> String { t(" 前导 \(lag) 天", " lag \(lag) days") }

    func dependencyRow(title: String, type: String, lag: String?) -> String {
        var text = "  - \(title)（\(type)）"
        if language == .en { text = "  - \(title) (\(type))" }
        if let lag { text += lagSuffix(lag) }
        return text
    }

    func assignmentRow(name: String, units: String) -> String {
        t("  - \(name)（\(units) 单位）", "  - \(name) (\(units) units)")
    }

    var unknownResource: String { t("未知资源", "unknown resource") }

    // MARK: - 领域枚举标签

    func kindLabel(_ kind: TaskKind) -> String {
        switch kind {
        case .task: return t("任务", "task")
        case .group: return t("群组", "group")
        case .milestone: return t("里程碑", "milestone")
        }
    }

    func statusLabel(_ status: TaskStatus) -> String {
        switch status {
        case .pending: return t("待办", "pending")
        case .inProgress: return t("进行中", "in progress")
        case .done: return t("已完成", "done")
        case .blocked: return t("阻塞", "blocked")
        }
    }

    func priorityLabel(_ priority: TaskPriority) -> String {
        switch priority {
        case .low: return t("低", "low")
        case .normal: return t("普通", "normal")
        case .high: return t("高", "high")
        case .critical: return t("紧急", "critical")
        }
    }

    func resourceKindLabel(_ kind: ResourceKind) -> String {
        switch kind {
        case .person: return t("人员", "person")
        case .equipment: return t("设备", "equipment")
        case .material: return t("素材", "material")
        case .group: return t("群组", "group")
        }
    }
}
