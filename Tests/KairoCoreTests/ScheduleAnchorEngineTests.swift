import Foundation
import Testing
@testable import KairoCore

// D-003 复现与修复：项目未设开始日期时，排期不得落在 1970 纪元。
// 同时验证 ScheduleResult 的未排期集合与旧数据解码兼容。

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d))!
}

private let now = day(2026, 10, 18)

struct ScheduleAnchorEngineTests {
    @Test func engineDerivesAnchorFromEarliestTaskStart() {
        let task = TaskItem(title: "A", startDate: day(2026, 11, 2), durationDays: 2)

        let result = ScheduleEngine.compute(tasks: [task], calendar: utc, now: now)

        #expect(result.projectStart == day(2026, 11, 2))
        #expect(result.projectStartDerived)
        let scheduled = result.scheduled(task.id)
        #expect(scheduled?.scheduledStart == day(2026, 11, 2))
        #expect(scheduled?.scheduledFinish == day(2026, 11, 4))
        #expect(result.projectStart != day(1970, 1, 1))
    }

    @Test func engineFallsBackToTodayWithoutDates() {
        let task = TaskItem(title: "A")

        let result = ScheduleEngine.compute(tasks: [task], calendar: utc, now: now)

        #expect(result.projectStart == day(2026, 10, 18))
        #expect(result.projectStartDerived)
    }

    @Test func explicitProjectStartIsNotDerived() {
        let task = TaskItem(title: "A")

        let result = ScheduleEngine.compute(
            tasks: [task], projectStart: day(2026, 12, 1), calendar: utc, now: now
        )

        #expect(result.projectStart == day(2026, 12, 1))
        #expect(!result.projectStartDerived)
    }

    @Test func emptyGroupIsUnscheduled() {
        let group = TaskItem(title: "空组", kind: .group)
        let task = TaskItem(title: "A")

        let result = ScheduleEngine.compute(tasks: [group, task], calendar: utc, now: now)

        #expect(result.unscheduledTaskIDs == [group.id])
        #expect(!result.hasSchedule(for: group.id))
        #expect(result.hasSchedule(for: task.id))
    }

    @Test func cycleTasksAreUnscheduled() {
        let a = TaskItem(title: "A")
        let b = TaskItem(title: "B")
        var tasks = [a, b]
        tasks[0].dependencies = [TaskDependency(predecessorID: b.id)]
        tasks[1].dependencies = [TaskDependency(predecessorID: a.id)]

        let result = ScheduleEngine.compute(tasks: tasks, calendar: utc, now: now)

        #expect(Set(result.unscheduledTaskIDs) == [a.id, b.id])
        #expect(result.hasSchedule(for: a.id) == false)
    }

    @Test func resultDecodesLegacyPayloadWithoutNewFields() throws {
        let task = TaskItem(title: "A")
        let legacy = """
        {
          "tasks": [],
          "direction": "forward",
          "cycleTaskIDs": []
        }
        """
        // 旧负载缺少 projectStart/projectEnd/projectStartDerived/unscheduledTaskIDs。
        let decoded = try JSONDecoder().decode(ScheduleResult.self, from: Data(legacy.utf8))

        #expect(decoded.tasks.isEmpty)
        #expect(decoded.projectStartDerived == false)
        #expect(decoded.unscheduledTaskIDs.isEmpty)
        #expect(!decoded.hasSchedule(for: task.id))
    }

    @Test func ruleCategoriesAreExposed() {
        let codes = Set(ViolationEngine.ruleCategories.map(\.code))

        #expect(codes.contains("cycle"))
        #expect(codes.contains("constraint_window_too_narrow"))
        // F-0704：规则名不再随核心层下发（名字由视图按 violation.rule.<code> 查 Catalog）。
        #expect(ViolationEngine.ruleCategories.count == 7)
        #expect(ViolationEngine.ruleCategories.allSatisfy { $0.severity == .error })
    }
}
