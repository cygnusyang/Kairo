import Foundation
import Testing

// MARK: - 夹具数据（用户数据，不翻译；断言与构造共用同一常量）
private let b0Fixture1 = "孤儿"
private let b0Fixture2 = "组"
private let b0Fixture3 = "顶层任务"
@testable import KairoCore

// 可见大纲树（F-14 / ADR-013）：行序、层级、收合、过滤、群组聚合。

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d))!
}

private func scheduled(
    _ id: UUID,
    start: Date,
    finish: Date,
    duration: Double = 1
) -> ScheduledTask {
    ScheduledTask(
        taskID: id,
        durationDays: duration,
        earliestStart: start,
        earliestFinish: finish,
        latestStart: start,
        latestFinish: finish,
        scheduledStart: start,
        scheduledFinish: finish,
        totalSlackDays: 0,
        freeSlackDays: 0
    )
}

private struct Fixture {
    let group = TaskItem(title: b0Fixture2, kind: .group)
    let a: TaskItem
    let b: TaskItem
    let c = TaskItem(title: b0Fixture3)

    init() {
        a = TaskItem(title: "A", parentID: group.id, effortHours: 3, progress: 0.5)
        b = TaskItem(title: "B", parentID: group.id, progress: 1)
    }

    var tasks: [TaskItem] { [group, a, b, c] }
}

struct OutlineTreeTests {
    @Test func collapsedGroupsHideChildren() {
        let f = Fixture()

        let tree = OutlineTree(tasks: f.tasks, expanded: [], calendar: utc)

        #expect(tree.rows.map(\.task.title) == [b0Fixture2, b0Fixture3])
        #expect(tree.rows.map(\.depth) == [0, 0])
        #expect(tree.hiddenByCollapseCount == 2)
        #expect(tree.hiddenByFilterCount == 0)
    }

    @Test func expandedGroupsShowChildrenInOrder() {
        let f = Fixture()

        let tree = OutlineTree(tasks: f.tasks, expanded: [f.group.id], calendar: utc)

        #expect(tree.rows.map(\.task.title) == [b0Fixture2, "A", "B", b0Fixture3])
        #expect(tree.rows.map(\.depth) == [0, 1, 1, 0])
        #expect(tree.rows[0].isExpanded)
    }

    @Test func groupAggregatesWeightedProgress() {
        let f = Fixture()

        let tree = OutlineTree(tasks: f.tasks, expanded: [f.group.id], calendar: utc)
        let groupRow = tree.rows[0]

        #expect(abs(groupRow.aggregateProgress - 0.625) < 0.0001)
        #expect(groupRow.hasChildren)
        #expect(groupRow.aggregateStatus == .pending)
    }

    @Test func groupAggregatesScheduleWindow() {
        let f = Fixture()
        let schedule = ScheduleResult(tasks: [
            scheduled(f.a.id, start: day(2026, 10, 20), finish: day(2026, 10, 22), duration: 2),
            scheduled(f.b.id, start: day(2026, 10, 19), finish: day(2026, 10, 21), duration: 2)
        ])

        let tree = OutlineTree(
            tasks: f.tasks, schedule: schedule, expanded: [f.group.id], calendar: utc
        )
        let groupRow = tree.rows[0]

        #expect(groupRow.aggregateStart == day(2026, 10, 19))
        #expect(groupRow.aggregateFinish == day(2026, 10, 22))
        #expect(groupRow.aggregateDurationDays == 3)
    }

    @Test func groupStatusRules() {
        let group = TaskItem(title: b0Fixture2, kind: .group)
        let done1 = TaskItem(title: "D1", status: .done, parentID: group.id)
        let done2 = TaskItem(title: "D2", status: .done, parentID: group.id)
        let pending = TaskItem(title: "P", parentID: group.id)
        let blocked = TaskItem(title: "B", status: .blocked, parentID: group.id)
        let active = TaskItem(title: "A", status: .inProgress, parentID: group.id)

        func status(_ children: [TaskItem]) -> TaskStatus {
            OutlineTree(
                tasks: [group] + children, expanded: [group.id], calendar: utc
            ).rows[0].aggregateStatus
        }

        #expect(status([done1, done2]) == .done)
        #expect(status([pending, active]) == .inProgress)
        #expect(status([pending, blocked]) == .blocked)
        #expect(status([pending]) == .pending)
        #expect(status([]) == .pending)
    }

    @Test func emptyGroupHasNoAggregateWindow() {
        let group = TaskItem(title: "空组", kind: .group)

        let row = OutlineTree(tasks: [group], expanded: [group.id], calendar: utc).rows[0]

        #expect(!row.hasChildren)
        #expect(row.aggregateStart == nil)
        #expect(row.aggregateFinish == nil)
        #expect(row.aggregateProgress == 0)
    }

    @Test func groupCountsSubtreeViolations() {
        let f = Fixture()
        let violations = [
            Violation(reason: .cycle(taskTitle: "A"), taskID: f.a.id, severity: .warning),
            Violation(reason: .negativeSlack(taskTitle: "B"), taskID: f.b.id, severity: .error),
            Violation(reason: .taskAfterProjectEnd(taskTitle: "C"), taskID: f.c.id, severity: .error)
        ]

        let tree = OutlineTree(
            tasks: f.tasks, expanded: [f.group.id], matchedIDs: nil,
            violations: violations, calendar: utc
        )

        #expect(tree.rows[0].violationCount == 2)
        #expect(tree.rows[3].violationCount == 1)
    }

    @Test func filterShowsMatchesAndForcesAncestorsExpanded() {
        let f = Fixture()

        let tree = OutlineTree(
            tasks: f.tasks, expanded: [], matchedIDs: [f.b.id], calendar: utc
        )

        #expect(tree.rows.map(\.task.title) == [b0Fixture2, "B"])
        #expect(tree.rows.map(\.depth) == [0, 1])
        #expect(tree.hiddenByFilterCount == 2)
        #expect(tree.rows[0].isExpanded)
    }

    @Test func filterWithNoMatchesProducesEmptyTree() {
        let f = Fixture()

        let tree = OutlineTree(
            tasks: f.tasks, expanded: [f.group.id], matchedIDs: [], calendar: utc
        )

        #expect(tree.rows.isEmpty)
        #expect(tree.hiddenByFilterCount == 4)
    }

    @Test func leavesCarryOwnScheduleAndProgress() {
        let f = Fixture()
        let schedule = ScheduleResult(tasks: [
            scheduled(f.a.id, start: day(2026, 10, 20), finish: day(2026, 10, 22), duration: 2)
        ])

        let tree = OutlineTree(
            tasks: f.tasks, schedule: schedule, expanded: [f.group.id], calendar: utc
        )
        let row = tree.rows[1]

        #expect(row.scheduledStart == day(2026, 10, 20))
        #expect(row.scheduledFinish == day(2026, 10, 22))
        #expect(row.aggregateProgress == 0.5)
        #expect(row.aggregateStart == nil)
    }

    @Test func orphanIsTreatedAsRoot() {
        let orphan = TaskItem(title: b0Fixture1, parentID: UUID())

        let tree = OutlineTree(tasks: [orphan], calendar: utc)

        #expect(tree.rows.map(\.task.title) == [b0Fixture1])
        #expect(tree.rows[0].depth == 0)
    }
}
