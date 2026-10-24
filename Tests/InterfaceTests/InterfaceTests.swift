import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Testing
import KairoCore
import KairoCommands
@testable import KairoMCP
@testable import KairoCLI

// 接口对等性契约测试（US-E5-05）：MCP 侧 JSON-RPC 编解码与工具往返。
// CLI 侧路由测试见 CLITests.swift。
// 说明：US-E1-02 负责人字段冻结判据（T1）要求 A1/A2 的 CLI 契约用例与 A3 的 MCP 契约用例
// 集中在此文件登记，故本文件同时包含这两侧用例；常规 CLI 路由用例仍见 CLITests.swift。

/// 发送一行请求并解析响应为 JSONValue。
private func send(_ server: MCPServer, _ json: String) throws -> JSONValue {
    let response = server.handle(requestJSON: json)!
    return try JSONDecoder().decode(JSONValue.self, from: Data(response.utf8))
}

/// 取出 tools/call 的 result.content[0].text，并解析为 JSONValue。
private func toolResult(_ value: JSONValue) throws -> JSONValue {
    let content = value.objectValue?["result"]?.objectValue?["content"]?.arrayValue ?? []
    let text = content.first?.objectValue?["text"]?.stringValue ?? "{}"
    return try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

// MARK: - initialize 握手

@Test func initializeHandshakeReturnsProtocolAndServerInfo() throws {
    let server = MCPServer()
    let response = try send(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"测试"}}}"#
    )
    #expect(response.objectValue?["id"] == .number(1))
    let result = response.objectValue?["result"]?.objectValue
    #expect(result?["protocolVersion"]?.stringValue == "2024-11-05")
    #expect(result?["serverInfo"]?.objectValue?["name"]?.stringValue == "kairo")
    #expect(result?["capabilities"]?.objectValue?["tools"] != nil)
}

// MARK: - tools/list schema

@Test func toolsListReturnsSprint2ToolSetWithSchema() throws {
    let server = MCPServer()
    let response = try send(server, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
    let tools = response.objectValue?["result"]?.objectValue?["tools"]?.arrayValue ?? []
    let names = tools.compactMap { $0.objectValue?["name"]?.stringValue }
    #expect(names == [
        "project_create", "project_open", "project_save",
        "task_add", "task_list", "task_get", "task_update", "task_delete",
        "wbs_import",
        "schedule_compute", "schedule_critical_path", "violations_list", "status_update",
        "status_batch_update", "resource_add", "resource_list",
    ])
    #expect(tools.allSatisfy { $0.objectValue?["inputSchema"]?.objectValue?["type"]?.stringValue == "object" })
    let taskAdd = tools.first { $0.objectValue?["name"]?.stringValue == "task_add" }
    #expect(taskAdd?.objectValue?["inputSchema"]?.objectValue?["required"]?.arrayValue?.first?.stringValue == "title")
}

// MARK: - violations_list 文案（F-0720）

/// 阶段一契约：violations_list 必须同时返回结构化字段与人类可读 message，
/// 且 message 由 KairoCommands.ViolationText 产出（与 CLI 同一实现）。
@Test func violationsListCarriesCodeReasonAndMessage() throws {
    let server = MCPServer()
    _ = try send(server, #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_create","arguments":{"title":"违例项目"}}}"#)
    _ = try send(server, #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"任务 A"}}}"#)
    _ = try send(server, #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"任务 B"}}}"#)
    let ids = try toolResult(try send(server, #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"task_list","arguments":{}}}"#))
    let tasks = try #require(ids.objectValue?["tasks"]?.arrayValue)
    let a = try #require(tasks.first?.objectValue?["id"]?.stringValue)
    let b = try #require(tasks.last?.objectValue?["id"]?.stringValue)
    // 造一个相关性环：A 依赖 B，B 依赖 A
    _ = try send(server, "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"task_update\",\"arguments\":{\"taskID\":\"\(a)\",\"dependencies\":[{\"predecessorID\":\"\(b)\",\"type\":\"fs\"}]}}}")
    _ = try send(server, "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"task_update\",\"arguments\":{\"taskID\":\"\(b)\",\"dependencies\":[{\"predecessorID\":\"\(a)\",\"type\":\"fs\"}]}}}")

    let listed = try toolResult(try send(server, #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"violations_list","arguments":{}}}"#))
    let rows = try #require(listed.objectValue?["violations"]?.arrayValue)
    #expect(!rows.isEmpty)
    for row in rows {
        #expect(row.objectValue?["code"]?.stringValue?.isEmpty == false)
        #expect(row.objectValue?["reason"] != nil)
        let message = try #require(row.objectValue?["message"]?.stringValue)
        #expect(!message.isEmpty)
        #expect(message.contains("任务「"))
    }
}

// MARK: - tools/call 往返

@Test func taskAddThenTaskListRoundTrip() throws {
    let server = MCPServer()
    _ = try send(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_create","arguments":{"title":"演示项目"}}}"#
    )
    let addResponse = try send(
        server,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"任务 A","kind":"group"}}}"#
    )
    let taskID = try toolResult(addResponse).objectValue?["taskID"]?.stringValue
    #expect(taskID != nil)

    let listResponse = try send(
        server,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"task_list","arguments":{}}}"#
    )
    let tasks = try toolResult(listResponse).objectValue?["tasks"]?.arrayValue ?? []
    #expect(tasks.count == 1)
    #expect(tasks.first?.objectValue?["id"]?.stringValue == taskID)
    #expect(tasks.first?.objectValue?["kind"]?.stringValue == "group")
}


@Test func taskAddWithDependenciesCreatesFSChain() throws {
    let server = MCPServer()
    _ = try send(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_create","arguments":{"title":"相关性项目","projectStart":"2026-11-02T00:00:00Z"}}}"#
    )
    let a = try send(
        server,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"前驱","durationDays":2}}}"#
    )
    let aID = try #require(try toolResult(a).objectValue?["taskID"]?.stringValue)
    let b = try send(
        server,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"后继","durationDays":3,"dependencies":[{"predecessorID":"\#(aID)","type":"fs"}]}}}"#
    )
    let bID = try #require(try toolResult(b).objectValue?["taskID"]?.stringValue)

    let get = try send(
        server,
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"task_get","arguments":{"taskID":"\#(bID)"}}}"#
    )
    let deps = try toolResult(get).objectValue?["dependencies"]?.arrayValue ?? []
    #expect(deps.count == 1)
    #expect(deps.first?.objectValue?["predecessorID"]?.stringValue == aID)
    #expect(deps.first?.objectValue?["type"]?.stringValue == "fs")

    // 排期传播：后继的开始应等于前驱的结束。
    let schedule = try send(
        server,
        #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"schedule_compute","arguments":{"projectStart":"2026-11-02T00:00:00Z"}}}"#
    )
    let scheduled = try toolResult(schedule).objectValue?["tasks"]?.arrayValue ?? []
    let aEntry = scheduled.first { $0.objectValue?["taskID"]?.stringValue == aID }
    let bEntry = scheduled.first { $0.objectValue?["taskID"]?.stringValue == bID }
    #expect(bEntry?.objectValue?["scheduledStart"]?.stringValue == aEntry?.objectValue?["scheduledFinish"]?.stringValue)
}

// MARK: - 错误契约

@Test func unknownMethodReturnsJSONRPCError() throws {
    let server = MCPServer()
    let response = try send(server, #"{"jsonrpc":"2.0","id":9,"method":"frobnicate"}"#)
    let errorCode = response.objectValue?["error"]?.objectValue?["code"]?.doubleValue
    #expect(errorCode == Double(JSONRPCErrorCode.methodNotFound))
    #expect(response.objectValue?["error"]?.objectValue?["message"]?.stringValue?.contains("未知方法") == true)
}

@Test func toolErrorReturnsIsErrorWithStructuredCode() throws {
    let server = MCPServer()
    // 未打开项目时 task_get 应返回 isError=true + 结构化错误码。
    let response = try send(
        server,
        #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"task_get","arguments":{"taskID":"\#(UUID().uuidString)"}}}"#
    )
    let result = response.objectValue?["result"]?.objectValue
    #expect(result?["isError"]?.boolValue == true)
    let text = result?["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue ?? "{}"
    let failure = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    #expect(failure.objectValue?["code"]?.stringValue == "project_not_open")
    #expect(failure.objectValue?["message"]?.stringValue != nil)
}

@Test func statusBatchUpdateReportsPerTaskSuccessAndFailure() throws {
    let server = MCPServer()
    _ = try send(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_create","arguments":{"title":"批量回写"}}}"#
    )
    let a = try send(server, #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"任务一"}}}"#)
    let aID = try #require(try toolResult(a).objectValue?["taskID"]?.stringValue)
    let b = try send(server, #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"任务二"}}}"#)
    let bID = try #require(try toolResult(b).objectValue?["taskID"]?.stringValue)
    let missing = UUID().uuidString

    let response = try send(
        server,
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"status_batch_update","arguments":{"tasks":[{"taskID":"\#(aID)","status":"done"},{"taskID":"\#(bID)","progress":0.5},{"taskID":"\#(missing)","status":"done"}]}}}"#
    )
    let result = try toolResult(response)
    #expect(result.objectValue?["succeeded"]?.doubleValue == 2)
    #expect(result.objectValue?["failed"]?.doubleValue == 1)
    let entries = result.objectValue?["entries"]?.arrayValue ?? []
    #expect(entries.count == 3)
    #expect(entries.last?.objectValue?["ok"]?.boolValue == false)
    #expect(entries.last?.objectValue?["error"]?.stringValue != nil)
}

@Test func resourceAddThenListRoundTrip() throws {
    let server = MCPServer()
    _ = try send(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_create","arguments":{"title":"资源项目"}}}"#
    )
    let add = try send(
        server,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"resource_add","arguments":{"name":"李工","kind":"person","units":1,"efficiency":0.9}}}"#
    )
    let id = try #require(try toolResult(add).objectValue?["resourceID"]?.stringValue)
    let list = try send(
        server,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"resource_list","arguments":{}}}"#
    )
    let resources = try toolResult(list).objectValue?["resources"]?.arrayValue ?? []
    #expect(resources.count == 1)
    #expect(resources.first?.objectValue?["id"]?.stringValue == id)
    #expect(resources.first?.objectValue?["name"]?.stringValue == "李工")
    #expect(resources.first?.objectValue?["efficiency"]?.doubleValue == 0.9)
}

@Test func taskAssignmentDrivesDurationFromEffort() throws {
    let server = MCPServer()
    _ = try send(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_create","arguments":{"title":"投入换算"}}}"#
    )
    let res = try send(
        server,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"resource_add","arguments":{"name":"李工","efficiency":1}}}"#
    )
    let resourceID = try #require(try toolResult(res).objectValue?["resourceID"]?.stringValue)
    let task = try send(
        server,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"受分配任务","effortHours":8,"assignments":[{"resourceID":"\#(resourceID)","units":1}]}}}"#
    )
    _ = try #require(try toolResult(task).objectValue?["taskID"]?.stringValue)

    let schedule = try send(
        server,
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"schedule_compute","arguments":{"projectStart":"2026-11-02T00:00:00Z"}}}"#
    )
    let scheduled = try toolResult(schedule).objectValue?["tasks"]?.arrayValue ?? []
    // duration = 8h / 8h 每日 / (1 单位 × 100% 效率) = 1 天。
    #expect(scheduled.first?.objectValue?["durationDays"]?.doubleValue == 1)
}

// MARK: - Sprint 2 工具（schedule / violations / status）

@Test func scheduleComputeReportsConstraintConflictThenViolationsList() throws {
    let server = MCPServer()
    _ = try send(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_create","arguments":{"title":"排期项目"}}}"#
    )
    // 任务 A：持续 5 天；任务 B：开始不晚于项目开始后 2 天（D0+2），与前驱冲突。
    let a = try send(
        server,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"任务 A","durationDays":5}}}"#
    )
    let aID = try #require(try toolResult(a).objectValue?["taskID"]?.stringValue)
    let b = try send(
        server,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"任务 B","durationDays":1,"constraint":"startNoEarlierThan:2026-11-09T00:00:00Z"}}}"#
    )
    _ = try #require(try toolResult(b).objectValue?["taskID"]?.stringValue)

    let schedule = try send(
        server,
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"schedule_compute","arguments":{"projectStart":"2026-11-02T00:00:00Z","projectEnd":"2026-11-08T00:00:00Z"}}}"#
    )
    let result = try toolResult(schedule)
    let tasks = result.objectValue?["tasks"]?.arrayValue ?? []
    #expect(tasks.count == 2)
    #expect(tasks.allSatisfy { $0.objectValue?["scheduledStart"]?.stringValue != nil })

    // 任务 A 持续 5 天 → 结束 D0+5（2026-11-07）> 项目结束 D0+6（2026-11-08）？不：D0+5=11-07 < 11-08。任务 B 时限与相关性冲突。
    let violations = try send(
        server,
        #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"violations_list","arguments":{}}}"#
    )
    let vres = try toolResult(violations)
    let vs = vres.objectValue?["violations"]?.arrayValue ?? []
    let vcodes = vs.compactMap { $0.objectValue?["code"]?.stringValue }
    #expect(!vcodes.isEmpty)
    _ = aID
}

@Test func statusUpdateDoneReturnsCompletedAtAndGroupAggregate() throws {
    let server = MCPServer()
    _ = try send(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_create","arguments":{"title":"回写项目"}}}"#
    )
    let g = try send(
        server,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"群组 G","kind":"group"}}}"#
    )
    let gID = try #require(try toolResult(g).objectValue?["taskID"]?.stringValue)
    let c = try send(
        server,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"子一","parentID":"\#(gID)","effortHours":4}}}"#
    )
    let cID = try #require(try toolResult(c).objectValue?["taskID"]?.stringValue)

    let up = try send(
        server,
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"status_update","arguments":{"taskID":"\#(cID)","status":"done"}}}"#
    )
    let updated = try toolResult(up)
    #expect(updated.objectValue?["status"]?.stringValue == "done")
    #expect(updated.objectValue?["progress"]?.doubleValue == 1)
    #expect(updated.objectValue?["completedAt"]?.stringValue != nil)

    // 只读查询群组聚合（不传 status/progress）。
    let gread = try send(
        server,
        #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"status_update","arguments":{"taskID":"\#(gID)"}}}"#
    )
    let gres = try toolResult(gread)
    #expect(gres.objectValue?["groupProgress"]?.doubleValue == 1)
}

// MARK: - 负责人字段契约（US-E1-02-A1~A3，2026-10-19 冻结，RED）
// 冻结判据见 docs/01-prd.md「US-E1-02」小节末「验收判据（2026-10-19 补充：负责人字段）」。
// 命名前缀 usE102A<判据号>_。
// A4（收紧措辞后）只覆盖 CLI 侧 rejectUnknown 白名单子命令的回归，由现有用例覆盖，不重复：
// - task list：CLITests.swift 的 taskListRejectsUnknownOptions；
// - task update：CLITests.swift 的 RouteErrorTests。
// task add 未知标志静默忽略为顺延项，不在本版测试范围内。

/// 建临时工作目录（CLI 用例用），返回目录与 .kairo 路径；调用方用 defer 清理。
private func makeScratchDir() throws -> (dir: URL, kairo: URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("kairo-interface-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return (dir: dir, kairo: dir.appendingPathComponent("demo.kairo"))
}

/// stdout 捕获的进程级互斥锁。
/// fd 1 是进程级全局资源：并行用例同时进入捕获时，一方的 dup(1) 可能指向另一方的管道
/// 写端；后者恢复 fd 1 到该写端时其读端已关闭，随后任何 stdout 写入都会触发
/// SIGPIPE（signal 13）。锁必须覆盖 dup2 → body → 恢复 fd 1 → 关闭写端 全程，
/// 使捕获窗口不重叠。本函数不得嵌套调用（NSLock 非递归）。
private let stdoutCaptureLock = NSLock()

/// 捕获闭包内 print 写入 stdout 的文本（断言 CLI 文本输出用）。
/// 通过 dup2 把 fd 1 重定向到管道，并把 stdout 设为无缓冲，保证 print 立即落管；
/// 读之前先恢复 fd 1、关闭写端，避免 readToEnd 因残留写引用而阻塞。
func captureStdout(_ body: () throws -> Void) throws -> String {
    stdoutCaptureLock.lock()
    defer { stdoutCaptureLock.unlock() }

    let pipe = Pipe()
    let savedFD = dup(FileHandle.standardOutput.fileDescriptor)
    dup2(pipe.fileHandleForWriting.fileDescriptor, FileHandle.standardOutput.fileDescriptor)
    setvbuf(stdout, nil, _IONBF, 0)

    var thrown: Error?
    do {
        try body()
    } catch {
        thrown = error
    }
    fflush(stdout)
    dup2(savedFD, FileHandle.standardOutput.fileDescriptor)
    close(savedFD)
    pipe.fileHandleForWriting.closeFile()

    if let thrown { throw thrown }
    return String(decoding: try pipe.fileHandleForReading.readToEnd() ?? Data(), as: UTF8.self)
}

// US-E1-02-A1：CLI task add --assignee 创建后 assignee 生效，task list --json 输出该值。
@Test func usE102A1_cliTaskAddWithAssigneePersists() throws {
    let scratch = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: scratch.dir) }
    let file = scratch.kairo

    try CLIRouter.execute(arguments: ["project", "create", "负责人 CLI 添加", "--file", file.path])
    try CLIRouter.execute(arguments: [
        "task", "add", "负责人任务", "--assignee", "dev-coder-core", "--file", file.path,
    ])

    let project = try KairoFile.load(from: file)
    let task = try #require(project.tasks.first { $0.title == "负责人任务" })
    #expect(task.assignee == "dev-coder-core")
    // task list --json 输出该值（US-E1-02-A1 输出要求）。
    let json = try CLIOutput.taskListJSON([task])
    #expect(json.contains("\"assignee\":\"dev-coder-core\""))
    // task get 文本输出含负责人行（US-E1-02-A1 输出要求，HIGH-1）。
    let detail = try captureStdout {
        try CLIRouter.execute(arguments: ["task", "get", task.id.uuidString, "--file", file.path])
    }
    #expect(detail.contains("负责人：dev-coder-core"))
}

// US-E1-02-A2：CLI task update --assignee 生效；--assignee "" 清空为 nil。
@Test func usE102A2_cliTaskUpdateAssigneePersistsAndClears() throws {
    let scratch = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: scratch.dir) }
    let file = scratch.kairo

    try CLIRouter.execute(arguments: ["project", "create", "负责人 CLI 更新", "--file", file.path])
    try CLIRouter.execute(arguments: ["task", "add", "待更新任务", "--file", file.path])
    let id = try #require(try KairoFile.load(from: file).tasks.first).id

    try CLIRouter.execute(arguments: [
        "task", "update", id.uuidString, "--assignee", "dev-coder-core", "--file", file.path,
    ])
    var task = try #require(try KairoFile.load(from: file).tasks.first)
    #expect(task.assignee == "dev-coder-core")

    // 空字符串清空 → assignee 变 nil。
    try CLIRouter.execute(arguments: [
        "task", "update", id.uuidString, "--assignee", "", "--file", file.path,
    ])
    task = try #require(try KairoFile.load(from: file).tasks.first)
    #expect(task.assignee == nil)
}

// US-E1-02-A3：MCP task_add 传 assignee 创建后生效。
@Test func usE102A3_mcpTaskAddWithAssigneePersists() throws {
    let server = MCPServer()
    _ = try send(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_create","arguments":{"title":"负责人 MCP 添加"}}}"#
    )
    let add = try send(
        server,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"负责人任务","assignee":"dev-coder-core"}}}"#
    )
    let taskID = try #require(try toolResult(add).objectValue?["taskID"]?.stringValue)

    let get = try send(
        server,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"task_get","arguments":{"taskID":"\#(taskID)"}}}"#
    )
    let got = try toolResult(get)
    #expect(got.objectValue?["assignee"]?.stringValue == "dev-coder-core")
}

// US-E1-02-A3：MCP task_update 传 assignee 生效；传 "" 清空为 nil。
@Test func usE102A3_mcpTaskUpdateAssigneePersistsAndClears() throws {
    let server = MCPServer()
    _ = try send(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_create","arguments":{"title":"负责人 MCP 更新"}}}"#
    )
    let add = try send(
        server,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"task_add","arguments":{"title":"待更新任务"}}}"#
    )
    let taskID = try #require(try toolResult(add).objectValue?["taskID"]?.stringValue)

    let up = try send(
        server,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"task_update","arguments":{"taskID":"\#(taskID)","assignee":"dev-coder-core"}}}"#
    )
    let updated = try toolResult(up)
    #expect(updated.objectValue?["assignee"]?.stringValue == "dev-coder-core")

    // 空字符串清空 → assignee 为 nil，输出不含该键。
    let clear = try send(
        server,
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"task_update","arguments":{"taskID":"\#(taskID)","assignee":""}}}"#
    )
    let cleared = try toolResult(clear)
    #expect(cleared.objectValue?["assignee"] == nil)
}

// MARK: - FR-KAIRO-FMT-6：MCP 报告写入版本与升级来源

@Test func fr_kairo_fmt_6_mcpProjectToolsReportFormatVersion() throws {
    let scratch = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: scratch.dir) }
    let server = MCPServer()
    let current = Double(KairoFile.currentFormatVersion)

    let create = try toolResult(try send(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_create","arguments":{"title":"版本报告"}}}"#
    ))
    #expect(create.objectValue?["formatVersion"]?.doubleValue == current)

    let save = try toolResult(try send(
        server,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"project_save","arguments":{"path":"\#(scratch.kairo.path)"}}}"#
    ))
    #expect(save.objectValue?["formatVersion"]?.doubleValue == current)
    #expect(save.objectValue?["upgradedFrom"] == nil)

    let open = try toolResult(try send(
        server,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"project_open","arguments":{"path":"\#(scratch.kairo.path)"}}}"#
    ))
    // project_open：formatVersion 描述磁盘文件版本；另报当前版本与是否需要升级。
    #expect(open.objectValue?["formatVersion"]?.doubleValue == current)
    #expect(open.objectValue?["currentFormatVersion"]?.doubleValue == current)
    #expect(open.objectValue?["needsUpgrade"]?.boolValue == false)
    #expect(open.objectValue?["upgradedFrom"] == nil)
}

@Test func fr_kairo_fmt_6_mcpOpenReportsDiskVersionAndUpgradeNeed() throws {
    // current == 1 时磁盘上不存在合法旧文件；经会话接缝构造来源版本 0，校验 open 结果组装。
    let session = KairoSession()
    let project = Project()
    project.metadata.title = "旧格式会话"
    session.adoptProject(
        project,
        from: URL(fileURLWithPath: "/tmp/kairo-old-source.kairo"),
        formatVersion: 0
    )
    let opened = try #require(
        ProjectResults.opened(project.metadata, sourceFormatVersion: session.sourceFormatVersion)
            .objectValue
    )
    #expect(opened["formatVersion"]?.doubleValue == 0)
    #expect(opened["currentFormatVersion"]?.doubleValue == Double(KairoFile.currentFormatVersion))
    #expect(opened["needsUpgrade"]?.boolValue == true)
    #expect(opened["upgradedFrom"] == nil)
}

@Test func fr_kairo_fmt_6_mcpSaveReportsUpgradedFromWithoutTouchingOriginal() throws {
    let scratch = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: scratch.dir) }
    let original = scratch.kairo
    let target = scratch.dir.appendingPathComponent("upgraded.kairo")
    // 原文件先以当前版本落盘，用于校验「保存到其他路径不改动原文件」。
    try KairoFile.save(Project(), to: original)
    let originalBytes = try Data(contentsOf: original)

    // 合成旧来源版本（current == 1 时磁盘上不存在合法旧文件，故经会话接缝构造）。
    let session = KairoSession()
    let project = Project()
    project.metadata.title = "旧格式会话"
    session.adoptProject(project, from: original, formatVersion: 0)
    let server = MCPServer(session: session)

    let save = try toolResult(try send(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_save","arguments":{"path":"\#(target.path)"}}}"#
    ))
    #expect(save.objectValue?["formatVersion"]?.doubleValue == Double(KairoFile.currentFormatVersion))
    #expect(save.objectValue?["upgradedFrom"]?.doubleValue == 0)
    #expect(save.objectValue?["path"]?.stringValue == target.path)
    #expect(try Data(contentsOf: original) == originalBytes)
}
