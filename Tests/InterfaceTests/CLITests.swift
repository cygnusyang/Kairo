import Foundation
import Testing
import KairoCore
import KairoCommands
@testable import KairoCLI

// CLI 对等性契约测试（US-E5-05 / ADR-005）：路由解析与 KairoSession 往返。
// MCP 侧对应测试见 InterfaceTests.swift；两接口层共享同一命令层契约。

// MARK: - 参数与枚举解析（路由级）

struct OptionsParsingTests {
    @Test func operandsAndFlagValues() throws {
        // 路由已剥离子命令，Options 只接收操作数与选项。
        let o = Options(["标题", "--kind", "group", "--effort", "8"])
        #expect(try o.operand(0, name: "标题") == "标题")
        #expect(o.value(for: "--kind") == "group")
        #expect(o.double(for: "--effort") == 8)
        #expect(o.value(for: "--parent") == nil)
    }

    @Test func repeatedDependencyValues() throws {
        let idA = UUID().uuidString
        let idB = UUID().uuidString
        let o = Options(["add", "任务", "--dep", "\(idA):fs", "--dep", "\(idB):ff:2"])
        let specs = o.values(for: "--dep")
        #expect(specs == ["\(idA):fs", "\(idB):ff:2"])
    }

    @Test func enumsParseValidKinds() throws {
        #expect(try CLIEnums.kind("task") == .task)
        #expect(try CLIEnums.kind("group") == .group)
        #expect(try CLIEnums.kind("milestone") == .milestone)
        #expect(try CLIEnums.kind(nil) == nil)
    }

    @Test func enumsRejectInvalidValues() throws {
        #expect(throws: UsageError.self) { _ = try CLIEnums.kind("gantt") }
        #expect(throws: CLIError.self) { _ = try CLIEnums.priority("urgent") }
        #expect(throws: CLIError.self) { _ = try CLIEnums.status("paused") }
        #expect(try CLIEnums.priority("critical") == .critical)
        #expect(try CLIEnums.status("in_progress") == .inProgress)
    }

    @Test func dependencySpecParsesTypeAndLag() throws {
        let id = UUID()
        let spec = try CLIEnums.dependency("\(id.uuidString):ff:2")
        #expect(spec.predecessor == id.uuidString)
        #expect(spec.type == .ff)
        #expect(spec.lagDays == 2)
    }

    @Test func dependencySpecAcceptsShortPrefix() throws {
        // 前缀在会话打开后解析：此处只验证规格解析不因短标识失败。
        let spec = try CLIEnums.dependency("A1B2C3D4:fs")
        #expect(spec.predecessor == "A1B2C3D4")
        #expect(spec.type == .fs)
        #expect(spec.lagDays == 0)
    }

    @Test func dependencySpecDefaultsToFSNoLag() throws {
        let id = UUID()
        let dep = try CLIEnums.dependency(id.uuidString)
        #expect(dep.type == .fs)
        #expect(dep.lagDays == 0)
    }

    @Test func dependencySpecRejectsBadTypeAndEmptyPredecessor() throws {
        // 前驱标识接受完整 UUID 或前缀，故只校验类型与空标识。
        #expect(throws: CLIError.self) {
            _ = try CLIEnums.dependency("\(UUID().uuidString):xx")
        }
        #expect(throws: CLIError.self) { _ = try CLIEnums.dependency(":fs") }
    }

    @Test func assignmentSpecParsesPrefixAndUnits() throws {
        let spec = try CLIEnums.assignment("A1B2C3D4")
        #expect(spec.resource == "A1B2C3D4")
        #expect(spec.units == 1)

        let half = try CLIEnums.assignment("A1B2C3D4:0.5")
        #expect(half.units == 0.5)

        #expect(throws: UsageError.self) { _ = try CLIEnums.assignment(":2") }
        #expect(throws: UsageError.self) { _ = try CLIEnums.assignment("A1B2C3D4:0") }
        #expect(throws: UsageError.self) { _ = try CLIEnums.assignment("A1B2C3D4:abc") }
    }

    @Test func schedulingPolicyAndConstraintParse() throws {
        #expect(try CLIEnums.schedulingPolicy("alap") == .alap)
        #expect(try CLIEnums.schedulingPolicy(nil) == nil)
        #expect(throws: UsageError.self) { _ = try CLIEnums.schedulingPolicy("soon") }

        let constraint = try CLIEnums.constraint("startNoLaterThan:2026-11-05T00:00:00Z")
        guard case .startNoLaterThan(let date) = constraint else {
            Issue.record("应解析为 startNoLaterThan")
            return
        }
        #expect(ISO8601DateFormatter().string(from: date) == "2026-11-05T00:00:00Z")
        #expect(try CLIEnums.constraint(nil) == nil)
        #expect(throws: UsageError.self) { _ = try CLIEnums.constraint("bad-spec") }
    }
}

// MARK: - 端到端路由（临时目录内 create → import → list）

struct RouteTests {
    /// 建临时工作目录，返回目录与其中的两个路径（.kairo 与 wbs.json）。
    /// 调用方用 defer 在测试结束后清理目录。
    private func makeScratch() throws -> (dir: URL, kairo: URL, wbs: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (
            dir: dir,
            kairo: dir.appendingPathComponent("demo.kairo"),
            wbs: dir.appendingPathComponent("wbs.json")
        )
    }

    @Test func projectCreateThenWBSImportPersistsTree() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo

        try CLIRouter.execute(arguments: ["project", "create", "演示项目", "--file", file.path])

        let wbs = #"""
        [
          {"title": "设计", "children": [
            {"title": "原型"},
            {"title": "评审"}
          ]},
          {"title": "开发", "kind": "group", "children": [
            {"title": "后端", "kind": "milestone"}
          ]}
        ]
        """#
        try Data(wbs.utf8).write(to: scratch.wbs)
        try CLIRouter.execute(arguments: ["wbs", "import", scratch.wbs.path, "--file", file.path])

        let project = try KairoFile.load(from: file)
        #expect(project.metadata.title == "演示项目")
        #expect(project.tasks.count == 5)
        // 层级：设计(根) → 原型/评审；开发(根) → 后端。
        let design = try #require(project.tasks.first { $0.title == "设计" })
        let dev = try #require(project.tasks.first { $0.title == "开发" })
        let proto = try #require(project.tasks.first { $0.title == "原型" })
        #expect(design.kind == .group)
        #expect(design.parentID == nil)
        #expect(proto.parentID == design.id)
        #expect(dev.kind == .group)
        #expect(try #require(project.tasks.first { $0.title == "后端" }).kind == .milestone)
    }

    @Test func taskAddWithDependencyThenGetRoundTrip() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo

        try CLIRouter.execute(arguments: ["project", "create", "依赖演示", "--file", file.path])
        try CLIRouter.execute(arguments: ["task", "add", "前驱任务", "--file", file.path])

        var project = try KairoFile.load(from: file)
        let predecessor = try #require(project.tasks.first)
        try CLIRouter.execute(arguments: [
            "task", "add", "后继任务",
            "--dep", "\(predecessor.id.uuidString):ff:2",
            "--priority", "high",
            "--effort", "8",
            "--file", file.path,
        ])

        project = try KairoFile.load(from: file)
        let successor = try #require(project.tasks.first { $0.title == "后继任务" })
        #expect(successor.dependencies.count == 1)
        #expect(successor.dependencies.first?.predecessorID == predecessor.id)
        #expect(successor.dependencies.first?.type == .ff)
        #expect(successor.dependencies.first?.lagDays == 2)
        #expect(successor.priority == .high)
        #expect(successor.effortHours == 8)

        try CLIRouter.execute(arguments: ["task", "get", predecessor.id.uuidString, "--file", file.path])
    }

    @Test func taskUpdateProgressAndStatus() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo

        try CLIRouter.execute(arguments: ["project", "create", "更新演示", "--file", file.path])
        try CLIRouter.execute(arguments: ["task", "add", "进行中的任务", "--file", file.path])
        let project0 = try KairoFile.load(from: file)
        let id = try #require(project0.tasks.first).id

        try CLIRouter.execute(arguments: [
            "task", "update", id.uuidString,
            "--status", "in_progress",
            "--progress", "0.6",
            "--tags", "后端, 搜索",
            "--file", file.path,
        ])

        let project = try KairoFile.load(from: file)
        let task = try #require(project.tasks.first)
        #expect(task.status == .inProgress)
        #expect(task.progress == 0.6)
        #expect(task.tags == ["后端", "搜索"])
    }

    @Test func taskListSupportsParentFilter() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo

        try CLIRouter.execute(arguments: ["project", "create", "列表演示", "--file", file.path])
        let wbs = #"[{"title": "群组A", "children": [{"title": "子一"}, {"title": "子二"}]}]"#
        try Data(wbs.utf8).write(to: scratch.wbs)
        try CLIRouter.execute(arguments: ["wbs", "import", scratch.wbs.path, "--file", file.path])

        let project = try KairoFile.load(from: file)
        let group = try #require(project.tasks.first { $0.title == "群组A" })
        try CLIRouter.execute(arguments: ["task", "list", "--parent", group.id.uuidString, "--file", file.path])
    }

    @Test func taskAddAcceptsParentIDPrefix() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo

        try CLIRouter.execute(arguments: ["project", "create", "前缀演示", "--file", file.path])
        let wbs = #"[{"title": "群组B", "children": []}]"#
        try Data(wbs.utf8).write(to: scratch.wbs)
        try CLIRouter.execute(arguments: ["wbs", "import", scratch.wbs.path, "--file", file.path])

        let project0 = try KairoFile.load(from: file)
        let group = try #require(project0.tasks.first { $0.title == "群组B" })
        let prefix = String(group.id.uuidString.prefix(8))
        try CLIRouter.execute(arguments: [
            "task", "add", "子任务", "--parent", prefix, "--file", file.path,
        ])

        let project = try KairoFile.load(from: file)
        let child = try #require(project.tasks.first { $0.title == "子任务" })
        #expect(child.parentID == group.id)
    }

    @Test func taskUpdatePersistsDateOnlyConstraint() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo

        try CLIRouter.execute(arguments: ["project", "create", "时限演示", "--file", file.path])
        try CLIRouter.execute(arguments: ["task", "add", "受时限任务", "--file", file.path])
        let id = try #require(try KairoFile.load(from: file).tasks.first).id

        try CLIRouter.execute(arguments: [
            "task", "update", id.uuidString,
            "--constraint", "startNoLaterThan:2026-11-04",
            "--file", file.path,
        ])

        let task = try #require(try KairoFile.load(from: file).tasks.first)
        #expect(task.constraint != nil)
        if case .startNoLaterThan = task.constraint {
            // 通过
        } else {
            Issue.record("时限类型应为 startNoLaterThan")
        }
    }
}

// MARK: - 错误契约与退出码

struct RouteErrorTests {
    @Test func unknownCommandThrowsUsageError() {
        #expect(throws: UsageError.self) {
            try CLIRouter.execute(arguments: ["frobnicate", "x"])
        }
    }

    @Test func missingOperandThrowsUsageError() {
        #expect(throws: UsageError.self) {
            try CLIRouter.execute(arguments: ["task", "get"])
        }
    }

    @Test func taskOnMissingFileReturnsRuntimeExitCode() throws {
        let code = CLIRouter.run(arguments: [
            "task", "list", "--file", "/nonexistent/kairo/demo.kairo",
        ])
        #expect(code == 1)
    }

    @Test func unknownCommandReturnsUsageExitCode() {
        #expect(CLIRouter.run(arguments: ["nope", "x"]) == 2)
    }

    @Test func updateRejectsMalformedDependencySpec() {
        // 相关性类型非法 → 用法错误（退出码 2），在 IO 前抛出。
        let code = CLIRouter.run(arguments: ["task", "update", UUID().uuidString, "--dep", "x:zz"])
        #expect(code == 2)
    }

    @Test func updateAcceptsWellFormedDependencySpec() {
        // 合法规格通过参数解析，随后因文件不存在以运行期错误退出（1），
        // 证明 --dep 已被 update 接受（不再是用例错误）。
        let pred = UUID().uuidString
        let code = CLIRouter.run(arguments: [
            "task", "update", UUID().uuidString,
            "--dep", "\(pred):fs:1",
            "--file", "/nonexistent/kairo/demo.kairo",
        ])
        #expect(code == 1)
    }
}

// MARK: - JSON 输出（US-E5-02 验收 2 / 插件完成 hook）

struct CLIJSONTests {
    @Test func flagDetection() {
        let o = Options(["task", "list", "--json", "--file", "x.kairo"])
        #expect(o.flag("--json"))
        #expect(!o.flag("--pretty"))
    }

    @Test func taskListJSONEncodesStableFields() throws {
        let parentID = UUID()
        let task = TaskItem(
            title: "接口设计",
            status: .done,
            tags: ["设计"],
            kind: .task,
            parentID: parentID,
            durationDays: 2,
            progress: 1
        )
        let json = try CLIOutput.taskListJSON([task])
        // 钉住 hook 消费的字面字段，防止 key 名或 enum 编码漂移。
        #expect(json.contains("\"title\":\"接口设计\""))
        #expect(json.contains("\"status\":\"done\""))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([TaskItem].self, from: Data(json.utf8))
        let item = try #require(decoded.first)
        #expect(item.id == task.id)
        #expect(item.title == "接口设计")
        #expect(item.status == .done)
        #expect(item.parentID == parentID)
        #expect(item.tags == ["设计"])
        #expect(item.progress == 1)
    }

    @Test func taskListRejectsUnknownOptions() {
        // 未知选项必须报用法错误（退出码 2），不能静默退回人类可读输出。
        let code = CLIRouter.run(arguments: [
            "task", "list", "--jsn", "--file", "/nonexistent/kairo/demo.kairo",
        ])
        #expect(code == 2)
    }

    @Test func taskListJSONUsesISODates() throws {
        let date = ISO8601DateFormatter().date(from: "2026-10-18T08:00:00Z")!
        let task = TaskItem(title: "已完成", status: .done, completedAt: date)
        let json = try CLIOutput.taskListJSON([task])
        #expect(json.contains("2026-10-18T08:00:00Z"))
    }
}

// MARK: - Sprint 2 命令（schedule / status / resource）

struct Sprint2CommandTests {
    private func makeScratch() throws -> (dir: URL, kairo: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-cli2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir: dir, kairo: dir.appendingPathComponent("demo.kairo"))
    }

    @Test func scheduleComputeThenStatusUpdatePersistsCompletedAt() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo

        try CLIRouter.execute(arguments: ["project", "create", "闭环演示", "--file", file.path])
        try CLIRouter.execute(arguments: ["task", "add", "任务 A", "--duration", "3", "--file", file.path])
        let groupID = try addTaskID(title: "群组 G", kind: "group", file: file)

        // 排期计算命令（含项目边界）不抛错。
        try CLIRouter.execute(arguments: [
            "schedule", "compute",
            "--start", "2026-11-02T00:00:00Z",
            "--end", "2026-11-16T00:00:00Z",
            "--file", file.path,
        ])
        // 重要路径命令。
        try CLIRouter.execute(arguments: ["schedule", "path", "--file", file.path])
        // 违例命令（此时应无违例）。
        try CLIRouter.execute(arguments: ["violations", "--file", file.path])

        // 状态回写：子任务完成 → completedAt 落盘。
        let childID = try addTaskID(title: "子一", kind: "task", file: file, parentID: groupID, effort: "4")
        try CLIRouter.execute(arguments: [
            "status", "update", childID.uuidString, "--status", "done", "--file", file.path,
        ])
        let project = try KairoFile.load(from: file)
        let child = try #require(project.tasks.first { $0.id == childID })
        #expect(child.status == .done)
        #expect(child.progress == 1)
        #expect(child.completedAt != nil)
    }

    @Test func statusBatchUpdatesMultipleTasksAndReportsSummary() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo
        let batch = scratch.dir.appendingPathComponent("batch.json")

        try CLIRouter.execute(arguments: ["project", "create", "批量演示", "--file", file.path])
        let a = try addTaskID(title: "任务一", kind: "task", file: file)
        let b = try addTaskID(title: "任务二", kind: "task", file: file)
        let payload = #"""
        [
          {"taskID": "\#(String(a.uuidString.prefix(8)))", "status": "done"},
          {"taskID": "\#(b.uuidString)", "progress": 0.5}
        ]
        """#
        try Data(payload.utf8).write(to: batch)

        try CLIRouter.execute(arguments: ["status", "batch", batch.path, "--file", file.path])

        let project = try KairoFile.load(from: file)
        let taskA = try #require(project.tasks.first { $0.id == a })
        let taskB = try #require(project.tasks.first { $0.id == b })
        #expect(taskA.status == .done)
        #expect(taskA.progress == 1)
        #expect(taskA.completedAt != nil)
        #expect(taskB.progress == 0.5)
    }

    @Test func statusBatchWithUnknownTaskExitsWithRuntimeCode() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo
        let batch = scratch.dir.appendingPathComponent("batch.json")

        try CLIRouter.execute(arguments: ["project", "create", "批量失败演示", "--file", file.path])
        let missing = UUID().uuidString
        try Data(#"[{"taskID":"\#(missing)","status":"done"}]"#.utf8).write(to: batch)

        let code = CLIRouter.run(arguments: ["status", "batch", batch.path, "--file", file.path])
        #expect(code == 1)
    }

    @Test func resourceAddAndListPersist() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo

        try CLIRouter.execute(arguments: ["project", "create", "资源演示", "--file", file.path])
        try CLIRouter.execute(arguments: [
            "resource", "add", "李工", "--type", "person", "--units", "1", "--efficiency", "0.9", "--file", file.path,
        ])
        try CLIRouter.execute(arguments: ["resource", "list", "--file", file.path])

        let project = try KairoFile.load(from: file)
        #expect(project.resources.count == 1)
        #expect(project.resources.first?.name == "李工")
        #expect(project.resources.first?.kind == .person)
        #expect(project.resources.first?.efficiency == 0.9)
    }

    @Test func taskAddAndUpdateWithAssignmentByPrefix() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo

        try CLIRouter.execute(arguments: ["project", "create", "分配演示", "--file", file.path])
        try CLIRouter.execute(arguments: ["resource", "add", "李工", "--file", file.path])
        let resourceID = try #require(try KairoFile.load(from: file).resources.first).id
        let prefix = String(resourceID.uuidString.prefix(8))

        try CLIRouter.execute(arguments: [
            "task", "add", "受分配任务",
            "--effort", "16",
            "--assign", "\(prefix):2",
            "--file", file.path,
        ])
        let taskID = try #require(try KairoFile.load(from: file).tasks.first).id
        var task = try #require(try KairoFile.load(from: file).tasks.first)
        #expect(task.assignments.count == 1)
        #expect(task.assignments.first?.resourceID == resourceID)
        #expect(task.assignments.first?.units == 2)

        // 更新：默认单位 1 覆盖原分配。
        try CLIRouter.execute(arguments: [
            "task", "update", taskID.uuidString,
            "--assign", prefix,
            "--file", file.path,
        ])
        task = try #require(try KairoFile.load(from: file).tasks.first)
        #expect(task.assignments.count == 1)
        #expect(task.assignments.first?.units == 1)
    }

    @Test func taskAddWithUnknownResourceFailsAndWritesNothing() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo

        try CLIRouter.execute(arguments: ["project", "create", "悬空分配演示", "--file", file.path])
        let code = CLIRouter.run(arguments: [
            "task", "add", "悬空分配任务",
            "--assign", "DEADBEEF:1",
            "--file", file.path,
        ])
        #expect(code == 2)
        #expect(try KairoFile.load(from: file).tasks.isEmpty)
    }

    private func addTaskID(
        title: String, kind: String, file: URL, parentID: UUID? = nil, effort: String? = nil
    ) throws -> UUID {
        var args = ["task", "add", title, "--kind", kind, "--file", file.path]
        if let parentID { args += ["--parent", parentID.uuidString] }
        if let effort { args += ["--effort", effort] }
        try CLIRouter.execute(arguments: args)
        let project = try KairoFile.load(from: file)
        return try #require(project.tasks.first { $0.title == title }).id
    }

    // MARK: - FR-KAIRO-FMT-6：保存输出格式版本

    @Test func fr_kairo_fmt_6_cliProjectCommandsPrintFormatVersion() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo
        let line = "格式版本：v\(KairoFile.currentFormatVersion)"

        // 语言必须钉死：默认跟随系统/环境，CI 的英文 runner 上中文断言必红。
        let pinned = ["KAIRO_LANG": "zh-Hans"]
        let createOutput = try captureStdout {
            try CLIRouter.execute(
                arguments: ["project", "create", "版本输出", "--file", file.path],
                environment: pinned, preferredLanguages: []
            )
        }
        #expect(createOutput.contains(line))

        let saveOutput = try captureStdout {
            try CLIRouter.execute(
                arguments: ["project", "save", "--file", file.path],
                environment: pinned, preferredLanguages: []
            )
        }
        #expect(saveOutput.contains(line))
        #expect(!saveOutput.contains("已从 v"))

        let openOutput = try captureStdout {
            try CLIRouter.execute(
                arguments: ["project", "open", file.path],
                environment: pinned, preferredLanguages: []
            )
        }
        // project open：报告磁盘文件版本与当前目标版本，不报告升级来源。
        #expect(openOutput.contains("源格式版本：v\(KairoFile.currentFormatVersion)（当前 v\(KairoFile.currentFormatVersion)）"))
        #expect(!openOutput.contains("保存后升级"))
    }

    @Test func fr_kairo_fmt_6_cliSourceVersionLineRendersUpgradeHint() throws {
        let current = KairoFile.currentFormatVersion
        // 显式传 language：默认 .current 跟随系统，CI 英文 runner 上中文断言必红。
        #expect(
            CLIRouter.sourceVersionLine(source: current, current: current, language: .zhHans)
                == "源格式版本：v\(current)（当前 v\(current)）"
        )
        #expect(
            CLIRouter.sourceVersionLine(source: current - 1, current: current, language: .zhHans)
                == "源格式版本：v\(current - 1)（当前 v\(current)），保存后升级"
        )
        // 同一条断言的英文对照：证明本地化真的生效，而不是恒等于中文。
        #expect(
            CLIRouter.sourceVersionLine(source: current - 1, current: current, language: .en)
                == "source format version: v\(current - 1) (current v\(current)), will upgrade on save"
        )
    }

    @Test func fr_kairo_fmt_6_cliFormatVersionLineRendersUpgradeSource() throws {
        let current = KairoFile.currentFormatVersion
        #expect(
            CLIRouter.formatVersionLine(written: current, upgradedFrom: nil, language: .zhHans)
                == "格式版本：v\(current)"
        )
        #expect(
            CLIRouter.formatVersionLine(written: current, upgradedFrom: current, language: .zhHans)
                == "格式版本：v\(current)"
        )
        #expect(
            CLIRouter.formatVersionLine(written: current, upgradedFrom: current - 1, language: .zhHans)
                == "格式版本：v\(current)（已从 v\(current - 1) 升级）"
        )
        // 英文对照：升级来源分支必须本地化。
        #expect(
            CLIRouter.formatVersionLine(written: current, upgradedFrom: current - 1, language: .en)
                == "format version: v\(current) (upgraded from v\(current - 1))"
        )
    }
}
