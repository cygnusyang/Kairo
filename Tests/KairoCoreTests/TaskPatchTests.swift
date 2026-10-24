import Foundation
import Testing
@testable import KairoCore
import KairoCommands

// MARK: - 夹具数据（用户数据，不翻译；断言与构造共用同一常量）
private let b0Fixture1 = "备注"
private let b0Fixture2 = "新标题"
private let b0Fixture3 = "设计"

// 任务补丁（ADR-013）：unchanged / set / clear，状态与进度统一回写。

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c.date(from: DateComponents(year: y, month: m, day: d))!
}

private func makeSession() throws -> (KairoSession, UUID) {
    let session = KairoSession()
    try session.createProject(title: "补丁")
    let id = try session.addTask(
        title: "任务",
        startDate: day(2026, 11, 1),
        dueDate: day(2026, 12, 1),
        assignee: "Alice"
    )
    return (session, id)
}

struct TaskPatchTests {
    @Test func addTaskCarriesDatesAndAssignee() throws {
        let (session, id) = try makeSession()
        let task = try session.getTask(id: id)

        #expect(task.startDate == day(2026, 11, 1))
        #expect(task.dueDate == day(2026, 12, 1))
        #expect(task.assignee == "Alice")
    }

    @Test func unchangedPatchLeavesTaskIntact() throws {
        let (session, id) = try makeSession()
        let before = try session.getTask(id: id)

        let after = try session.updateTask(id: id, patch: TaskPatch())

        #expect(after == before)
    }

    @Test func patchUpdatesPlainFields() throws {
        let (session, id) = try makeSession()
        var patch = TaskPatch()
        patch.title = b0Fixture2
        patch.notes = b0Fixture1
        patch.priority = .high
        patch.tags = [b0Fixture3]

        let task = try session.updateTask(id: id, patch: patch)

        #expect(task.title == b0Fixture2)
        #expect(task.notes == b0Fixture1)
        #expect(task.priority == .high)
        #expect(task.tags == [b0Fixture3])
    }

    @Test func clearRemovesOptionalValues() throws {
        let (session, id) = try makeSession()
        var patch = TaskPatch()
        patch.dueDate = .clear
        patch.assignee = .clear
        patch.startDate = .clear

        let task = try session.updateTask(id: id, patch: patch)

        #expect(task.dueDate == nil)
        #expect(task.assignee == nil)
        #expect(task.startDate == nil)
    }

    @Test func setReplacesOptionalValues() throws {
        let (session, id) = try makeSession()
        var patch = TaskPatch()
        patch.assignee = .set("Bob")
        patch.effortHours = .set(8)

        let task = try session.updateTask(id: id, patch: patch)

        #expect(task.assignee == "Bob")
        #expect(task.effortHours == 8)
    }

    // D-004：assignee 输入 trim；纯空白按清空（nil）处理（会话层集中归一）。
    @Test func patchAssigneeTrimsWhitespaceAndClearsWhenBlank() throws {
        let (session, id) = try makeSession()

        var patch = TaskPatch()
        patch.assignee = .set("  Bob  ")
        let task = try session.updateTask(id: id, patch: patch)
        #expect(task.assignee == "Bob")

        patch = TaskPatch()
        patch.assignee = .set("   ")
        let cleared = try session.updateTask(id: id, patch: patch)
        #expect(cleared.assignee == nil)
    }

    @Test func addTaskAssigneeTrimsWhitespaceToNil() throws {
        let session = KairoSession()
        try session.createProject(title: "trim")
        let id = try session.addTask(title: "任务", assignee: "   ")
        #expect(try session.getTask(id: id).assignee == nil)
    }

    @Test func legacyUpdateTaskAssigneeTrimsWhitespace() throws {
        let (session, id) = try makeSession()
        let task = try session.updateTask(id: id, assignee: "  Mei  ")
        #expect(task.assignee == "Mei")
        let cleared = try session.updateTask(id: id, assignee: "  ")
        #expect(cleared.assignee == nil)
        // 不传（nil）= 不改。
        let untouched = try session.updateTask(id: id)
        #expect(untouched.assignee == nil)
    }

    @Test func statusDoneSetsProgressAndCompletedAt() throws {
        let (session, id) = try makeSession()
        var patch = TaskPatch()
        patch.status = .done

        let task = try session.updateTask(id: id, patch: patch)

        #expect(task.status == .done)
        #expect(task.progress == 1)
        #expect(task.completedAt != nil)
    }

    @Test func leavingDoneClearsCompletedAt() throws {
        let (session, id) = try makeSession()
        _ = try session.statusUpdate(id: id, status: .done)

        let task = try session.statusUpdate(id: id, status: .inProgress)

        #expect(task.completedAt == nil)
    }

    @Test func fullProgressMarksDone() throws {
        let (session, id) = try makeSession()

        let task = try session.statusUpdate(id: id, progress: 1)

        #expect(task.status == .done)
        #expect(task.progress == 1)
        #expect(task.completedAt != nil)
    }

    @Test func patchRejectsOutOfRangeProgress() throws {
        let (session, id) = try makeSession()
        var patch = TaskPatch()
        patch.progress = 1.5

        #expect(throws: SessionError.self) {
            try session.updateTask(id: id, patch: patch)
        }
    }

    @Test func patchValidatesParentExists() throws {
        let (session, id) = try makeSession()
        var patch = TaskPatch()
        patch.parentID = .set(UUID())

        #expect(throws: SessionError.self) {
            try session.updateTask(id: id, patch: patch)
        }
    }

    @Test func patchRejectsSelfParent() throws {
        let (session, id) = try makeSession()
        var patch = TaskPatch()
        patch.parentID = .set(id)

        #expect(throws: SessionError.self) {
            try session.updateTask(id: id, patch: patch)
        }
    }

    @Test func patchRejectsMovingIntoOwnSubtree() throws {
        let session = KairoSession()
        try session.createProject(title: "环")
        let a = try session.addTask(title: "A")
        let b = try session.addTask(title: "B", parentID: a)
        let c = try session.addTask(title: "C", parentID: b)
        var patch = TaskPatch()
        patch.parentID = .set(c)

        #expect(throws: SessionError.self) {
            try session.updateTask(id: a, patch: patch)
        }
        #expect(throws: SessionError.self) {
            try session.updateTask(id: a, parentID: c)
        }
        #expect(try session.getTask(id: a).parentID == nil)
    }

    @Test func movingUnderPlainTaskPromotesParentToGroup() throws {
        let session = KairoSession()
        try session.createProject(title: "群组提升")
        let parent = try session.addTask(title: "父")
        let child = try session.addTask(title: "子")
        var patch = TaskPatch()
        patch.parentID = .set(parent)

        try session.updateTask(id: child, patch: patch)

        #expect(try session.getTask(id: parent).kind == .group)
    }

    @Test func demotingTaskWithChildrenIsRejected() throws {
        let session = KairoSession()
        try session.createProject(title: "类型")
        let parent = try session.addTask(title: "群组", kind: .group)
        _ = try session.addTask(title: "子", parentID: parent)
        var patch = TaskPatch()
        patch.kind = .task

        #expect(throws: SessionError.self) {
            try session.updateTask(id: parent, patch: patch)
        }
        #expect(throws: SessionError.self) {
            try session.updateTask(id: parent, kind: .task)
        }
        #expect(try session.getTask(id: parent).kind == .group)
    }
}
