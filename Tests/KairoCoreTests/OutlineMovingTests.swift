import Foundation
import Testing
@testable import KairoCore
import KairoCommands

// MARK: - 夹具数据（用户数据，不翻译；断言与构造共用同一常量）
private let b0Fixture1 = "其他"
private let b0Fixture2 = "子"
private let b0Fixture3 = "孙"
private let b0Fixture4 = "组"

// 单行拖拽重排（ADR-013）：目标父级与索引、子树随行、拒绝移入自身或后代。

private struct Fixture {
    let group = TaskItem(title: b0Fixture4, kind: .group)
    let child: TaskItem
    let grandchild: TaskItem
    let other = TaskItem(title: b0Fixture1)

    init() {
        child = TaskItem(title: b0Fixture2, parentID: group.id)
        grandchild = TaskItem(title: b0Fixture3, parentID: child.id)
    }

    var tasks: [TaskItem] { [group, child, grandchild, other] }
}

struct OutlineMovingTests {
    @Test func movesTaskIntoGroupAtStart() throws {
        let f = Fixture()

        let updated = try OutlineMoving.move(
            f.other.id, toParent: f.group.id, at: 0, in: f.tasks
        ).get()

        #expect(updated.map(\.title) == [b0Fixture4, b0Fixture1, b0Fixture2, b0Fixture3])
        #expect(updated[1].parentID == f.group.id)
    }

    @Test func movesTaskIntoGroupAtEnd() throws {
        let f = Fixture()

        let updated = try OutlineMoving.move(
            f.other.id, toParent: f.group.id, at: 99, in: f.tasks
        ).get()

        #expect(updated.map(\.title) == [b0Fixture4, b0Fixture2, b0Fixture3, b0Fixture1])
    }

    @Test func movesSubtreeOutToRoot() throws {
        let f = Fixture()

        let updated = try #require(try OutlineMoving.move(
            f.child.id, toParent: nil, at: 0, in: f.tasks
        ).get())

        #expect(updated.map(\.title) == [b0Fixture2, b0Fixture3, b0Fixture4, b0Fixture1])
        #expect(updated[0].parentID == nil)
        #expect(updated[1].parentID == f.child.id)
    }

    @Test func rejectsMoveIntoOwnSubtree() {
        let f = Fixture()

        let result = OutlineMoving.move(
            f.group.id, toParent: f.grandchild.id, at: 0, in: f.tasks
        )

        #expect(result == .failure(.moveIntoSubtree))
    }

    @Test func rejectsMoveIntoItself() {
        let f = Fixture()

        let result = OutlineMoving.move(
            f.group.id, toParent: f.group.id, at: 0, in: f.tasks
        )

        #expect(result == .failure(.moveIntoSubtree))
    }

    @Test func rejectsUnknownTarget() {
        let f = Fixture()

        let result = OutlineMoving.move(f.other.id, toParent: UUID(), at: 0, in: f.tasks)

        #expect(result == .failure(.targetNotFound))
    }

    @Test func sessionMoveUpdatesOutlineOrder() throws {
        let session = KairoSession()
        try session.createProject(title: "移动")
        let group = try session.addTask(title: b0Fixture4, kind: .group)
        let task = try session.addTask(title: "任务")

        _ = try session.moveTask(id: task, toParent: group, at: 0)

        #expect(try session.getTask(id: task).parentID == group)
    }
}
