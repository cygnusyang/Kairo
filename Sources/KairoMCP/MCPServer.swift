import Foundation
import KairoCore
import KairoCommands

/// MCP 服务核心：逐行 JSON-RPC 2.0 传输（ADR-010 零第三方依赖）。
/// 方法面：initialize / tools/list / tools/call / ping + 通知（不响应）。
/// 与工具层（Tools.swift）分离，可单测。
final class MCPServer {
    static let protocolVersion = "2024-11-05"
    static let serverInfo: [String: String] = ["name": "kairo", "version": "0.8.5"]

    private let registry: ToolRegistry
    private let session: KairoSession
    private var negotiatedProtocolVersion: String?

    init(registry: ToolRegistry = ToolRegistry(), session: KairoSession = KairoSession()) {
        self.registry = registry
        self.session = session
    }

    /// 处理一行请求 JSON，返回一行响应 JSON；通知返回 nil。
    func handle(requestJSON: String) -> String? {
        guard let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: Data(requestJSON.utf8)) else {
            return encode(.failure(
                JSONRPCErrorObject(
                    code: JSONRPCErrorCode.parseError,
                    reason: KairoErrorCode.mcpParseError.rawValue,
                    message: "解析失败：无效的 JSON-RPC"
                ),
                id: extractID(from: requestJSON)
            ))
        }
        if request.isNotification {
            handleNotification(request)
            return nil
        }
        return encode(dispatch(request))
    }

    private func dispatch(_ request: JSONRPCRequest) -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return .ok(initializeResult(request), id: request.id)
        case "tools/list":
            return .ok(toolsListResult(), id: request.id)
        case "tools/call":
            return callTool(request)
        case "ping":
            return .ok(.object([:]), id: request.id)
        default:
            return .failure(
                JSONRPCErrorObject(
                    code: JSONRPCErrorCode.methodNotFound,
                    reason: KairoErrorCode.mcpMethodNotFound.rawValue,
                    message: "未知方法：\(request.method)"
                ),
                id: request.id
            )
        }
    }

    private func handleNotification(_ request: JSONRPCRequest) {
        // 当前仅接收 notifications/initialized；无需动作。
        _ = request
    }

    private func initializeResult(_ request: JSONRPCRequest) -> JSONValue {
        if let version = request.params?.objectValue?["protocolVersion"]?.stringValue {
            negotiatedProtocolVersion = version
        }
        return .object([
            "protocolVersion": .string(Self.protocolVersion),
            "capabilities": .object(["tools": .object([:])]),
            "serverInfo": .object(Self.serverInfo.mapValues { .string($0) }),
        ])
    }

    private func toolsListResult() -> JSONValue {
        let tools: [JSONValue] = registry.tools.map { tool in
            .object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "inputSchema": tool.inputSchema,
            ])
        }
        return .object(["tools": .array(tools)])
    }

    private func callTool(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let params = request.params?.objectValue ?? [:]
        guard let name = params["name"]?.stringValue else {
            return .failure(
                JSONRPCErrorObject(
                    code: JSONRPCErrorCode.invalidParams,
                    reason: KairoErrorCode.mcpMissingToolName.rawValue,
                    message: "tools/call 缺少 name"
                ),
                id: request.id
            )
        }
        guard let tool = registry.find(name) else {
            return .failure(
                JSONRPCErrorObject(
                    code: JSONRPCErrorCode.methodNotFound,
                    reason: KairoErrorCode.mcpUnknownTool.rawValue,
                    message: "未知工具：\(name)"
                ),
                id: request.id
            )
        }
        do {
            let result = try tool.handler(params["arguments"], session)
            let text = try encodeText(result)
            return .ok(
                .object([
                    "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                    "isError": .bool(false),
                ]),
                id: request.id
            )
        } catch {
            let failure = self.failure(from: error)
            let text = (try? encodeText(.json(failure))) ?? "{\"code\":\"internal_error\",\"reason\":\"internal_error\"}"
            return .ok(
                .object([
                    "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                    "isError": .bool(true),
                ]),
                id: request.id
            )
        }
    }

    /// 映射错误为结构化失败（架构 §3.1 错误契约）。
    ///
    /// `code` 是冻结的粗粒度分类（不改取值），`reason` 是本版新增的细粒度稳定码；
    /// `message` 阶段一保持中文原样（设计 §6：先给码，v0.10.0 再切英文）。
    private func failure(from error: Error) -> ToolFailure {
        switch error {
        case let sessionError as SessionError:
            return ToolFailure(
                code: sessionError.code.rawValue,
                reason: sessionError.reason.rawValue,
                message: sessionError.message,
                taskID: sessionError.taskID?.uuidString
            )
        case let toolError as ToolError:
            return ToolFailure(
                code: "invalid_argument",
                reason: toolError.reason.rawValue,
                message: toolError.description,
                taskID: nil
            )
        default:
            return ToolFailure(
                code: "internal_error",
                reason: KairoErrorCode.internalError.rawValue,
                message: "\(error)",
                taskID: nil
            )
        }
    }

    private func encode(_ response: JSONRPCResponse) -> String? {
        guard let data = try? JSONEncoder().encode(response) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func encodeText(_ value: JSONValue) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// 从无法反序列化的文本里尽力取出 id（parse error 响应用）。
    private func extractID(from raw: String) -> JSONValue? {
        guard let object = (try? JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)))?.objectValue else {
            return nil
        }
        return object["id"]
    }
}
