import Foundation

/// 稳定错误码（F-0703 / 设计 §A）。文法 `<group>_<detail>`，v0.9.0 起冻结，只增不改。
///
/// 为什么是码而不是文案：错误文案要按语言渲染（视图 / CLI / MCP 各持渲染器），
/// 而跨进程、跨版本的消费者（脚本、模型上下文、日志检索）需要与语言无关的稳定标识。
/// 码进结构体，自然语言只留在各自的渲染层。
///
/// 分组：`model` 领域模型校验 / `schedule` 排期与违例 / `storage` 文件读写 /
/// `session` 会话状态 / `cli` 命令行用法 / `mcp` 工具参数与协议 / `internal` 兜底。
///
/// `KairoUpdater` 自带同文法枚举（`UpdaterErrorCode`，前缀 `updater_`），
/// 不复用本类型：OTA 模块零依赖，避免被核心版本的节奏绑住。两个码表的
/// rawValue 唯一性由各自测试的「去重断言」兜底。
public enum KairoErrorCode: String, Codable, Hashable, Sendable, CaseIterable {
    // MARK: - model（领域模型校验）

    case taskNotFound = "model_task_not_found"
    case parentNotFound = "model_parent_not_found"
    case progressOutOfRange = "model_progress_out_of_range"
    case moveIntoSubtree = "model_move_into_subtree"
    case dependencySelf = "model_dependency_self"
    case dependencyCycle = "model_dependency_cycle"
    case dependencyPredecessorNotFound = "model_dependency_predecessor_not_found"
    case groupPromoted = "model_group_promoted"
    case resourceUnitInvalid = "model_resource_unit_invalid"
    case resourceEfficiencyInvalid = "model_resource_efficiency_invalid"
    case resourceNotFound = "model_resource_not_found"

    // MARK: - schedule（排期、时限与违例）

    case scheduleCycle = "schedule_cycle"
    case taskAfterProjectEnd = "schedule_task_after_project_end"
    case taskBeforeProjectStart = "schedule_task_before_project_start"
    case constraintWindowTooNarrow = "schedule_constraint_window_too_narrow"
    case negativeSlack = "schedule_negative_slack"
    case constraintVsDependency = "schedule_constraint_vs_dependency"
    case constraintVsPrerequisite = "schedule_constraint_vs_prerequisite"
    /// F-0715 / D-022：任务开始日落在项目窗口之外（用户输入致因）。
    case startAfterProjectWindow = "schedule_start_after_project_window"

    // MARK: - storage（.kairo 读写）

    case unsupportedFormat = "storage_unsupported_format"
    case malformedFormatVersion = "storage_malformed_version"
    case noMigrationPath = "storage_no_migration_path"
    case migrationFailed = "storage_migration_failed"
    case fileUnreadable = "storage_unreadable"
    case writeFailed = "storage_write_failed"

    // MARK: - session（命令层会话状态）

    case projectNotOpen = "session_project_not_open"
    case noSavePath = "session_no_save_path"

    // MARK: - cli（命令行用法）

    case cliMissingOperand = "cli_usage_missing_operand"
    case cliUnknownOption = "cli_usage_unknown_option"
    case cliUnknownCommand = "cli_usage_unknown_command"
    case cliInvalidEnum = "cli_usage_invalid_enum"
    case cliInvalidDate = "cli_usage_invalid_date"
    case cliIdPrefix = "cli_usage_id_prefix"

    // MARK: - mcp（工具参数与 JSON-RPC）

    case mcpParseError = "mcp_parse_error"
    case mcpMethodNotFound = "mcp_method_not_found"
    case mcpMissingToolName = "mcp_missing_tool_name"
    case mcpUnknownTool = "mcp_unknown_tool"
    case mcpMissingParam = "mcp_missing_param"
    case mcpWrongType = "mcp_wrong_type"
    case mcpMalformedUUID = "mcp_malformed_uuid"
    case mcpMalformedDate = "mcp_malformed_date"
    case mcpInvalidEnum = "mcp_invalid_enum"
    case mcpMalformedConstraint = "mcp_malformed_constraint"
    case mcpMalformedDependency = "mcp_malformed_dependency"
    case mcpMalformedAssignment = "mcp_malformed_assignment"
    case mcpMalformedBatchItem = "mcp_malformed_batch_item"

    // MARK: - internal（兜底）

    case internalError = "internal_error"
}
