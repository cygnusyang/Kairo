import Foundation
import Testing
@testable import KairoCore
import KairoCommands

// MARK: - 夹具数据（用户数据，不翻译；断言与构造共用同一常量）
private let b0Fixture1 = "原任务"

// 会话缓存失效（ADR-013）：任一写操作置脏，读取排期时按需重算一次。

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

struct SessionCacheTests {
    @Test func addTaskInvalidatesCachedSchedule() throws {
        let session = KairoSession()
        try session.createProject(title: "缓存", projectStart: Date(timeIntervalSince1970: 1_800_000_000))
        let first = try session.addTask(title: "一", durationDays: 2)
        let before = try session.computeSchedule()
        #expect(before.scheduled(first) != nil)

        let second = try session.addTask(title: "二", durationDays: 10)
        let after = try session.computeSchedule()

        #expect(after.scheduled(second) != nil)
        #expect(after.tasks.map(\.scheduledFinish).max()! > before.tasks.map(\.scheduledFinish).max()!)
    }

    @Test func patchInvalidatesCachedSchedule() throws {
        let session = KairoSession()
        try session.createProject(title: "缓存")
        let id = try session.addTask(title: "任务", durationDays: 1)
        let before = try session.computeSchedule()

        var patch = TaskPatch()
        patch.durationDays = .set(20)
        try session.updateTask(id: id, patch: patch)
        let after = try session.computeSchedule()

        #expect(after.scheduled(id)?.durationDays == 20)
        #expect(after.tasks.map(\.scheduledFinish).max()! > before.tasks.map(\.scheduledFinish).max()!)
    }

    @Test func statusUpdateInvalidatesCachedSchedule() throws {
        let session = KairoSession()
        try session.createProject(title: "缓存")
        let id = try session.addTask(title: "任务")
        _ = try session.computeSchedule()

        try session.statusUpdate(id: id, status: .done)

        #expect(session.lastSchedule == nil)
    }

    @Test func hasUnsavedChangesTracksWritesAndSave() throws {
        let session = KairoSession()
        try session.createProject(title: "保存状态")
        #expect(!session.hasUnsavedChanges)

        try session.addTask(title: "任务")
        #expect(session.hasUnsavedChanges)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kairo")
        defer { try? FileManager.default.removeItem(at: url) }
        try session.saveProject(to: url)
        #expect(!session.hasUnsavedChanges)
    }

    @Test func deleteCascadeRemovesSubtreeAndCleansDependencies() throws {
        let session = KairoSession()
        try session.createProject(title: "级联")
        let group = try session.addTask(title: "组", kind: .group)
        let child = try session.addTask(title: "子", parentID: group)
        let grandchild = try session.addTask(title: "孙", parentID: child)
        let other = try session.addTask(title: "其他")
        try session.addDependency(to: other, predecessorID: grandchild)

        let count = try session.deleteTaskCascade(id: group)

        #expect(count == 3)
        #expect(try session.listTasks().map(\.id) == [other])
        #expect(try session.getTask(id: other).dependencies.isEmpty)
    }

    @Test func deletingParentRemovesDescendantsSoNoDanglingParentIDs() throws {
        let session = KairoSession()
        try session.createProject(title: "删除")
        let group = try session.addTask(title: "组", kind: .group)
        _ = try session.addTask(title: "子", parentID: group)
        let other = try session.addTask(title: "其他")

        _ = try session.deleteTask(id: group)

        let tasks = try session.listTasks()
        let ids = Set(tasks.map(\.id))
        #expect(ids == [other])
        #expect(tasks.allSatisfy { task in
            task.parentID.map(ids.contains) ?? true
        })
    }

    @Test func writeOperationsIncrementRevision() throws {
        let session = KairoSession()
        try session.createProject(title: "版本")
        let start = session.revision
        _ = try session.addTask(title: "任务")
        #expect(session.revision > start)
    }

    @Test func restoreReplacesProjectContent() throws {
        let session = KairoSession()
        try session.createProject(title: "快照")
        let id = try session.addTask(title: b0Fixture1)
        let state = try session.snapshot()

        _ = try session.addTask(title: "新增")
        try session.updateTask(id: id, patch: {
            var patch = TaskPatch()
            patch.title = "改名"
            return patch
        }())

        try session.restore(state)

        #expect(try session.listTasks().map(\.title) == [b0Fixture1])
    }
}
