import Foundation
import Testing
import KairoCore
@testable import KairoMCP

// F-0708 MCP 错误码（阶段一）的验收用例。
// 用例编号对应 docs/features/06-localization-cases.md 的 E 组。
// 基线 Tests/Fixtures/mcp-errors-v085.json 是 v0.8.5 的中文 message 逐字快照。

// MARK: - MCP 错误码（F-0708）

/// v0.8.5 错误基线（Tests/Fixtures/mcp-errors-v085.json）。
private struct MCPErrorBaseline: Decodable {
    struct Entry: Decodable {
        let id: String
        let reason: String
        /// ToolFailure 的 \`code\`；JSON-RPC 层错误没有该字段。
        let code: String?
        let message: String
    }

    let cases: [Entry]
}

private func loadMCPErrorBaseline() throws -> [MCPErrorBaseline.Entry] {
    // Tests/Fixtures 不在测试 target 的资源声明内（Package.swift 未声明），故按源码路径读取。
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()          // Tests/InterfaceTests
        .deletingLastPathComponent()          // Tests
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("mcp-errors-v085.json")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(MCPErrorBaseline.self, from: data).cases
}

/// 每个基线条目对应的 JSON-RPC 请求（id 与 fixture 的 id 同名）。
private func mcpErrorRequests(taskID: String) -> [String: String] {
    [
        "wrong_type_object":
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"task_add","arguments":[]}}"#,
        "wrong_type_array":
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"T","dependencies":1}}}"#,
        "missing_param_title":
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"task_add","arguments":{}}}"#,
        "missing_param_nodes":
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"wbs_import","arguments":{}}}"#,
        "missing_param_taskid":
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"task_get","arguments":{}}}"#,
        "malformed_uuid":
            #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"task_get","arguments":{"taskID":"abc"}}}"#,
        "malformed_date":
            #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"project_create","arguments":{"title":"T","projectStart":"nope"}}}"#,
        "malformed_dependency_item":
            #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"T","dependencies":[{}]}}}"#,
        "malformed_dependency_type":
            "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"task_add\",\"arguments\":{\"title\":\"T\",\"dependencies\":[{\"predecessorID\":\"\(taskID)\",\"type\":\"xx\"}]}}}",
        "malformed_assignment_item":
            #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"T","assignments":[{}]}}}"#,
        "malformed_batch_item":
            #"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"status_batch_update","arguments":{"tasks":[{}]}}}"#,
        "malformed_batch_status":
            "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"tools/call\",\"params\":{\"name\":\"status_batch_update\",\"arguments\":{\"tasks\":[{\"taskID\":\"\(taskID)\",\"status\":\"paused\"}]}}}",
        "malformed_constraint_format":
            #"{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"T","constraint":"bad"}}}"#,
        "malformed_constraint_type":
            #"{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"T","constraint":"sometime:2026-11-05T00:00:00Z"}}}"#,
        "invalid_enum_policy":
            #"{"jsonrpc":"2.0","id":15,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"T","schedulingPolicy":"soon"}}}"#,
        "invalid_enum_kind":
            #"{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"T","kind":"gantt"}}}"#,
        "invalid_enum_priority":
            #"{"jsonrpc":"2.0","id":17,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"T","priority":"urgent"}}}"#,
        "invalid_enum_status":
            #"{"jsonrpc":"2.0","id":18,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"T","status":"paused"}}}"#,
        "invalid_enum_resource_kind":
            #"{"jsonrpc":"2.0","id":19,"method":"tools/call","params":{"name":"resource_add","arguments":{"name":"R","kind":"robot"}}}"#,
        "parse_error": "not json",
        "method_not_found": #"{"jsonrpc":"2.0","id":21,"method":"frobnicate"}"#,
        "missing_tool_name": #"{"jsonrpc":"2.0","id":22,"method":"tools/call","params":{}}"#,
        "unknown_tool": #"{"jsonrpc":"2.0","id":23,"method":"tools/call","params":{"name":"nope","arguments":{}}}"#,
    ]
}

/// 发送一行请求并解码响应。
private func sendJSON(_ server: MCPServer, _ payload: String) throws -> JSONValue {
    let response = try #require(server.handle(requestJSON: payload))
    return try JSONDecoder().decode(JSONValue.self, from: Data(response.utf8))
}

struct MCPErrorReasonTests {
    /// \`code\` 阶段一冻结的取值（5 值 + internal_error）：不许增减。
    private static let frozenCodes: Set<String> = [
        "project_not_open", "task_not_found", "invalid_argument",
        "file_unreadable", "unsupported_format", "internal_error",
    ]

    /// E-01 + E-02：22 处错误逐条带稳定 \`reason\`，且 \`message\` 与 v0.8.5 逐字一致。
    @Test func everyErrorCarriesReasonAndV085Message() throws {
        let baseline = try loadMCPErrorBaseline()
        let requests = mcpErrorRequests(taskID: UUID().uuidString)
        #expect(requests.count == baseline.count, "基线条目与请求表必须一一对应")

        let server = MCPServer()
        for entry in baseline {
            let payload = try #require(requests[entry.id], "缺少请求：\(entry.id)")
            let response = try sendJSON(server, payload)
            let object = try #require(response.objectValue, "\(entry.id)：响应不是对象")

            if let error = object["error"]?.objectValue {
                #expect(entry.code == nil, "\(entry.id)：JSON-RPC 层错误不带 ToolFailure.code")
                #expect(error["reason"]?.stringValue == entry.reason, "\(entry.id)：reason")
                #expect(error["message"]?.stringValue == entry.message, "\(entry.id)：message")
                continue
            }

            let result = try #require(object["result"]?.objectValue, "\(entry.id)：缺 result")
            #expect(result["isError"]?.boolValue == true, "\(entry.id)：isError 应为 true")
            let text = try #require(
                result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue,
                "\(entry.id)：缺 content[0].text"
            )
            let failure = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
            #expect(failure.objectValue?["reason"]?.stringValue == entry.reason, "\(entry.id)：reason")
            #expect(failure.objectValue?["message"]?.stringValue == entry.message, "\(entry.id)：message")
            #expect(failure.objectValue?["code"]?.stringValue == entry.code, "\(entry.id)：code")
        }
    }

    /// E-01：\`reason\` 全部是 \`KairoErrorCode\` 的合法取值，\`code\` 不越出冻结集合。
    @Test func reasonsAndCodesStayInFrozenSets() throws {
        let baseline = try loadMCPErrorBaseline()
        for entry in baseline {
            #expect(
                KairoErrorCode(rawValue: entry.reason) != nil,
                "\(entry.id)：reason 不在 KairoErrorCode 内：\(entry.reason)"
            )
            #expect(
                entry.reason.range(of: "^[a-z]+(_[a-z]+)+$", options: .regularExpression) != nil,
                "\(entry.id)：reason 不符合 <group>_<detail> 文法：\(entry.reason)"
            )
            if let code = entry.code {
                #expect(Self.frozenCodes.contains(code), "\(entry.id)：code 越出冻结集合：\(code)")
            }
        }
    }

    /// E-04：协议结构不变——错误仍在 \`result.content[0].text\` 内，旧消费的文本匹配仍可命中。
    @Test func errorResponseKeepsProtocolShapeAndOriginalText() throws {
        let server = MCPServer()
        let response = try sendJSON(
            server,
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"task_get","arguments":{"taskID":"abc"}}}"#
        )
        let object = try #require(response.objectValue)
        #expect(Set(object.keys) == ["jsonrpc", "id", "result"])

        let result = try #require(object["result"]?.objectValue)
        #expect(Set(result.keys) == ["content", "isError"])

        let text = try #require(
            result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue
        )
        // 顶层没有新增键承载 code：错误码仍在 content 文本内。
        #expect(result["code"] == nil)
        #expect(text.contains("不是合法 UUID"))
        #expect(text.contains("mcp_malformed_uuid"))
    }

    /// 会话层错误同样带 \`reason\`（\`SessionError.reason\` 透传），\`code\` 仍为原粗粒度值。
    @Test func sessionErrorsAlsoCarryReason() throws {
        let server = MCPServer()
        let response = try sendJSON(
            server,
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"task_get","arguments":{"taskID":"\#(UUID().uuidString)"}}}"#
        )
        let result = try #require(response.objectValue?["result"]?.objectValue)
        let text = try #require(result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
        let failure = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        #expect(failure.objectValue?["code"]?.stringValue == "project_not_open")
        #expect(failure.objectValue?["reason"]?.stringValue == "session_project_not_open")
    }

    /// 违例列表必须带稳定 \`code\`（\`Violation.code\` 是计算属性，接口层显式投影）。
    @Test func violationsListCarriesStableCode() throws {
        let server = MCPServer()
        _ = try sendJSON(
            server,
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_create","arguments":{"title":"违例项目"}}}"#
        )
        _ = try sendJSON(
            server,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"B","durationDays":1,"constraint":"startNoEarlierThan:2026-11-09T00:00:00Z"}}}"#
        )
        _ = try sendJSON(
            server,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"schedule_compute","arguments":{"projectStart":"2026-11-02T00:00:00Z","projectEnd":"2026-11-08T00:00:00Z"}}}"#
        )
        let response = try sendJSON(
            server,
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"violations_list","arguments":{}}}"#
        )
        let result = try #require(response.objectValue?["result"]?.objectValue)
        let text = try #require(result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
        let payload = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        let violations = try #require(payload.objectValue?["violations"]?.arrayValue)
        #expect(!violations.isEmpty)
        for violation in violations {
            let code = violation.objectValue?["code"]?.stringValue
            #expect(code != nil)
            #expect(KairoErrorCode(rawValue: code ?? "") != nil)
            // reason 仍在（阶段一保留语义枚举，供后续渲染与迁移）。
            #expect(violation.objectValue?["reason"] != nil)
        }
    }
}
