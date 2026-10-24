import Foundation
import Testing
@testable import KairoCommands
@testable import KairoCore

// F-0703：命令层错误的细粒度码（设计 §A.2）。
//
// 阶段一契约：code 仍是 5 个冻结的粗粒度值（CLI 退出码 / MCP 分类依赖它），
// 新增的 reason 才是细粒度稳定标识——消费者不必再按中文 message 文本匹配。

private func sessionError(_ body: () throws -> Void) -> SessionError? {
    do {
        try body()
        return nil
    } catch let error as SessionError {
        return error
    } catch {
        return nil
    }
}

private func newSession() throws -> KairoSession {
    let session = KairoSession()
    try session.createProject(title: "测试项目")
    return session
}

struct SessionErrorReasonTests {
    @Test func notOpenMapsToSessionProjectNotOpen() {
        let session = KairoSession()
        let error = sessionError { _ = try session.snapshot() }

        #expect(error?.code == .projectNotOpen)
        #expect(error?.reason == .projectNotOpen)
    }

    @Test func missingTaskAndParentCarryModelCodes() throws {
        let session = try newSession()
        let missingTask = sessionError { _ = try session.getTask(id: UUID()) }
        #expect(missingTask?.code == .taskNotFound)
        #expect(missingTask?.reason == .taskNotFound)

        let missingParent = sessionError {
            _ = try session.addTask(title: "子任务", parentID: UUID())
        }
        #expect(missingParent?.code == .invalidArgument)
        #expect(missingParent?.reason == .parentNotFound)
    }

    @Test func progressOutOfRangeIsItsOwnCode() throws {
        let session = try newSession()
        let id = try session.addTask(title: "任务")

        let error = sessionError { _ = try session.statusUpdate(id: id, progress: 1.5) }

        #expect(error?.code == .invalidArgument)
        #expect(error?.reason == .progressOutOfRange)
    }

    @Test func dependencyErrorsKeepTheirOwnCodes() throws {
        let session = try newSession()
        let a = try session.addTask(title: "A")
        let b = try session.addTask(title: "B")

        #expect(sessionError { _ = try session.addDependency(to: a, predecessorID: UUID()) }?.reason
                == .dependencyPredecessorNotFound)
        #expect(sessionError { _ = try session.addDependency(to: a, predecessorID: a) }?.reason
                == .dependencySelf)

        _ = try session.addDependency(to: b, predecessorID: a)
        #expect(sessionError { _ = try session.addDependency(to: a, predecessorID: b) }?.reason
                == .dependencyCycle)
    }

    @Test func resourceValidationUsesResourceCodes() throws {
        let session = try newSession()

        #expect(sessionError { _ = try session.resourceAdd(name: "R", units: 0) }?.reason
                == .resourceUnitInvalid)
        #expect(sessionError { _ = try session.resourceAdd(name: "R", efficiency: -1) }?.reason
                == .resourceEfficiencyInvalid)
    }

    @Test func saveWithoutPathIsNoSavePath() throws {
        let session = try newSession()

        let error = sessionError { _ = try session.saveProject() }

        #expect(error?.code == .invalidArgument)
        #expect(error?.reason == .noSavePath)
    }

    @Test func unreadableFileDistinguishesMalformedVersionFromUnsupported() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let malformed = dir.appendingPathComponent("malformed.kairo")
        try Data("not json".utf8).write(to: malformed)
        let malformedError = sessionError {
            _ = try KairoSession().openProject(at: malformed)
        }
        #expect(malformedError?.code == .fileUnreadable)
        #expect(malformedError?.reason == .malformedFormatVersion)

        let future = dir.appendingPathComponent("future.kairo")
        let payload = """
        {"formatVersion": 99, "project": {"title": "x"}, "tasks": []}
        """
        try Data(payload.utf8).write(to: future)
        let futureError = sessionError {
            _ = try KairoSession().openProject(at: future)
        }
        #expect(futureError?.code == .unsupportedFormat)
        #expect(futureError?.reason == .unsupportedFormat)
    }

    @Test func groupPromotionWarningIsSemantic() throws {
        // 旧数据：有子项但 kind 不是 group → 载入时提升，并留下结构化警告。
        let group = TaskItem(title: "阶段", kind: .task)
        let child = TaskItem(title: "子任务", parentID: group.id)
        let project = Project()
        project.add(group)
        project.add(child)

        let session = KairoSession()
        session.adoptProject(project, from: URL(fileURLWithPath: "/tmp/unused.kairo"))

        let warning = try #require(session.loadWarnings.first)
        #expect(warning.code == .groupPromoted)
        #expect(warning.taskTitle == "阶段")
        #expect(warning.taskID == group.id)
    }
}
