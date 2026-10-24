import Foundation
import Testing
@testable import KairoCore

// 项目摘要与健康度（F-30 / ADR-013）：进度加权、逾期口径、健康阈值、剩余天数。

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d))!
}

private let now = day(2026, 10, 18)

private func scheduled(
    _ id: UUID,
    start: Date,
    finish: Date,
    slack: Double = 0,
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
        totalSlackDays: slack,
        freeSlackDays: slack
    )
}

struct ProjectSummaryTests {
    @Test func weightedProgressIgnoresGroups() {
        let group = TaskItem(title: "组", kind: .group)
        let a = TaskItem(title: "A", parentID: group.id, effortHours: 3, progress: 0.5)
        let b = TaskItem(title: "B", parentID: group.id, progress: 1)

        let summary = ProjectSummary(
            tasks: [group, a, b], schedule: nil, violations: [], now: now, calendar: utc
        )

        #expect(abs(summary.totalProgress - 0.625) < 0.0001)
        #expect(summary.groupCount == 1)
        #expect(summary.taskCount == 2)
    }

    @Test func countsKindsAndIncompleteLeaves() {
        let tasks = [
            TaskItem(title: "任务"),
            TaskItem(title: "完成", status: .done),
            TaskItem(title: "群组", kind: .group),
            TaskItem(title: "里程碑", kind: .milestone)
        ]

        let summary = ProjectSummary(
            tasks: tasks, schedule: nil, violations: [], now: now, calendar: utc
        )

        #expect(summary.taskCount == 2)
        #expect(summary.groupCount == 1)
        #expect(summary.milestoneCount == 1)
        #expect(summary.incompleteLeafCount == 2)
    }

    @Test func overdueUsesPlannedFinishThenDueDateFallback() {
        let planned = TaskItem(title: "计划结束已过")
        let fallback = TaskItem(title: "无排期按截止日期", dueDate: day(2026, 10, 1))
        let done = TaskItem(title: "已完成", dueDate: day(2026, 10, 1), status: .done)
        let future = TaskItem(title: "未到期", dueDate: day(2026, 10, 20))
        let schedule = ScheduleResult(tasks: [
            scheduled(planned.id, start: day(2026, 10, 10), finish: day(2026, 10, 17))
        ])

        let summary = ProjectSummary(
            tasks: [planned, fallback, done, future],
            schedule: schedule,
            violations: [],
            now: now,
            calendar: utc
        )

        #expect(summary.overdueCount == 2)
        #expect(summary.missingDueDateCount == 1) // planned 无 dueDate
    }

    @Test func unscheduledTaskFallsBackToDueDate() {
        let task = TaskItem(title: "空群组内", dueDate: day(2026, 10, 1))
        let schedule = ScheduleResult(
            tasks: [scheduled(task.id, start: day(2026, 10, 10), finish: day(2026, 10, 17))],
            unscheduledTaskIDs: [task.id]
        )

        let summary = ProjectSummary(
            tasks: [task], schedule: schedule, violations: [], now: now, calendar: utc
        )

        #expect(summary.overdueCount == 1)
    }

    @Test func errorViolationForcesRed() {
        let summary = ProjectSummary(
            tasks: [TaskItem(title: "A")],
            schedule: nil,
            violations: [Violation(reason: .cycle(taskTitle: "A"))],
            now: now,
            calendar: utc
        )

        #expect(summary.health == .red)
        #expect(summary.errorCount == 1)
    }

    @Test func overdueRatioAboveTwentyPercentIsRed() {
        let tasks = (0..<5).map { i in
            TaskItem(title: "T\(i)", dueDate: i < 2 ? day(2026, 10, 1) : day(2026, 12, 1))
        }

        let summary = ProjectSummary(
            tasks: tasks, schedule: nil, violations: [], now: now, calendar: utc
        )

        #expect(summary.overdueCount == 2)
        #expect(summary.health == .red)
    }

    @Test func singleOverdueIsOrange() {
        let tasks = (0..<5).map { i in
            TaskItem(title: "T\(i)", dueDate: i == 0 ? day(2026, 10, 1) : day(2026, 12, 1))
        }

        let summary = ProjectSummary(
            tasks: tasks, schedule: nil, violations: [], now: now, calendar: utc
        )

        #expect(summary.health == .orange)
    }

    @Test func warningOrMissingDueDateMajorityIsOrange() {
        let warning = ProjectSummary(
            tasks: [TaskItem(title: "A")],
            schedule: nil,
            violations: [Violation(reason: .negativeSlack(taskTitle: "A"), severity: .warning)],
            now: now,
            calendar: utc
        )
        #expect(warning.health == .orange)

        let missing = ProjectSummary(
            tasks: (0..<5).map { TaskItem(title: "T\($0)", dueDate: $0 == 0 ? day(2026, 12, 1) : nil) },
            schedule: nil,
            violations: [],
            now: now,
            calendar: utc
        )
        #expect(missing.health == .orange)
    }

    @Test func greenWhenNoSignals() {
        let summary = ProjectSummary(
            tasks: [TaskItem(title: "A", dueDate: day(2026, 12, 1))],
            schedule: nil,
            violations: [],
            now: now,
            calendar: utc
        )

        #expect(summary.health == .green)
    }

    @Test func criticalPathCountsZeroSlackLeavesOnly() {
        let a = TaskItem(title: "关键")
        let b = TaskItem(title: "有宽延")
        let group = TaskItem(title: "组", kind: .group)
        let schedule = ScheduleResult(tasks: [
            scheduled(a.id, start: day(2026, 10, 18), finish: day(2026, 10, 20), slack: 0),
            scheduled(b.id, start: day(2026, 10, 18), finish: day(2026, 10, 20), slack: 2),
            scheduled(group.id, start: day(2026, 10, 18), finish: day(2026, 10, 20), slack: 0)
        ])

        let summary = ProjectSummary(
            tasks: [a, b, group], schedule: schedule, violations: [], now: now, calendar: utc
        )

        #expect(summary.criticalPathCount == 1)
    }

    @Test func remainingDaysUsesProjectEnd() {
        let a = TaskItem(title: "A")
        let schedule = ScheduleResult(
            tasks: [scheduled(a.id, start: day(2026, 10, 18), finish: day(2026, 10, 25))],
            projectEnd: day(2026, 10, 25)
        )

        let summary = ProjectSummary(
            tasks: [a], schedule: schedule, violations: [], now: now, calendar: utc
        )

        #expect(summary.remainingDays == 7)
    }

    @Test func remainingDaysFallsBackToLatestFinishAndClampsPast() {
        let a = TaskItem(title: "A")
        let past = ScheduleResult(tasks: [
            scheduled(a.id, start: day(2026, 10, 1), finish: day(2026, 10, 5))
        ])

        let summary = ProjectSummary(
            tasks: [a], schedule: past, violations: [], now: now, calendar: utc
        )

        #expect(summary.remainingDays == 0)
        #expect(ProjectSummary(
            tasks: [a], schedule: nil, violations: [], now: now, calendar: utc
        ).remainingDays == nil)
    }
}
