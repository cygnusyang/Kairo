import Foundation
import KairoCore
import KairoCommands

/// 工具层错误：非法参数（架构 §3.1 错误契约的 argument 类）。
///
/// `reason` 是细粒度稳定码（`KairoErrorCode`）：对外的 `code` 仍冻结为
/// `invalid_argument`，消费者改按 `reason` 区分参数错误，不必再匹配中文文本（F-0708 阶段一）。
enum ToolError: Error, Equatable, CustomStringConvertible {
    case invalidArgument(reason: KairoErrorCode, message: String)

    /// 细粒度稳定码。
    var reason: KairoErrorCode {
        switch self {
        case .invalidArgument(let reason, _): return reason
        }
    }

    var description: String {
        switch self {
        case .invalidArgument(_, let message): return message
        }
    }
}

/// 结构化工具失败（架构 §3.1：{code, message, reason?, taskID?}）。
///
/// `code` 是冻结的粗粒度分类（5 值 + `internal_error`），不改取值——按它匹配的既有
/// 消费者不能静默失效；`reason` 是本版新增的细粒度稳定码。`message` 阶段一保持中文
/// 原样（设计 §6：先给码、下一个版本再切文案）。
struct ToolFailure: Encodable {
    var code: String
    var reason: String?
    var message: String
    var taskID: String?
}

/// MCP 工具定义：名称 / 描述 / 输入 schema / 处理函数。
struct MCPTool {
    let name: String
    let description: String
    let inputSchema: JSONValue
    let handler: (JSONValue?, KairoSession) throws -> JSONValue
}

/// 工具清单（Sprint 1 子集，与架构文档 §3.1 草案对齐）。
/// 接口事实源（ADR-005）：CLI 从同一命令层派生。
struct ToolRegistry {
    private(set) var tools: [MCPTool]

    init() {
        tools = Self.makeTools()
    }

    func find(_ name: String) -> MCPTool? {
        tools.first { $0.name == name }
    }

    // MARK: - 工具定义

    private static func makeTools() -> [MCPTool] {
        [
            projectCreate,
            projectOpen,
            projectSave,
            taskAdd,
            taskList,
            taskGet,
            taskUpdate,
            taskDelete,
            wbsImport,
            scheduleCompute,
            scheduleCriticalPath,
            violationsList,
            statusUpdate,
            statusBatchUpdate,
            resourceAdd,
            resourceList,
        ]
    }

    // MARK: project

    private static let projectCreate = MCPTool(
        name: "project_create",
        description: "新建项目并打开（US-E1-01）；可带项目时间线 projectStart/projectEnd（ISO8601），作为排期与违例的默认边界",
        inputSchema: Schema.object(properties: [
            "title": Schema.string(),
            "projectStart": Schema.string(),
            "projectEnd": Schema.string(),
        ], required: ["title"])
    ) { args, session in
        let a = try ToolArgs(args)
        let meta = try session.createProject(
            title: a.string("title"),
            projectStart: try a.optionalISODate("projectStart"),
            projectEnd: try a.optionalISODate("projectEnd")
        )
        return ProjectResults.created(meta)
    }

    private static let projectOpen = MCPTool(
        name: "project_open",
        description: "打开 .kairo 项目文件（US-E6-01）；formatVersion 为磁盘文件版本，needsUpgrade 表示保存后会升级",
        inputSchema: Schema.object(properties: ["path": Schema.string()], required: ["path"])
    ) { args, session in
        let a = try ToolArgs(args)
        let meta = try session.openProject(at: URL(fileURLWithPath: a.string("path")))
        return ProjectResults.opened(meta, sourceFormatVersion: session.sourceFormatVersion)
    }

    private static let projectSave = MCPTool(
        name: "project_save",
        description: "保存当前项目为 .kairo（未指定路径时保存到已打开文件）；formatVersion 为写出文件的版本",
        inputSchema: Schema.object(properties: ["path": Schema.string()])
    ) { args, session in
        let a = try ToolArgs(args)
        let target = a.optionalString("path").map { URL(fileURLWithPath: $0) }
        // 保存会把来源版本置为 current，必须先捕获；否则 upgradedFrom 永远丢失。
        let upgradedFrom = session.sourceFormatVersion
        let meta = try session.saveProject(to: target)
        return ProjectResults.saved(
            updatedAt: meta.updatedAt,
            path: session.projectURL?.path ?? "",
            upgradedFrom: upgradedFrom
        )
    }

    // MARK: task

    private static let taskAdd = MCPTool(
        name: "task_add",
        description: "创建任务（US-E1-02；assignee 为负责人；constraint 格式 type:ISO8601，如 startNoLaterThan:2026-11-05T00:00:00Z；dependencies 元素 {\"predecessorID\":\"UUID\",\"type\":\"fs\",\"lagDays\":0}）",
        inputSchema: Schema.object(
            properties: [
                "title": Schema.string(),
                "kind": Schema.string(enumValues: ["task", "group", "milestone"]),
                "parentID": Schema.string(),
                "effortHours": Schema.number(),
                "durationDays": Schema.number(),
                "notes": Schema.string(),
                "priority": Schema.string(enumValues: ["low", "normal", "high", "critical"]),
                "status": Schema.string(enumValues: ["pending", "in_progress", "done", "blocked"]),
                "tags": Schema.arrayOf(Schema.string()),
                "dependencies": Schema.arrayOf(Schema.object(properties: [
                    "predecessorID": Schema.string(),
                    "type": Schema.string(enumValues: ["fs", "ff", "ss", "sf"]),
                    "lagDays": Schema.number(),
                ])),
                "constraint": Schema.string(),
                "schedulingPolicy": Schema.string(enumValues: ["asap", "alap"]),
                "assignments": Schema.arrayOf(Schema.object(properties: [
                    "resourceID": Schema.string(),
                    "units": Schema.number(),
                ], required: ["resourceID"])),
                "assignee": Schema.string(),
            ],
            required: ["title"]
        )
    ) { args, session in
        let a = try ToolArgs(args)
        let id = try session.addTask(
            title: a.string("title"),
            kind: a.optionalKind("kind") ?? .task,
            parentID: a.optionalUUID("parentID"),
            effortHours: a.optionalDouble("effortHours"),
            durationDays: a.optionalDouble("durationDays"),
            notes: a.optionalString("notes") ?? "",
            priority: a.optionalPriority("priority") ?? .normal,
            status: a.optionalStatus("status") ?? .pending,
            tags: a.stringArray("tags"),
            dependencies: try a.optionalDependencies("dependencies") ?? [],
            constraint: try a.optionalConstraint("constraint"),
            schedulingPolicy: try a.optionalSchedulingPolicy("schedulingPolicy") ?? .asap,
            assignments: try a.optionalAssignments("assignments") ?? [],
            // 负责人（US-E1-02）：不传或空串 = nil（默认无负责人）；否则设置。
            assignee: a.optionalString("assignee").flatMap { $0.isEmpty ? nil : $0 }
        )
        return .object(["taskID": .string(id.uuidString)])
    }

    private static let taskList = MCPTool(
        name: "task_list",
        description: "列出任务（可按父任务过滤 / 自然语言过滤，US-E4-01）",
        inputSchema: Schema.object(properties: ["parentID": Schema.string(), "filter": Schema.string()])
    ) { args, session in
        let a = try ToolArgs(args)
        let tasks = try session.listTasks(
            parentID: a.optionalUUID("parentID"),
            filter: a.optionalString("filter") ?? ""
        )
        return .object(["tasks": .array(try tasks.map { try JSONValue.json($0) })])
    }

    private static let taskGet = MCPTool(
        name: "task_get",
        description: "获取单个任务（US-E4-01）",
        inputSchema: Schema.object(properties: ["taskID": Schema.string()], required: ["taskID"])
    ) { args, session in
        let a = try ToolArgs(args)
        let task = try session.getTask(id: a.uuid("taskID"))
        return try JSONValue.json(task)
    }

    private static let taskUpdate = MCPTool(
        name: "task_update",
        description: "更新任务字段（US-E1-02；assignee 传空串可清空负责人）",
        inputSchema: Schema.object(
            properties: [
                "taskID": Schema.string(),
                "title": Schema.string(),
                "kind": Schema.string(enumValues: ["task", "group", "milestone"]),
                "parentID": Schema.string(),
                "effortHours": Schema.number(),
                "durationDays": Schema.number(),
                "notes": Schema.string(),
                "priority": Schema.string(enumValues: ["low", "normal", "high", "critical"]),
                "status": Schema.string(enumValues: ["pending", "in_progress", "done", "blocked"]),
                "progress": Schema.number(),
                "tags": Schema.arrayOf(Schema.string()),
                "dependencies": Schema.arrayOf(Schema.object(properties: [
                    "predecessorID": Schema.string(),
                    "type": Schema.string(enumValues: ["fs", "ff", "ss", "sf"]),
                    "lagDays": Schema.number(),
                ])),
                "constraint": Schema.string(),
                "schedulingPolicy": Schema.string(enumValues: ["asap", "alap"]),
                "assignments": Schema.arrayOf(Schema.object(properties: [
                    "resourceID": Schema.string(),
                    "units": Schema.number(),
                ], required: ["resourceID"])),
                "assignee": Schema.string(),
            ],
            required: ["taskID"]
        )
    ) { args, session in
        let a = try ToolArgs(args)
        let task = try session.updateTask(
            id: a.uuid("taskID"),
            title: a.optionalString("title"),
            kind: a.optionalKind("kind"),
            parentID: a.optionalUUID("parentID"),
            effortHours: a.optionalDouble("effortHours"),
            durationDays: a.optionalDouble("durationDays"),
            notes: a.optionalString("notes"),
            priority: a.optionalPriority("priority"),
            status: a.optionalStatus("status"),
            progress: a.optionalDouble("progress"),
            tags: a.optionalStringArray("tags"),
            dependencies: try a.optionalDependencies("dependencies"),
            constraint: try a.optionalConstraint("constraint"),
            schedulingPolicy: try a.optionalSchedulingPolicy("schedulingPolicy"),
            assignments: try a.optionalAssignments("assignments"),
            // 负责人（US-E1-02）：nil = 不改；空串 = 清空（清空在共享层 updateTask 统一处理）。
            assignee: a.optionalString("assignee")
        )
        return try JSONValue.json(task)
    }

    private static let taskDelete = MCPTool(
        name: "task_delete",
        description: "删除任务及其全部子任务，并移除指向它们的相关性（US-E1-02）",
        inputSchema: Schema.object(properties: ["taskID": Schema.string()], required: ["taskID"])
    ) { args, session in
        let a = try ToolArgs(args)
        _ = try session.deleteTask(id: a.uuid("taskID"))
        return .object(["ok": .bool(true)])
    }

    // MARK: wbs

    private static let wbsImport = MCPTool(
        name: "wbs_import",
        description: "批量导入 WBS 嵌套任务树（US-E1-04）",
        inputSchema: Schema.object(properties: ["nodes": Schema.arrayOf(Schema.object(properties: [:]))])
    ) { args, session in
        let a = try ToolArgs(args)
        guard let nodesValue = args?.objectValue?["nodes"] else {
            throw ToolError.invalidArgument(reason: .mcpMissingParam, message: "缺少参数 nodes")
        }
        let nodes = try JSONValue.decode([WBSNode].self, from: nodesValue)
        let result = try session.importWBS(nodes: nodes)
        return .object([
            "rootIDs": .array(result.rootIDs.map { .string($0.uuidString) }),
            "total": .number(Double(result.total)),
            "warnings": .array(result.warnings.map { .string($0) }),
        ])
    }

    // MARK: schedule / violations / status（Sprint 2）

    private static let scheduleCompute = MCPTool(
        name: "schedule_compute",
        description: "计算排期（US-E2-02）：相关性传播 + ASAP/ALAP，返回每任务最早/最晚与选定安排",
        inputSchema: Schema.object(properties: [
            "projectStart": Schema.string(),
            "projectEnd": Schema.string(),
        ])
    ) { args, session in
        let a = try ToolArgs(args)
        let start = try a.optionalISODate("projectStart")
        let end = try a.optionalISODate("projectEnd")
        let result = try session.computeSchedule(projectStart: start, projectEnd: end)
        return try JSONValue.json(result)
    }

    private static let scheduleCriticalPath = MCPTool(
        name: "schedule_critical_path",
        description: "重要路径与宽延（US-E2-03）：总宽延 ≤ slackLimit 的任务集",
        inputSchema: Schema.object(properties: ["slackLimit": Schema.number()])
    ) { args, session in
        let a = try ToolArgs(args)
        let entries = try session.criticalPath(slackLimit: a.optionalDouble("slackLimit"))
        return .object(["criticalPath": .array(try entries.map { try JSONValue.json($0) })])
    }

    private static let violationsList = MCPTool(
        name: "violations_list",
        description: "列出排期违例（US-E2-05）：环、时限冲突、超项目范围等",
        inputSchema: Schema.object(properties: [:])
    ) { _, session in
        let vs = try session.violations()
        // 接口契约（设计 §B）：违例必须带稳定 `code`。`Violation.code` 是由 `reason` 推导的
        // 计算属性，合成编码不会包含它，故在接口层显式投影，避免消费者只能读语义枚举。
        let rows = try vs.map { violation -> JSONValue in
            var object = try JSONValue.json(violation).objectValue ?? [:]
            object["code"] = .string(violation.code.rawValue)
            return .object(object)
        }
        return .object(["violations": .array(rows)])
    }

    private static let statusUpdate = MCPTool(
        name: "status_update",
        description: "单任务状态/进度回写（US-E3-01/02）；状态置 done 记录完成时间，返回群组聚合完成度",
        inputSchema: Schema.object(
            properties: [
                "taskID": Schema.string(),
                "status": Schema.string(enumValues: ["pending", "in_progress", "done", "blocked"]),
                "progress": Schema.number(),
            ],
            required: ["taskID"]
        )
    ) { args, session in
        let a = try ToolArgs(args)
        let task = try session.statusUpdate(
            id: a.uuid("taskID"),
            status: a.optionalStatus("status"),
            progress: a.optionalDouble("progress")
        )
        let group = try session.groupProgress(id: task.id)
        var result = try JSONValue.json(task).objectValue ?? [:]
        result["groupProgress"] = .number(group)
        return .object(result)
    }

    private static let statusBatchUpdate = MCPTool(
        name: "status_batch_update",
        description: "批量回写任务状态/进度（US-E3-02）：返回逐条成功与失败明细，失败项不中断后续条目",
        inputSchema: Schema.object(
            properties: [
                "tasks": Schema.arrayOf(Schema.object(properties: [
                    "taskID": Schema.string(),
                    "status": Schema.string(enumValues: ["pending", "in_progress", "done", "blocked"]),
                    "progress": Schema.number(),
                ], required: ["taskID"])),
            ],
            required: ["tasks"]
        )
    ) { args, session in
        let a = try ToolArgs(args)
        let result = try session.statusBatch(a.statusUpdates("tasks"))
        return try JSONValue.json(result)
    }

    // MARK: resource（US-E1-05）

    private static let resourceAdd = MCPTool(
        name: "resource_add",
        description: "添加资源（US-E1-05）：人员/设备/素材，单位与效率参与投入换算",
        inputSchema: Schema.object(
            properties: [
                "name": Schema.string(),
                "kind": Schema.string(enumValues: ["person", "equipment", "material", "group"]),
                "units": Schema.number(),
                "efficiency": Schema.number(),
            ],
            required: ["name"]
        )
    ) { args, session in
        let a = try ToolArgs(args)
        let id = try session.resourceAdd(
            name: a.string("name"),
            kind: a.optionalResourceKind("kind") ?? .person,
            units: a.optionalDouble("units") ?? 1,
            efficiency: a.optionalDouble("efficiency") ?? 1
        )
        return .object(["resourceID": .string(id.uuidString)])
    }

    private static let resourceList = MCPTool(
        name: "resource_list",
        description: "列出项目资源（US-E1-05）",
        inputSchema: Schema.object(properties: [:])
    ) { _, session in
        let resources = try session.resourceList()
        return .object(["resources": .array(try resources.map { try JSONValue.json($0) })])
    }
}

/// 项目工具结果组装（FR-KAIRO-FMT-6）。
enum ProjectResults {
    /// `project_create`：新建项目恒以当前版本落盘，无来源版本。
    static func created(_ meta: ProjectMetadata) -> JSONValue {
        var result = metadataFields(meta)
        result["formatVersion"] = .number(Double(KairoFile.currentFormatVersion))
        return .object(result)
    }

    /// `project_open`：`formatVersion` 为磁盘文件版本；
    /// `currentFormatVersion` / `needsUpgrade` 说明当前目标版本与保存后是否升级。
    /// 打开不改写磁盘，故不报告 `upgradedFrom`。
    static func opened(_ meta: ProjectMetadata, sourceFormatVersion: Int?) -> JSONValue {
        let source = sourceFormatVersion ?? KairoFile.currentFormatVersion
        var result = metadataFields(meta)
        result["formatVersion"] = .number(Double(source))
        result["currentFormatVersion"] = .number(Double(KairoFile.currentFormatVersion))
        result["needsUpgrade"] = .bool(source < KairoFile.currentFormatVersion)
        return .object(result)
    }

    /// `project_save`：`formatVersion` 为写出文件的版本（恒为当前版本）。
    /// `upgradedFrom` 描述写出文件的来源版本，仅当来源早于当前版本时出现；
    /// 目标路径与原路径不同时不改动原文件。
    static func saved(updatedAt: Date, path: String, upgradedFrom: Int?) -> JSONValue {
        var result: [String: JSONValue] = [
            "formatVersion": .number(Double(KairoFile.currentFormatVersion)),
            "savedAt": .string(ISO8601DateFormatter().string(from: updatedAt)),
            "path": .string(path),
        ]
        if let upgradedFrom, upgradedFrom < KairoFile.currentFormatVersion {
            result["upgradedFrom"] = .number(Double(upgradedFrom))
        }
        return .object(result)
    }

    private static func metadataFields(_ meta: ProjectMetadata) -> [String: JSONValue] {
        var result: [String: JSONValue] = [
            "projectID": .string(meta.id.uuidString),
            "title": .string(meta.title),
        ]
        let formatter = ISO8601DateFormatter()
        if let start = meta.projectStart { result["projectStart"] = .string(formatter.string(from: start)) }
        if let end = meta.projectEnd { result["projectEnd"] = .string(formatter.string(from: end)) }
        return result
    }
}

// MARK: - JSON Schema 构造

private enum Schema {
    static func object(properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        var schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }
        return .object(schema)
    }

    static func string(enumValues: [String]? = nil) -> JSONValue {
        guard let enumValues else { return .object(["type": .string("string")]) }
        return .object([
            "type": .string("string"),
            "enum": .array(enumValues.map { .string($0) }),
        ])
    }

    static func number() -> JSONValue {
        .object(["type": .string("number")])
    }

    static func arrayOf(_ item: JSONValue) -> JSONValue {
        .object(["type": .string("array"), "items": item])
    }
}

// MARK: - 参数解析

private struct ToolArgs {
    private let dict: [String: JSONValue]

    init(_ value: JSONValue?) throws {
        guard let object = value?.objectValue else {
            throw ToolError.invalidArgument(reason: .mcpWrongType, message: "参数必须是 JSON 对象")
        }
        dict = object
    }

    func string(_ key: String) throws -> String {
        guard let value = dict[key]?.stringValue, !value.isEmpty else {
            throw ToolError.invalidArgument(reason: .mcpMissingParam, message: "缺少参数 \(key)")
        }
        return value
    }

    func uuid(_ key: String) throws -> UUID {
        guard let uuid = try optionalUUID(key) else {
            throw ToolError.invalidArgument(reason: .mcpMissingParam, message: "缺少参数 \(key)")
        }
        return uuid
    }

    func optionalString(_ key: String) -> String? {
        dict[key]?.stringValue
    }

    func optionalDouble(_ key: String) -> Double? {
        dict[key]?.doubleValue
    }

    func optionalUUID(_ key: String) throws -> UUID? {
        guard let raw = dict[key]?.stringValue else { return nil }
        guard let uuid = UUID(uuidString: raw) else {
            throw ToolError.invalidArgument(reason: .mcpMalformedUUID, message: "参数 \(key) 不是合法 UUID：\(raw)")
        }
        return uuid
    }

    func optionalISODate(_ key: String) throws -> Date? {
        guard let raw = dict[key]?.stringValue else { return nil }
        guard let date = ISO8601DateFormatter().date(from: raw) else {
            throw ToolError.invalidArgument(reason: .mcpMalformedDate, message: "参数 \(key) 不是合法 ISO8601 日期：\(raw)")
        }
        return date
    }

    /// 时限规格：type:ISO8601（如 startNoLaterThan:2026-11-05T00:00:00Z）。
    /// 相关性数组：元素 {"predecessorID":"UUID","type":"fs","lagDays":0}，type/lagDays 可省略。
    func optionalDependencies(_ key: String) throws -> [TaskDependency]? {
        guard let value = dict[key] else { return nil }
        guard let array = value.arrayValue else {
            throw ToolError.invalidArgument(reason: .mcpWrongType, message: "参数 \(key) 必须是数组")
        }
        return try array.map { item in
            guard let obj = item.objectValue,
                  let rawID = obj["predecessorID"]?.stringValue,
                  let uuid = UUID(uuidString: rawID) else {
                throw ToolError.invalidArgument(
                    reason: .mcpMalformedDependency,
                    message: "参数 \(key) 的元素格式应为 {\"predecessorID\":\"UUID\",\"type\":\"fs\",\"lagDays\":0}"
                )
            }
            let type: TaskDependency.DependencyType
            if let rawType = obj["type"]?.stringValue {
                guard let parsed = TaskDependency.DependencyType(rawValue: rawType) else {
                    throw ToolError.invalidArgument(
                    reason: .mcpMalformedDependency,
                    message: "参数 \(key) 的相关性类型非法：\(rawType)（fs/ff/ss/sf）"
                )
                }
                type = parsed
            } else {
                type = .fs
            }
            return TaskDependency(
                predecessorID: uuid,
                type: type,
                lagDays: obj["lagDays"]?.doubleValue ?? 0
            )
        }
    }

    /// 分配数组：元素 {"resourceID":"UUID","units":1}，units 可省略（默认 1）。
    func optionalAssignments(_ key: String) throws -> [TaskAssignment]? {
        guard let value = dict[key] else { return nil }
        guard let array = value.arrayValue else {
            throw ToolError.invalidArgument(reason: .mcpWrongType, message: "参数 \(key) 必须是数组")
        }
        return try array.map { item in
            guard let obj = item.objectValue,
                  let rawID = obj["resourceID"]?.stringValue,
                  let uuid = UUID(uuidString: rawID) else {
                throw ToolError.invalidArgument(
                    reason: .mcpMalformedAssignment,
                    message: "参数 \(key) 的元素格式应为 {\"resourceID\":\"UUID\",\"units\":1}"
                )
            }
            return TaskAssignment(resourceID: uuid, units: obj["units"]?.doubleValue ?? 1)
        }
    }

    func optionalConstraint(_ key: String) throws -> SchedulingConstraint? {
        guard let raw = dict[key]?.stringValue else { return nil }
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let date = ISO8601DateFormatter().date(from: String(parts[1])) else {
            throw ToolError.invalidArgument(
                reason: .mcpMalformedConstraint,
                message: "参数 \(key) 格式应为 type:ISO8601（如 startNoLaterThan:2026-11-05T00:00:00Z）"
            )
        }
        switch String(parts[0]) {
        case "startNoEarlierThan": return .startNoEarlierThan(date)
        case "startNoLaterThan": return .startNoLaterThan(date)
        case "endNoEarlierThan": return .endNoEarlierThan(date)
        case "endNoLaterThan": return .endNoLaterThan(date)
        default:
            throw ToolError.invalidArgument(reason: .mcpMalformedConstraint, message: "参数 \(key) 非法时限类型：\(parts[0])")
        }
    }

    func optionalSchedulingPolicy(_ key: String) throws -> SchedulingPolicy? {
        guard let raw = dict[key]?.stringValue else { return nil }
        guard let policy = SchedulingPolicy(rawValue: raw) else {
            throw ToolError.invalidArgument(reason: .mcpInvalidEnum, message: "参数 \(key) 非法：\(raw)（asap/alap）")
        }
        return policy
    }

    func optionalKind(_ key: String) throws -> TaskKind? {
        guard let raw = dict[key]?.stringValue else { return nil }
        guard let kind = TaskKind(rawValue: raw) else {
            throw ToolError.invalidArgument(reason: .mcpInvalidEnum, message: "参数 \(key) 非法：\(raw)（task/group/milestone）")
        }
        return kind
    }

    func optionalPriority(_ key: String) throws -> TaskPriority? {
        guard let raw = dict[key]?.stringValue else { return nil }
        guard let priority = TaskPriority(rawValue: raw) else {
            throw ToolError.invalidArgument(reason: .mcpInvalidEnum, message: "参数 \(key) 非法：\(raw)（low/normal/high/critical）")
        }
        return priority
    }

    func optionalStatus(_ key: String) throws -> TaskStatus? {
        guard let raw = dict[key]?.stringValue else { return nil }
        guard let status = TaskStatus(rawValue: raw) else {
            throw ToolError.invalidArgument(reason: .mcpInvalidEnum, message: "参数 \(key) 非法：\(raw)（pending/in_progress/done/blocked）")
        }
        return status
    }

    func optionalResourceKind(_ key: String) throws -> ResourceKind? {
        guard let raw = dict[key]?.stringValue else { return nil }
        guard let kind = ResourceKind(rawValue: raw) else {
            throw ToolError.invalidArgument(reason: .mcpInvalidEnum, message: "参数 \(key) 非法：\(raw)（person/equipment/material/group）")
        }
        return kind
    }

    /// 批量回写清单：[{"taskID":"UUID","status":"done","progress":1}]。
    func statusUpdates(_ key: String) throws -> [KairoSession.StatusUpdateInput] {
        guard let array = dict[key]?.arrayValue else {
            throw ToolError.invalidArgument(reason: .mcpWrongType, message: "参数 \(key) 必须是数组")
        }
        return try array.map { item in
            guard let obj = item.objectValue,
                  let rawID = obj["taskID"]?.stringValue,
                  let uuid = UUID(uuidString: rawID) else {
                throw ToolError.invalidArgument(
                    reason: .mcpMalformedBatchItem,
                    message: "参数 \(key) 的元素格式应为 {\"taskID\":\"UUID\",\"status\":\"done\",\"progress\":1}"
                )
            }
            let status: TaskStatus?
            if let rawStatus = obj["status"]?.stringValue {
                guard let parsed = TaskStatus(rawValue: rawStatus) else {
                    throw ToolError.invalidArgument(
                        reason: .mcpMalformedBatchItem,
                        message: "参数 \(key) 的状态非法：\(rawStatus)（pending/in_progress/done/blocked）"
                    )
                }
                status = parsed
            } else {
                status = nil
            }
            return KairoSession.StatusUpdateInput(
                taskID: uuid,
                status: status,
                progress: obj["progress"]?.doubleValue
            )
        }
    }

    func stringArray(_ key: String) -> [String] {
        dict[key]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    func optionalStringArray(_ key: String) -> [String]? {
        guard let value = dict[key] else { return nil }
        return value.arrayValue?.compactMap(\.stringValue)
    }
}
