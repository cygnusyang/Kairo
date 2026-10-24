import Foundation
import KairoCore

/// 命令层统一错误（接口层结构化错误契约；MCP 工具与 CLI 共用）。
///
/// 两层码（F-0703）：
/// - code：冻结的粗粒度分类（5 值），CLI 退出码与既有 MCP 消费者的匹配依据，不改值；
/// - reason：细粒度稳定码（KairoErrorCode），取代「按 message 文本匹配」的脆弱用法。
///
/// message 仍保留：阶段一 CLI 的人类输出逐字等于 v0.8.5，MCP 的错误 message 也保持中文；
/// 核心层与视图层一律不读它（读 code / reason 后自行渲染）。
public struct SessionError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Code: String, Equatable, Sendable {
        case projectNotOpen = "project_not_open"
        case taskNotFound = "task_not_found"
        case invalidArgument = "invalid_argument"
        case fileUnreadable = "file_unreadable"
        case unsupportedFormat = "unsupported_format"
    }

    public var code: Code
    /// 细粒度稳定错误码（接口层输出；与语言无关）。
    public var reason: KairoErrorCode
    /// 人类可读说明（阶段一中文原样；核心/视图不读）。
    public var message: String
    public var taskID: UUID?

    public init(
        code: Code,
        reason: KairoErrorCode,
        message: String,
        taskID: UUID? = nil
    ) {
        self.code = code
        self.reason = reason
        self.message = message
        self.taskID = taskID
    }

    public var description: String { message }
}

/// 载入期的规范化警告（F-0703）：只带码与参数，中文 / 英文由调用方渲染。
///
/// 典型场景：旧数据里「有子项但 kind 不是 group」的任务在载入时被提升为群组，
/// 用户需要知道项目被改动过。
public struct LoadWarning: Codable, Hashable, Sendable {
    public var code: KairoErrorCode
    public var taskID: UUID?
    public var taskTitle: String?

    public init(code: KairoErrorCode, taskID: UUID? = nil, taskTitle: String? = nil) {
        self.code = code
        self.taskID = taskID
        self.taskTitle = taskTitle
    }
}

/// 可选字段补丁（ADR-013）：区分「不修改」「设为值」「清空」。
public enum FieldPatch<T: Sendable>: Sendable {
    case unchanged
    case set(T)
    case clear
}

/// 任务字段补丁（ADR-013）：`updateTask(id:patch:)` 使用；可选字段支持清空。
public struct TaskPatch: Sendable {
    public var title: String?
    public var notes: String?
    public var priority: TaskPriority?
    public var status: TaskStatus?
    public var progress: Double?
    public var tags: [String]?
    public var kind: TaskKind?
    public var schedulingPolicy: SchedulingPolicy?
    public var dependencies: [TaskDependency]?
    public var assignments: [TaskAssignment]?
    public var startDate: FieldPatch<Date> = .unchanged
    public var dueDate: FieldPatch<Date> = .unchanged
    public var assignee: FieldPatch<String> = .unchanged
    public var parentID: FieldPatch<UUID> = .unchanged
    public var effortHours: FieldPatch<Double> = .unchanged
    public var durationDays: FieldPatch<Double> = .unchanged
    public var constraint: FieldPatch<SchedulingConstraint> = .unchanged

    public init() {}
}

/// MCP 与 CLI 共享的命令实现层（ADR-005 契约同源）。
/// 持有当前项目与会话状态；project / task / wbs 操作全部经由此处，
/// 两个接口层只做参数路由与输出呈现。
public final class KairoSession {
    public private(set) var project: Project?
    public private(set) var projectURL: URL?
    /// 是否存在未保存修改（ADR-013 / 外部更新检测）。
    public private(set) var hasUnsavedChanges = false
    /// 写操作版本号：每次变更递增，供异步加载判断期间是否有新编辑。
    public private(set) var revision: UInt64 = 0
    /// 当前项目来源文件的格式版本；新建项目或尚未打开文件时为 nil。
    public private(set) var sourceFormatVersion: Int?

    /// 来源文件早于当前格式，保存后即完成升级（FR-KAIRO-FMT）。
    public var needsFormatUpgrade: Bool {
        sourceFormatVersion.map { $0 < KairoFile.currentFormatVersion } ?? false
    }

    public init() {}

    // MARK: - 缓存与脏标记

    /// 任一写操作后置脏；读取排期时按需重算一次。
    private func markChanged() {
        lastSchedule = nil
        hasUnsavedChanges = true
        revision &+= 1
    }

    private func markSaved() {
        hasUnsavedChanges = false
    }

    // MARK: - 项目

    /// 新建项目（US-E1-01）：返回项目元数据，含项目 ID。
    @discardableResult
    public func createProject(
        title: String,
        projectStart: Date? = nil,
        projectEnd: Date? = nil
    ) throws -> ProjectMetadata {
        let project = Project()
        project.metadata.title = title
        project.metadata.projectStart = projectStart
        project.metadata.projectEnd = projectEnd
        project.metadata.updatedAt = Date()
        self.project = project
        projectURL = nil
        sourceFormatVersion = nil
        markChanged()
        markSaved()
        return project.metadata
    }

    /// 打开 .kairo 项目文件。
    @discardableResult
    public func openProject(at url: URL) throws -> ProjectMetadata {
        let decoded: DecodedProject
        do {
            // 保留来源版本：迁移在读取时完成，但磁盘仍可能是旧格式直至保存。
            decoded = try KairoFile.read(from: url)
        } catch let error as KairoFileError {
            // 粗码 code 保持 v0.8.5 口径（决定 CLI 退出码与 MCP 分类）；
            // 细码 reason 四例透传，取代「按 message 文本猜是哪一种格式问题」。
            let code: SessionError.Code
            let reason: KairoErrorCode
            switch error {
            case .unsupportedFormatVersion:
                code = .unsupportedFormat
                reason = .unsupportedFormat
            case .noMigrationPath:
                code = .unsupportedFormat
                reason = .noMigrationPath
            case .migrationFailed:
                code = .unsupportedFormat
                reason = .migrationFailed
            case .malformedFormatVersion:
                code = .fileUnreadable
                reason = .malformedFormatVersion
            }
            throw SessionError(code: code, reason: reason, message: error.description)
        } catch {
            throw SessionError(
                code: .fileUnreadable,
                reason: .fileUnreadable,
                message: "无法读取项目文件：\(url.lastPathComponent)"
            )
        }
        adoptProject(
            decoded.project, from: url, formatVersion: decoded.sourceFormatVersion
        )
        return decoded.project.metadata
    }

    /// 接管已在后台解码的项目（应用层异步打开，避免主线程阻塞）。
    ///
    /// - Parameter formatVersion: 来源文件的格式版本。生产路径的取值为
    ///   `1...KairoFile.currentFormatVersion`（读取时已校验）；测试接缝可传 0
    ///   模拟早于首个可迁移版本的来源。默认值仅用于接管已是当前版本的项目；
    ///   打开旧版文件时必须显式传入 `DecodedProject.sourceFormatVersion`。
    public func adoptProject(
        _ project: Project,
        from url: URL,
        formatVersion: Int = KairoFile.currentFormatVersion
    ) {
        normalizeGroupKinds(in: project)
        self.project = project
        projectURL = url
        sourceFormatVersion = formatVersion
        markChanged()
        markSaved()
    }

    /// 文件导出器已把快照写入磁盘：回填路径并清除脏标记，避免重复写文件。
    /// 导出内容始终是当前格式，因此来源版本同步为当前版本。
    public func noteExported(to url: URL) {
        projectURL = url
        sourceFormatVersion = KairoFile.currentFormatVersion
        markSaved()
    }

    /// 加载规范化警告（如「有子项的任务已按群组处理」）：只带码与参数，文案由调用方渲染。
    public private(set) var loadWarnings: [LoadWarning] = []

    /// 更新项目元数据；开始/结束日期可显式清空。
    @discardableResult
    public func updateProjectMetadata(
        title: String? = nil,
        projectStart: FieldPatch<Date> = .unchanged,
        projectEnd: FieldPatch<Date> = .unchanged,
        direction: ScheduleDirection? = nil
    ) throws -> ProjectMetadata {
        guard let project else { throw notOpen() }
        if let title { project.metadata.title = title }
        if let direction { project.metadata.direction = direction }
        Self.apply(projectStart, to: &project.metadata.projectStart)
        Self.apply(projectEnd, to: &project.metadata.projectEnd)
        project.metadata.updatedAt = Date()
        markChanged()
        return project.metadata
    }

    /// 当前项目值快照（撤销栈与呈现层输入）。
    public func snapshot() throws -> ProjectState {
        guard let project else { throw notOpen() }
        return ProjectState(project: project)
    }

    /// 用快照恢复项目（撤销/重做）。
    public func restore(_ state: ProjectState) throws {
        guard let project else { throw notOpen() }
        state.apply(to: project)
        project.metadata.updatedAt = Date()
        markChanged()
    }

    /// 任务首次获得子项时提升为群组，保证「有子项 ⇒ kind == .group」始终成立。
    private func promoteToGroupIfNeeded(_ parentID: UUID?, in project: Project) {
        guard let parentID,
              let index = project.tasks.firstIndex(where: { $0.id == parentID }),
              project.tasks[index].kind != .group else { return }
        project.tasks[index].kind = .group
    }

    /// 群组唯一判据为 `kind == .group`；有子项但类型不符的旧数据在加载时规范化。
    private func normalizeGroupKinds(in project: Project) {
        let parentIDs = Set(project.tasks.compactMap(\.parentID))
        var warnings: [LoadWarning] = []
        for (index, task) in project.tasks.enumerated()
        where parentIDs.contains(task.id) && task.kind != .group {
            project.tasks[index].kind = .group
            warnings.append(LoadWarning(
                code: .groupPromoted,
                taskID: task.id,
                taskTitle: task.title
            ))
        }
        loadWarnings = warnings
    }

    /// 保存项目；未指定路径时使用已打开项目的路径。
    @discardableResult
    public func saveProject(to url: URL? = nil) throws -> ProjectMetadata {
        guard let project else { throw notOpen() }
        let target = url ?? projectURL
        guard let target else {
            throw SessionError(
                code: .invalidArgument,
                reason: .noSavePath,
                message: "未指定保存路径（请提供 --path 或先打开项目）"
            )
        }
        project.metadata.updatedAt = Date()
        do {
            try KairoFile.save(project, to: target)
        } catch {
            throw SessionError(
                code: .fileUnreadable,
                reason: .writeFailed,
                message: "保存失败：\(error.localizedDescription)"
            )
        }
        projectURL = target
        sourceFormatVersion = KairoFile.currentFormatVersion
        markSaved()
        return project.metadata
    }

    // MARK: - 任务 CRUD

    @discardableResult
    public func addTask(
        title: String,
        kind: TaskKind = .task,
        parentID: UUID? = nil,
        effortHours: Double? = nil,
        durationDays: Double? = nil,
        notes: String = "",
        priority: TaskPriority = .normal,
        status: TaskStatus = .pending,
        tags: [String] = [],
        dependencies: [TaskDependency] = [],
        constraint: SchedulingConstraint? = nil,
        schedulingPolicy: SchedulingPolicy = .asap,
        assignments: [TaskAssignment] = [],
        startDate: Date? = nil,
        dueDate: Date? = nil,
        assignee: String? = nil
    ) throws -> UUID {
        guard let project else { throw notOpen() }
        if let parentID, project.tasksByID[parentID] == nil {
            throw SessionError(code: .invalidArgument, reason: .parentNotFound, message: "父任务不存在", taskID: parentID)
        }
        promoteToGroupIfNeeded(parentID, in: project)
        try validate(assignments: assignments, in: project)
        let task = TaskItem(
            title: title,
            notes: notes,
            startDate: startDate,
            dueDate: dueDate,
            priority: priority,
            status: status,
            tags: tags,
            assignee: Self.normalizedAssignee(assignee),
            kind: kind,
            parentID: parentID,
            effortHours: effortHours,
            durationDays: durationDays,
            dependencies: dependencies,
            constraint: constraint,
            schedulingPolicy: schedulingPolicy,
            assignments: assignments
        )
        project.add(task)
        markChanged()
        return task.id
    }

    public func listTasks(parentID: UUID? = nil, filter: String = "") throws -> [TaskItem] {
        guard let project else { throw notOpen() }
        var tasks = project.tasks
        if let parentID {
            tasks = tasks.filter { $0.parentID == parentID }
        }
        if !filter.isEmpty {
            tasks = AIFilterTranslator.apply(clauses: AIFilterTranslator.translate(filter), to: tasks)
        }
        return tasks
    }

    public func getTask(id: UUID) throws -> TaskItem {
        guard let project else { throw notOpen() }
        guard let task = project.tasksByID[id] else {
            throw SessionError(code: .taskNotFound, reason: .taskNotFound, message: "任务不存在", taskID: id)
        }
        return task
    }

    @discardableResult
    public func updateTask(
        id: UUID,
        title: String? = nil,
        kind: TaskKind? = nil,
        parentID: UUID? = nil,
        effortHours: Double? = nil,
        durationDays: Double? = nil,
        notes: String? = nil,
        priority: TaskPriority? = nil,
        status: TaskStatus? = nil,
        progress: Double? = nil,
        tags: [String]? = nil,
        dependencies: [TaskDependency]? = nil,
        constraint: SchedulingConstraint? = nil,
        schedulingPolicy: SchedulingPolicy? = nil,
        assignments: [TaskAssignment]? = nil,
        assignee: String? = nil
    ) throws -> TaskItem {
        guard let project else { throw notOpen() }
        guard let index = project.tasks.firstIndex(where: { $0.id == id }) else {
            throw SessionError(code: .taskNotFound, reason: .taskNotFound, message: "任务不存在", taskID: id)
        }
        if let assignments { try validate(assignments: assignments, in: project) }
        var task = project.tasks[index]
        if let title { task.title = title }
        if let kind {
            task.kind = kind
            try validateKind(of: task, id: id, in: project)
        }
        if let parentID {
            task.parentID = parentID
            try validateParent(of: task, id: id, in: project)
        }
        if let effortHours { task.effortHours = effortHours }
        if let durationDays { task.durationDays = durationDays }
        if let notes { task.notes = notes }
        if let priority { task.priority = priority }
        if let status { task.status = status }
        if let progress { task.progress = min(max(progress, 0), 1) }
        if let tags { task.tags = tags }
        if let dependencies { task.dependencies = dependencies }
        if let constraint { task.constraint = constraint }
        if let schedulingPolicy { task.schedulingPolicy = schedulingPolicy }
        if let assignments { task.assignments = assignments }
        // 负责人字段（US-E1-02）：nil = 不改；非 nil 空串/纯空白 = 清空（D-004 trim）。
        if let assignee { task.assignee = Self.normalizedAssignee(assignee) }
        project.tasks[index] = task
        if let parentID { promoteToGroupIfNeeded(parentID, in: project) }
        markChanged()
        return task
    }

    /// 补丁式字段更新（ADR-013）：可选字段可显式清空；状态与进度走统一回写入口。
    @discardableResult
    public func updateTask(id: UUID, patch: TaskPatch) throws -> TaskItem {
        guard let project else { throw notOpen() }
        guard let index = project.tasks.firstIndex(where: { $0.id == id }) else {
            throw SessionError(code: .taskNotFound, reason: .taskNotFound, message: "任务不存在", taskID: id)
        }
        if let assignments = patch.assignments { try validate(assignments: assignments, in: project) }
        if let progress = patch.progress, !(0...1).contains(progress) {
            throw SessionError(code: .invalidArgument, reason: .progressOutOfRange, message: "进度必须介于 0 与 1 之间", taskID: id)
        }
        var task = project.tasks[index]
        if let title = patch.title { task.title = title }
        if let notes = patch.notes { task.notes = notes }
        if let priority = patch.priority { task.priority = priority }
        if let tags = patch.tags { task.tags = tags }
        if let kind = patch.kind {
            task.kind = kind
            try validateKind(of: task, id: id, in: project)
        }
        if let schedulingPolicy = patch.schedulingPolicy { task.schedulingPolicy = schedulingPolicy }
        if let dependencies = patch.dependencies { task.dependencies = dependencies }
        if let assignments = patch.assignments { task.assignments = assignments }
        Self.apply(patch.startDate, to: &task.startDate)
        Self.apply(patch.dueDate, to: &task.dueDate)
        switch patch.assignee {
        case .unchanged: break
        case .set(let name): task.assignee = Self.normalizedAssignee(name)
        case .clear: task.assignee = nil
        }
        Self.apply(patch.parentID, to: &task.parentID)
        Self.apply(patch.effortHours, to: &task.effortHours)
        Self.apply(patch.durationDays, to: &task.durationDays)
        Self.apply(patch.constraint, to: &task.constraint)
        Self.applyStatus(status: patch.status, progress: patch.progress, to: &task)
        // 仅父级实际变更时校验与提升，避免逐键更新做全量子树遍历。
        if case .set = patch.parentID {
            try validateParent(of: task, id: id, in: project)
        }
        project.tasks[index] = task
        if case .set = patch.parentID {
            promoteToGroupIfNeeded(task.parentID, in: project)
        }
        markChanged()
        return task
    }

    /// 父任务引用必须存在且不能指向自身；父级首次获得子项时提升为群组。
    private func validateParent(of task: TaskItem, id: UUID, in project: Project) throws {
        guard let parentID = task.parentID else { return }
        guard parentID != id else {
            throw SessionError(
                code: .invalidArgument,
                reason: .parentNotFound,
                message: "父任务不能是任务自身",
                taskID: id
            )
        }
        guard project.tasksByID[parentID] != nil else {
            throw SessionError(code: .invalidArgument, reason: .parentNotFound, message: "父任务不存在", taskID: parentID)
        }
        guard !OutlineEditor.subtreeIDs(of: id, in: project.tasks).contains(parentID) else {
            throw SessionError(
                code: .invalidArgument,
                reason: .moveIntoSubtree,
                message: "不能把任务移动到自身或后代之下",
                taskID: id
            )
        }
    }

    /// 有子项的任务必须是群组；拒绝经由 CLI/MCP 显式降级类型。
    private func validateKind(of task: TaskItem, id: UUID, in project: Project) throws {
        guard task.kind != .group,
              project.tasks.contains(where: { $0.parentID == id }) else { return }
        throw SessionError(
            code: .invalidArgument,
            reason: .parentNotFound,
            message: "任务存在子项，不能改为非群组类型",
            taskID: id
        )
    }

    private static func apply<V>(_ patch: FieldPatch<V>, to value: inout V?) {
        switch patch {
        case .unchanged: break
        case .set(let newValue): value = newValue
        case .clear: value = nil
        }
    }

    /// D-004：负责人输入集中归一——trim 首尾空白；纯空白视为清空（nil）。
    /// addTask / 旧式 updateTask / 补丁 updateTask 三个写路径共用。
    private static func normalizedAssignee(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 校验分配引用的资源存在（US-E1-05）；悬空引用在写入前拒绝。
    private func validate(assignments: [TaskAssignment], in project: Project) throws {
        let resourceIDs = Set(project.resources.map(\.id))
        for assignment in assignments where !resourceIDs.contains(assignment.resourceID) {
            throw SessionError(
                code: .invalidArgument,
                reason: .resourceNotFound,
                message: "资源不存在",
                taskID: assignment.resourceID
            )
        }
    }

    /// 删除任务；存在后代时一并删除，避免 MCP/CLI 绕过界面确认后留下悬空 parentID。
    @discardableResult
    public func deleteTask(id: UUID) throws -> Bool {
        _ = try deleteSubtree(id: id)
        return true
    }

    /// 级联删除任务及其全部后代，返回受影响任务数；同时清理悬空依赖。
    @discardableResult
    public func deleteTaskCascade(id: UUID) throws -> Int {
        try deleteSubtree(id: id)
    }

    private func deleteSubtree(id: UUID) throws -> Int {
        guard let project else { throw notOpen() }
        guard project.tasksByID[id] != nil else {
            throw SessionError(code: .taskNotFound, reason: .taskNotFound, message: "任务不存在", taskID: id)
        }
        let removed = OutlineEditor.subtreeIDs(of: id, in: project.tasks)
        let remaining = project.tasks.filter { !removed.contains($0.id) }
        // 指向被删任务的相关性一并移除（US-E1-02 验收）。
        project.replaceTasks(
            DependencyEditing.removingDanglingReferences(to: removed, in: remaining)
        )
        markChanged()
        return removed.count
    }

    // MARK: - 大纲移动（F-14-02 / ADR-013）

    /// Tab 缩进；无上一同级任务时返回 nil。
    @discardableResult
    public func indentTask(id: UUID) throws -> [TaskItem]? {
        guard let project else { throw notOpen() }
        guard let updated = OutlineEditor.indent(id, in: project.tasks) else { return nil }
        project.replaceTasks(updated)
        promoteToGroupIfNeeded(project.tasksByID[id]?.parentID, in: project)
        markChanged()
        return updated
    }

    /// Shift-Tab 出缩进；已是顶层时返回 nil。
    @discardableResult
    public func outdentTask(id: UUID) throws -> [TaskItem]? {
        guard let project else { throw notOpen() }
        guard let updated = OutlineEditor.outdent(id, in: project.tasks) else { return nil }
        project.replaceTasks(updated)
        markChanged()
        return updated
    }

    /// 拖拽重排：移动到目标父级与索引；拒绝移入自身或后代。
    @discardableResult
    public func moveTask(id: UUID, toParent parentID: UUID?, at index: Int) throws -> [TaskItem] {
        guard let project else { throw notOpen() }
        switch OutlineMoving.move(id, toParent: parentID, at: index, in: project.tasks) {
        case .success(let updated):
            project.replaceTasks(updated)
            promoteToGroupIfNeeded(parentID, in: project)
            markChanged()
            return updated
        case .failure(let error):
            let message: String
            let reason: KairoErrorCode
            switch error {
            case .taskNotFound:
                message = "任务不存在"
                reason = .taskNotFound
            case .targetNotFound:
                message = "目标父级不存在"
                reason = .parentNotFound
            case .moveIntoSubtree:
                message = "不能把任务移动到自身或后代之下"
                reason = .moveIntoSubtree
            }
            throw SessionError(code: .invalidArgument, reason: reason, message: message, taskID: id)
        }
    }

    // MARK: - 相关性编辑（F-30-08 / ADR-013）

    /// 添加或更新依赖（同前驱归一为一条）；成环被拒绝。
    @discardableResult
    public func addDependency(
        to taskID: UUID,
        predecessorID: UUID,
        type: TaskDependency.DependencyType = .fs,
        lagDays: Double = 0
    ) throws -> TaskItem {
        guard let project else { throw notOpen() }
        let dependency = TaskDependency(
            predecessorID: predecessorID, type: type, lagDays: lagDays
        )
        switch DependencyEditing.add(dependency, to: taskID, in: project.tasks) {
        case .success(let updated):
            project.replaceTasks(updated)
            markChanged()
            return project.tasksByID[taskID]!
        case .failure(let error):
            let message: String
            let reason: KairoErrorCode
            switch error {
            case .taskNotFound:
                message = "任务不存在"
                reason = .taskNotFound
            case .predecessorNotFound:
                message = "前驱任务不存在"
                reason = .dependencyPredecessorNotFound
            case .selfDependency:
                message = "任务不能依赖自身"
                reason = .dependencySelf
            case .cycle:
                message = "该依赖会形成相关性环"
                reason = .dependencyCycle
            }
            throw SessionError(code: .invalidArgument, reason: reason, message: message, taskID: taskID)
        }
    }

    /// 删除依赖；依赖不存在时原样返回。
    @discardableResult
    public func removeDependency(from taskID: UUID, predecessorID: UUID) throws -> TaskItem {
        guard let project else { throw notOpen() }
        switch DependencyEditing.remove(predecessorID: predecessorID, from: taskID, in: project.tasks) {
        case .success(let updated):
            project.replaceTasks(updated)
            markChanged()
            return project.tasksByID[taskID]!
        case .failure:
            throw SessionError(code: .taskNotFound, reason: .taskNotFound, message: "任务不存在", taskID: taskID)
        }
    }

    // MARK: - WBS 批量导入（US-E1-04）

    /// 把嵌套标题/kind/子节点树展开为 parentID 结构。
    @discardableResult
    public func importWBS(nodes: [WBSNode], parentID: UUID? = nil) throws -> WBSImportResult {
        guard let project else { throw notOpen() }
        if let parentID, project.tasksByID[parentID] == nil {
            throw SessionError(code: .invalidArgument, reason: .parentNotFound, message: "父任务不存在", taskID: parentID)
        }
        var rootIDs: [UUID] = []
        var idByTitle: [String: UUID] = [:]

        func walk(_ node: WBSNode, _ parent: UUID?) {
            let id = UUID()
            let kind = node.kind ?? (node.children.isEmpty ? .task : .group)
            var effort = node.effortHours
            var duration = node.durationDays
            // 里程碑：投入/持续时间恒为 0（US-E1-03）。
            if kind == .milestone {
                effort = 0
                duration = 0
            }
            // 显式传入 id：与 rootIDs / idByTitle 记录保持一致（否则返回的 ID 与任务实际 ID 不符）。
            let task = TaskItem(
                id: id,
                title: node.title,
                kind: kind,
                parentID: parent,
                effortHours: effort,
                durationDays: duration
            )
            project.add(task)
            if parent == nil { rootIDs.append(id) }
            idByTitle[node.title] = id
            for child in node.children { walk(child, id) }
        }
        for node in nodes { walk(node, parentID) }
        markChanged()

        return WBSImportResult(
            rootIDs: rootIDs,
            idByTitle: idByTitle,
            total: idByTitle.count,
            warnings: []
        )
    }

    // MARK: - 排期与违例查询（US-E2-02 / US-E2-03 / US-E2-05）

    /// 最近一次排期结果（schedule_compute 缓存；critical_path / violations 复用）。
    public private(set) var lastSchedule: ScheduleResult?

    /// 排期实际计算次数（测试观测缝：D-014 断言纯视图动作不触发重算）。
    public private(set) var scheduleComputeCount = 0

    /// 计算排期并缓存结果（ADR-007：经 KairoCore 纯函数，命令层不重复实现）。
    @discardableResult
    public func computeSchedule(projectStart: Date? = nil, projectEnd: Date? = nil) throws -> ScheduleResult {
        guard let project else { throw notOpen() }
        scheduleComputeCount += 1
        let result = ScheduleEngine.compute(
            tasks: project.tasks,
            resources: project.resources,
            projectStart: projectStart ?? project.metadata.projectStart,
            projectEnd: projectEnd ?? project.metadata.projectEnd,
            direction: project.metadata.direction
        )
        lastSchedule = result
        return result
    }

    /// 未排期时先计算一次（缓存复用）。
    /// 公开供呈现快照复用：写操作经 `markChanged` 置空缓存后才重算，
    /// 纯视图动作（如日宽调整）命中缓存不重算（D-014）。
    public func scheduleOrCompute() throws -> ScheduleResult {
        if let lastSchedule { return lastSchedule }
        return try computeSchedule()
    }

    /// 违例列表（US-E2-05）：未排期时先按当前项目计算。
    public func violations() throws -> [Violation] {
        guard let project else { throw notOpen() }
        let result = try scheduleOrCompute()
        return ViolationEngine.check(result: result, tasks: project.tasks)
    }

    /// 重要路径与宽延（US-E2-03 / F-21-01）：总宽延 ≤ slackLimit 的任务集。
    public func criticalPath(slackLimit: Double? = nil) throws -> [CriticalPathEntry] {
        let result = try scheduleOrCompute()
        return CriticalPathEngine.compute(result: result, slackLimit: slackLimit)
    }

    // MARK: - 状态回写（US-E3-01 / US-E3-02）

    /// 单任务状态/进度回写：状态置 done 时记录完成时间并把进度置 1；
    /// 进度超出 0...1 拒绝并返回参数错误（US-E3-01 验收）。
    @discardableResult
    public func statusUpdate(id: UUID, status: TaskStatus? = nil, progress: Double? = nil) throws -> TaskItem {
        guard let project else { throw notOpen() }
        guard let index = project.tasks.firstIndex(where: { $0.id == id }) else {
            throw SessionError(code: .taskNotFound, reason: .taskNotFound, message: "任务不存在", taskID: id)
        }
        if let progress, !(0...1).contains(progress) {
            throw SessionError(code: .invalidArgument, reason: .progressOutOfRange, message: "进度必须介于 0 与 1 之间", taskID: id)
        }
        var task = project.tasks[index]
        Self.applyStatus(status: status, progress: progress, to: &task)
        project.tasks[index] = task
        markChanged()
        return task
    }

    /// 统一状态回写入口：`done` → 进度 1 + 完成时间；离开 `done` 清空完成时间；
    /// 进度 100% → `done`（100% 与 done 双向联动）。
    private static func applyStatus(status: TaskStatus?, progress: Double?, to task: inout TaskItem) {
        if let status {
            task.status = status
            if status == .done {
                task.progress = 1
                if task.completedAt == nil { task.completedAt = Date() }
            } else {
                task.completedAt = nil
            }
        }
        if let progress, task.status != .done {
            task.progress = min(max(progress, 0), 1)
            if task.progress >= 1 {
                task.progress = 1
                task.status = .done
                if task.completedAt == nil { task.completedAt = Date() }
            }
        }
    }

    // MARK: - 批量回写（US-E3-02）

    /// 单条批量回写输入。
    public struct StatusUpdateInput: Sendable {
        public var taskID: UUID
        public var status: TaskStatus?
        public var progress: Double?

        public init(taskID: UUID, status: TaskStatus? = nil, progress: Double? = nil) {
            self.taskID = taskID
            self.status = status
            self.progress = progress
        }
    }

    /// 批量回写结果：逐条成功/失败明细，失败项不中断后续条目。
    public struct StatusBatchResult: Codable, Sendable {
        public struct Entry: Codable, Sendable {
            public var taskID: UUID
            public var ok: Bool
            public var task: TaskItem?
            public var error: String?

            public init(taskID: UUID, ok: Bool, task: TaskItem? = nil, error: String? = nil) {
                self.taskID = taskID
                self.ok = ok
                self.task = task
                self.error = error
            }
        }

        public var entries: [Entry]
        public var succeeded: Int
        public var failed: Int

        public init(entries: [Entry]) {
            self.entries = entries
            self.succeeded = entries.filter(\.ok).count
            self.failed = entries.count - succeeded
        }
    }

    /// 批量回写多个任务的状态/进度（US-E3-02）：按清单逐条更新，返回成功与失败明细。
    public func statusBatch(_ updates: [StatusUpdateInput]) throws -> StatusBatchResult {
        guard project != nil else { throw notOpen() }
        var entries: [StatusBatchResult.Entry] = []
        for update in updates {
            do {
                let task = try statusUpdate(
                    id: update.taskID,
                    status: update.status,
                    progress: update.progress
                )
                entries.append(.init(taskID: update.taskID, ok: true, task: task))
            } catch let error as SessionError {
                entries.append(.init(taskID: update.taskID, ok: false, error: error.message))
            } catch {
                entries.append(.init(taskID: update.taskID, ok: false, error: error.localizedDescription))
            }
        }
        return StatusBatchResult(entries: entries)
    }

    /// 群组完成度（US-E3-02 / F-20-03）：按投入加权聚合全部后代叶子任务；
    /// 群组容器自身不产生投入，无投入的叶子按权重 1 计；非群组（无后代）返回自身进度。
    public func groupProgress(id: UUID) throws -> Double {
        guard let project else { throw notOpen() }
        guard let task = project.tasksByID[id] else {
            throw SessionError(code: .taskNotFound, reason: .taskNotFound, message: "任务不存在", taskID: id)
        }
        let leaves = leafDescendants(of: id, in: project)
        guard !leaves.isEmpty else { return task.progress }
        let total = leaves.reduce(0.0) { $0 + ($1.effortHours ?? 1) }
        let done = leaves.reduce(0.0) { $0 + ($1.effortHours ?? 1) * $1.progress }
        guard total > 0 else { return task.progress }
        return done / total
    }

    /// 后代叶子任务：仍含子任务的群组容器被展开，只有叶子（无子任务）参与加权。
    private func leafDescendants(of id: UUID, in project: Project) -> [TaskItem] {
        var result: [TaskItem] = []
        for task in project.tasks where task.parentID == id {
            if project.tasks.contains(where: { $0.parentID == task.id }) {
                result.append(contentsOf: leafDescendants(of: task.id, in: project))
            } else {
                result.append(task)
            }
        }
        return result
    }

    // MARK: - 资源（F-23-01 / ADR-009）

    /// 新增资源（人员/设备/素材/群组）；单位与效率必须为正。
    @discardableResult
    public func resourceAdd(
        name: String,
        kind: ResourceKind = .person,
        units: Double = 1.0,
        efficiency: Double = 1.0
    ) throws -> UUID {
        guard let project else { throw notOpen() }
        if units <= 0 {
            throw SessionError(code: .invalidArgument, reason: .resourceUnitInvalid, message: "资源单位必须为正数")
        }
        if efficiency <= 0 {
            throw SessionError(code: .invalidArgument, reason: .resourceEfficiencyInvalid, message: "资源效率必须为正数")
        }
        let resource = Resource(name: name, kind: kind, units: units, efficiency: efficiency)
        project.resources.append(resource)
        markChanged()
        return resource.id
    }

    /// 列出项目资源。
    public func resourceList() throws -> [Resource] {
        guard let project else { throw notOpen() }
        return project.resources
    }

    // MARK: - 私有

    private func notOpen() -> SessionError {
        SessionError(
            code: .projectNotOpen,
            reason: .projectNotOpen,
            message: "未打开项目（请先 project open / project create）"
        )
    }
}
