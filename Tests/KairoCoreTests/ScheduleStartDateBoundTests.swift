import Foundation
import Testing
@testable import KairoCore

// S8 / D-021：任务 `startDate` 是「开始不早于」下界（设计稿 §9.1 E1 方案 C）。
// 排期口径：start = max(项目锚点, startOfDay(startDate), 时限下界, 相关性下界)；
// 群组忽略自身 startDate（由子任务聚合）；后向传播与宽延口径不变。

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d))!
}

/// 指定日期 + 时分秒（用于验证归一）。
private func at(_ y: Int, _ m: Int, _ d: Int, _ hour: Int, _ minute: Int) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
}

private let projectStart = day(2026, 11, 2) // 2026-11-02 周一

private func compute(_ tasks: [TaskItem], start: Date? = projectStart) -> ScheduleResult {
    ScheduleEngine.compute(tasks: tasks, projectStart: start, calendar: utc)
}

struct ScheduleStartDateBoundTests {
    @Test func leafStartDateRaisesEarliestStart() throws {
        let t = TaskItem(title: "T", startDate: day(2026, 11, 10), durationDays: 2)

        let s = try #require(compute([t]).scheduled(t.id))

        // 项目锚点 11-02 早于意图开始 11-10：取较晚者。
        #expect(s.earliestStart == day(2026, 11, 10))
        #expect(s.earliestFinish == day(2026, 11, 12))
        #expect(s.scheduledStart == day(2026, 11, 10))
    }

    @Test func startDateAndFinishToStartDependencyPickLater() throws {
        let a = TaskItem(title: "A", durationDays: 5)
        let b = TaskItem(
            title: "B",
            startDate: day(2026, 11, 4),
            durationDays: 2,
            dependencies: [TaskDependency(predecessorID: a.id, type: .fs)]
        )

        let result = compute([a, b])
        let sa = try #require(result.scheduled(a.id))
        let sb = try #require(result.scheduled(b.id))

        #expect(sa.earliestStart == projectStart)
        // FS 下界 = A 结束（11-07）晚于 B 的 startDate（11-04）→ 取 11-07。
        #expect(sb.earliestStart == day(2026, 11, 7))
        #expect(sb.earliestFinish == day(2026, 11, 9))
    }

    @Test func startDateAndConstraintPickLater() throws {
        let late = TaskItem(
            title: "时限更晚",
            startDate: day(2026, 11, 10),
            durationDays: 1,
            constraint: .startNoEarlierThan(day(2026, 11, 20))
        )
        let intent = TaskItem(
            title: "意图更晚",
            startDate: day(2026, 11, 25),
            durationDays: 1,
            constraint: .startNoEarlierThan(day(2026, 11, 20))
        )

        let result = compute([late, intent])

        #expect(try #require(result.scheduled(late.id)).earliestStart == day(2026, 11, 20))
        #expect(try #require(result.scheduled(intent.id)).earliestStart == day(2026, 11, 25))
    }

    @Test func groupStartDateIsIgnored() throws {
        let group = TaskItem(title: "阶段", startDate: day(2026, 11, 20), kind: .group)
        let child = TaskItem(title: "子任务", parentID: group.id, durationDays: 2)

        let result = compute([group, child])

        // 群组自身 startDate 不参与下界：仍从项目锚点起排。
        #expect(try #require(result.scheduled(group.id)).earliestStart == projectStart)
        #expect(try #require(result.scheduled(child.id)).earliestStart == projectStart)
    }

    @Test func milestoneStartDateActsAsBound() throws {
        let m = TaskItem(title: "M", startDate: day(2026, 11, 15), kind: .milestone)

        let s = try #require(compute([m]).scheduled(m.id))

        #expect(s.durationDays == 0)
        #expect(s.earliestStart == day(2026, 11, 15))
        #expect(s.earliestFinish == day(2026, 11, 15))
    }

    @Test func startDateBeforeProjectAnchorDoesNotPullScheduleEarlier() throws {
        let t = TaskItem(title: "T", startDate: day(2026, 10, 1), durationDays: 2)

        let s = try #require(compute([t], start: day(2026, 11, 16)).scheduled(t.id))

        // 已过期的意图开始不驱动提前，只作为下界：仍不早于项目锚点。
        #expect(s.earliestStart == day(2026, 11, 16))
        #expect(s.earliestFinish == day(2026, 11, 18))
    }

    @Test func startDateWithTimeIsNormalizedToStartOfDay() throws {
        let t = TaskItem(title: "T", startDate: at(2026, 11, 10, 23, 30), durationDays: 1)

        let s = try #require(compute([t]).scheduled(t.id))

        // 时刻被丢弃：条体从 11-10 零点起排。
        #expect(s.earliestStart == day(2026, 11, 10))
        #expect(s.earliestFinish == day(2026, 11, 11))
    }

    @Test func cycleTaskStartDateDoesNotCrash() throws {
        let aID = UUID()
        let bID = UUID()
        let a = TaskItem(
            id: aID, title: "A", startDate: day(2026, 11, 10), durationDays: 2,
            dependencies: [TaskDependency(predecessorID: bID)]
        )
        let b = TaskItem(
            id: bID, title: "B", startDate: day(2026, 11, 12), durationDays: 1,
            dependencies: [TaskDependency(predecessorID: aID)]
        )

        let result = compute([a, b])

        #expect(Set(result.unscheduledTaskIDs) == Set([aID, bID]))
        // 环上任务仍有基值，且尊重各自 startDate 下界（不崩溃、不落纪元）。
        let sa = try #require(result.scheduled(aID))
        let sb = try #require(result.scheduled(bID))
        #expect(sa.earliestStart == day(2026, 11, 10))
        #expect(sb.earliestStart == day(2026, 11, 12))
    }

    @Test func alapTaskNeverStartsBeforeStartDate() throws {
        // 项目结束锚点（11-05）早于意图开始（11-20）：ALAP 的最晚窗口落在 11-04，
        // 选定安排必须收敛到 startDate 下界，并保持 finish = start + duration。
        let t = TaskItem(
            title: "T", startDate: day(2026, 11, 20), durationDays: 1, schedulingPolicy: .alap
        )

        let result = ScheduleEngine.compute(
            tasks: [t], projectStart: projectStart, projectEnd: day(2026, 11, 5), calendar: utc
        )
        let s = try #require(result.scheduled(t.id))

        #expect(s.latestStart == day(2026, 11, 4))
        #expect(s.earliestStart == day(2026, 11, 20))
        #expect(s.scheduledStart == day(2026, 11, 20))
        #expect(s.scheduledFinish == day(2026, 11, 21))
    }

    @Test func asapTaskSelectionKeepsStartDateBound() throws {
        // 统一收敛路径的 ASAP 回归：选定值不应回退到锚点。
        let t = TaskItem(title: "T", startDate: day(2026, 11, 20), durationDays: 2)

        let result = ScheduleEngine.compute(
            tasks: [t], projectStart: projectStart, projectEnd: day(2026, 11, 5), calendar: utc
        )
        let s = try #require(result.scheduled(t.id))

        #expect(s.scheduledStart == day(2026, 11, 20))
        #expect(s.scheduledFinish == day(2026, 11, 22))
    }
}

// MARK: - F-0717 / D-024 「无下界」哨兵统一

struct NoLowerBoundSentinelTests {
    /// 哨兵只有一个取值：distantPast（旧实现里一条分支用 1970 纪元零点）。
    @Test func sentinelIsTheSingleNamedConstant() {
        #expect(ScheduleBounds.noLowerBound == Date.distantPast)
    }

    /// 无 startDate、无 startNoEarlierThan ⇒ 两个下界都取哨兵，被 max 吞掉，结果等于锚点。
    @Test func taskWithoutAnyLowerBoundStartsAtAnchor() throws {
        let t = TaskItem(title: "无下界", durationDays: 2)
        let s = try #require(compute([t]).scheduled(t.id))

        #expect(s.earliestStart == projectStart)
        #expect(s.scheduledStart == projectStart)
    }

    /// 两种下界同时缺席与只缺一种时口径一致：哨兵不参与比较胜出。
    @Test func constraintFloorAndIntentFloorAgreeWhenAbsent() throws {
        let neither = TaskItem(title: "都无", durationDays: 1)
        let constraintOnly = TaskItem(
            title: "只有时限",
            durationDays: 1,
            constraint: .startNoEarlierThan(projectStart)
        )
        let intentOnly = TaskItem(title: "只有意图", startDate: projectStart, durationDays: 1)

        let result = compute([neither, constraintOnly, intentOnly])
        let starts = try [neither, constraintOnly, intentOnly].map {
            try #require(result.scheduled($0.id)).earliestStart
        }

        #expect(Set(starts) == [projectStart])
    }
}
