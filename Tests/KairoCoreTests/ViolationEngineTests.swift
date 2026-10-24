import Foundation
import Testing
@testable import KairoCore

// 违例引擎测试（US-E2-05 / F-30 基础集）+ 重要路径与宽延（US-E2-03）。

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d))!
}

private let d0 = day(2026, 11, 2)

private func task(
    _ title: String,
    id: UUID? = nil,
    duration: Double? = nil,
    deps: [TaskDependency] = [],
    policy: SchedulingPolicy = .asap,
    constraint: SchedulingConstraint? = nil
) -> TaskItem {
    TaskItem(
        id: id ?? UUID(),
        title: title,
        durationDays: duration,
        dependencies: deps,
        constraint: constraint,
        schedulingPolicy: policy
    )
}

private func compute(_ tasks: [TaskItem], start: Date? = d0, end: Date? = nil) -> ScheduleResult {
    ScheduleEngine.compute(tasks: tasks, projectStart: start, projectEnd: end, calendar: utc)
}

private func violations(_ result: ScheduleResult, _ tasks: [TaskItem]) -> [Violation] {
    ViolationEngine.check(result: result, tasks: tasks, calendar: utc)
}

private func codes(_ violations: [Violation]) -> Set<KairoErrorCode> {
    Set(violations.map(\.code))
}

// MARK: - F-30-08 环

struct CycleViolationTests {
    @Test func cycleReportsCycleViolationOnBothTasks() {
        let aID = UUID()
        let bID = UUID()
        let b = task("B", id: bID, deps: [TaskDependency(predecessorID: aID)])
        let a = task("A", id: aID, deps: [TaskDependency(predecessorID: bID)])
        let result = compute([a, b])
        let vs = violations(result, [a, b])
        let cycle = vs.filter { $0.code == .scheduleCycle }
        #expect(cycle.count == 2)
        #expect(cycle.contains { $0.taskID == aID })
        #expect(cycle.contains { $0.taskID == bID })
    }

    @Test func acyclicChainHasNoCycleViolation() {
        let a = task("A", duration: 2)
        let b = task("B", duration: 2, deps: [TaskDependency(predecessorID: a.id)])
        let result = compute([a, b])
        #expect(!codes(violations(result, [a, b])).contains(.scheduleCycle))
    }
}

// MARK: - F-30-13 / F-30-14 项目边界

struct ProjectBoundaryViolationTests {
    @Test func taskEndingAfterProjectEndReportsViolation() throws {
        let t = task("长任务", duration: 5)
        let result = compute([t], end: day(2026, 11, 5)) // 项目结束 D0+3
        let vs = violations(result, [t])
        #expect(codes(vs).contains(.taskAfterProjectEnd))
    }

    @Test func taskInsideProjectEndHasNoBoundaryViolation() throws {
        let t = task("短任务", duration: 2)
        let result = compute([t], end: day(2026, 11, 16))
        #expect(!codes(violations(result, [t])).contains(.taskAfterProjectEnd))
    }

    @Test func alapTaskStartBeforeProjectStartReportsViolation() throws {
        let t = task("长任务", duration: 5, policy: .alap)
        let result = compute([t], end: day(2026, 11, 4)) // 项目窗口 D0..D0+2，装不下 5 天任务
        let vs = violations(result, [t])
        #expect(codes(vs).contains(.taskBeforeProjectStart))
    }

    @Test func asapTaskAtProjectStartHasNoEarlyViolation() throws {
        let t = task("任务", duration: 2)
        let result = compute([t])
        #expect(!codes(violations(result, [t])).contains(.taskBeforeProjectStart))
    }
}

// MARK: - F-30-06 负宽延

struct NegativeSlackViolationTests {
    @Test func negativeSlackReportsCannotSchedule() throws {
        let pred = task("前驱", duration: 2)
        let t = task("受时限任务", duration: 2, deps: [TaskDependency(predecessorID: pred.id)],
                     constraint: .endNoLaterThan(day(2026, 11, 5)))
        // 前驱把 B 推到 D0+2..D0+4，但「结束不晚于 D0+3」压缩最晚窗口 → 负宽延。
        let result = compute([pred, t])
        let vs = violations(result, [pred, t])
        #expect(codes(vs).contains(.negativeSlack))
    }

    @Test func positiveSlackHasNoCannotSchedule() throws {
        let pred = task("前驱", duration: 2)
        let t = task("后继", duration: 2, deps: [TaskDependency(predecessorID: pred.id)])
        let result = compute([pred, t], end: day(2026, 11, 16))
        #expect(!codes(violations(result, [pred, t])).contains(.negativeSlack))
    }
}

// MARK: - F-30-04 时限是先决条件

struct ConstraintIsPrerequisiteTests {
    @Test func startNoLaterThanViolatedByPredecessors() throws {
        let pred = task("前驱", duration: 4)
        let t = task("受时限任务", duration: 2, deps: [TaskDependency(predecessorID: pred.id)],
                     constraint: .startNoLaterThan(day(2026, 11, 5)))
        // 前驱使最早开始 = D0+4 > 时限 D0+3。
        let result = compute([pred, t])
        let vs = violations(result, [pred, t])
        #expect(codes(vs).contains(.constraintVsPrerequisite))
    }

    @Test func startNoLaterThanSatisfiedHasNoViolation() throws {
        let pred = task("前驱", duration: 1)
        let t = task("受时限任务", duration: 2, deps: [TaskDependency(predecessorID: pred.id)],
                     constraint: .startNoLaterThan(day(2026, 11, 16)))
        let result = compute([pred, t])
        #expect(!codes(violations(result, [pred, t])).contains(.constraintVsPrerequisite))
    }
}

// MARK: - F-30-05 时限是相关性

struct ConstraintIsDependencyTests {
    @Test func startNoEarlierThanBeyondLatestWindow() throws {
        let t = task("受时限任务", duration: 2,
                     constraint: .startNoEarlierThan(day(2026, 11, 16)))
        // 项目结束 D0+8 → 最晚开始 D0+6 < 时限 D0+14。
        let result = compute([t], end: day(2026, 11, 10))
        let vs = violations(result, [t])
        #expect(codes(vs).contains(.constraintVsDependency))
    }

    @Test func startNoEarlierThanWithinWindowHasNoViolation() throws {
        let t = task("受时限任务", duration: 2,
                     constraint: .startNoEarlierThan(day(2026, 11, 4)))
        let result = compute([t], end: day(2026, 11, 10))
        #expect(!codes(violations(result, [t])).contains(.constraintVsDependency))
    }
}

// MARK: - F-30-05 时限与相关性链冲突

struct ConstraintConflictsDependencyTests {
    @Test func startNoLaterThanTooCloseToFitDuration() throws {
        let t = task("受时限任务", duration: 5,
                     constraint: .startNoLaterThan(day(2026, 11, 4)))
        // 时限 D0+2 + 持续 5 = D0+7 > 最晚结束 D0+6（项目结束）。
        let result = compute([t], end: day(2026, 11, 8))
        let vs = violations(result, [t])
        #expect(codes(vs).contains(.constraintVsDependency))
    }

    @Test func startNoLaterThanWithRoomHasNoViolation() throws {
        let t = task("受时限任务", duration: 2,
                     constraint: .startNoLaterThan(day(2026, 11, 10)))
        let result = compute([t], end: day(2026, 11, 20))
        #expect(!codes(violations(result, [t])).contains(.constraintVsDependency))
    }
}

// MARK: - F-30-03 时限靠得太近（开始侧 + 结束侧时限窗口 < 持续时间）

struct ConstraintWindowTests {
    @Test func startAndEndConstraintsWindowTooNarrow() throws {
        let t = task("双时限任务", duration: 5,
                     constraint: .startNoEarlierThan(day(2026, 11, 2)))
        var withEnd = t
        withEnd.dueDate = day(2026, 11, 4)  // 窗口 2 天 < 持续 5 天
        let result = compute([withEnd], end: day(2026, 11, 20))
        #expect(codes(violations(result, [withEnd])).contains(.constraintWindowTooNarrow))
    }

    @Test func singleSidedConstraintHasNoWindowViolation() throws {
        let t = task("单时限任务", duration: 5,
                     constraint: .startNoLaterThan(day(2026, 11, 4)))
        let result = compute([t], end: day(2026, 11, 20))
        #expect(!codes(violations(result, [t])).contains(.constraintWindowTooNarrow))
    }
}

// MARK: - 重要路径与宽延（US-E2-03 / F-21-01）

struct CriticalPathTests {
    @Test func tightChainIsCriticalPathAndParallelIsNot() {
        let a = task("A", duration: 2)
        let b = task("B", duration: 2, deps: [TaskDependency(predecessorID: a.id)])
        let c = task("C", duration: 2, deps: [TaskDependency(predecessorID: b.id)])
        let p = task("并行任务", duration: 1)
        let result = compute([a, b, c, p], end: day(2026, 11, 8)) // 紧链，总宽延 0
        let entries = CriticalPathEngine.compute(result: result, slackLimit: 0)
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.taskID, $0) })
        #expect(byID[a.id]?.isCritical == true)
        #expect(byID[b.id]?.isCritical == true)
        #expect(byID[c.id]?.isCritical == true)
        #expect(byID[p.id]?.isCritical == false)
        #expect(byID[a.id]?.totalSlackDays == 0)
        #expect(byID[p.id]?.totalSlackDays == 5)
    }

    @Test func slackLimitExpandsCriticalSet() {
        let a = task("A", duration: 2)
        let b = task("B", duration: 2, deps: [TaskDependency(predecessorID: a.id)])
        let result = compute([a, b], end: day(2026, 11, 12)) // 项目结束 D0+10 → A、B 总宽延 6
        let loose = CriticalPathEngine.compute(result: result, slackLimit: 0)
        let tight = CriticalPathEngine.compute(result: result, slackLimit: 6)
        #expect(loose.allSatisfy { !$0.isCritical })
        #expect(tight.allSatisfy { $0.isCritical })
    }

    @Test func freeSlackDifferentiatesParallelPredecessors() {
        let p1 = task("P1", duration: 2)
        let p2 = task("P2", duration: 1)
        let s = task("S", duration: 1, deps: [
            TaskDependency(predecessorID: p1.id),
            TaskDependency(predecessorID: p2.id),
        ])
        let result = compute([p1, p2, s])
        let entries = CriticalPathEngine.compute(result: result)
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.taskID, $0) })
        // P1 结束即 S 最早开始 → 自由宽延 0；P2 可推迟 1 天不拖累 S。
        #expect(byID[p1.id]?.freeSlackDays == 0)
        #expect(byID[p2.id]?.freeSlackDays == 1)
    }
}

// MARK: - F-0715 / D-022 归因：开始日落在项目窗口外

struct StartAfterProjectWindowAttributionTests {
    @Test func startDateBeyondProjectEndIsAttributedToUserInput() {
        var late = task("窗口外任务", duration: 2)
        late.startDate = day(2026, 11, 20)
        let window = violations(compute([late], end: day(2026, 11, 5)), [late])
        let attributed = window.filter { $0.code == .startAfterProjectWindow }
        #expect(attributed.count == 1)
        guard case .startAfterProjectWindow(let title, let taskStart, let projectStart, let projectEnd)?
            = attributed.first?.reason else {
            Issue.record("期望 startAfterProjectWindow，实际 \(String(describing: attributed.first?.reason))")
            return
        }
        #expect(title == "窗口外任务")
        #expect(taskStart == day(2026, 11, 20))
        #expect(projectStart == d0)
        #expect(projectEnd == day(2026, 11, 5))
        // 归因不再落到「负宽延」：用户输入造成的越界不能被描述成依赖冲突（D-022）。
        #expect(!codes(window).contains(.negativeSlack))
    }

    @Test func startDateBeforeProjectStartIsAttributedToTheSameReason() {
        // 对称情形：意图开始早于项目开始，同样归因到用户输入（参数携带方向）。
        var early = task("过早任务", duration: 5)
        early.startDate = day(2026, 10, 20)
        let window = violations(compute([early], end: day(2026, 11, 4)), [early])
        let attributed = window.filter { $0.code == .startAfterProjectWindow }
        #expect(attributed.count == 1)
        guard case .startAfterProjectWindow(_, let taskStart, _, _)? = attributed.first?.reason else {
            return
        }
        #expect(taskStart == day(2026, 10, 20))
        #expect(!codes(window).contains(.negativeSlack))
    }

    @Test func negativeSlackInsideWindowKeepsItsOwnAttribution() {
        // 反例护栏：没有用户输入越界时，负宽延仍归因「无法安排」，不被新归因吞掉。
        let pred = task("前驱", duration: 2)
        let t = task("后继", duration: 2, deps: [TaskDependency(predecessorID: pred.id)])
        let vs = violations(compute([pred, t], end: day(2026, 11, 4)), [pred, t])
        #expect(codes(vs).contains(.negativeSlack))
        #expect(!codes(vs).contains(.startAfterProjectWindow))
    }
}

// MARK: - F-0716 / D-023 时限窗口按日历日（America/New_York 跨 DST）

private let newYork: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()

private func nyDay(_ y: Int, _ m: Int, _ d: Int) -> Date {
    newYork.date(from: DateComponents(year: y, month: m, day: d))!
}

/// 违例检查必须使用与排期同一个日历：混用 UTC 会把 DST 差异算成 0 小时（这正是 D-023 的坑）。
private func nyViolations(_ result: ScheduleResult, _ tasks: [TaskItem]) -> [Violation] {
    ViolationEngine.check(result: result, tasks: tasks, calendar: newYork)
}

struct ConstraintWindowCalendarDayTests {
    /// 秋退：2025-11-02 回拨，窗口 2 个日历日是 49 小时。
    /// 旧实现按 49h/24 = 2.0417 天判「装得下」；日历日口径是 2 天，装不下 2.02 天。
    @Test func windowAcrossFallBackCountsCalendarDays() {
        var t = task("跨回拨任务", duration: 2.02,
                     constraint: .startNoEarlierThan(nyDay(2025, 11, 1)))
        t.dueDate = nyDay(2025, 11, 3)
        let result = ScheduleEngine.compute(
            tasks: [t],
            projectStart: nyDay(2025, 10, 27),
            projectEnd: nyDay(2025, 12, 1),
            calendar: newYork
        )
        let window = nyViolations(result, [t]).filter { $0.code == .constraintWindowTooNarrow }
        #expect(window.count == 1)
        guard case .constraintWindowTooNarrow(_, let windowDays, let requiredDays)?
            = window.first?.reason else { return }
        #expect(windowDays == 2)
        #expect(requiredDays == 2)
    }

    /// 春进：2025-03-09 前拨，窗口 2 个日历日是 47 小时。
    /// 旧实现按 47h/24 = 1.9583 天误报「过窄」；日历日口径是 2 天，装得下 1.98 天。
    @Test func windowAcrossSpringForwardDoesNotReportFalsePositive() {
        var t = task("跨前拨任务", duration: 1.98,
                     constraint: .startNoEarlierThan(nyDay(2025, 3, 8)))
        t.dueDate = nyDay(2025, 3, 10)
        let result = ScheduleEngine.compute(
            tasks: [t],
            projectStart: nyDay(2025, 3, 3),
            projectEnd: nyDay(2025, 3, 20),
            calendar: newYork
        )
        #expect(!codes(nyViolations(result, [t])).contains(.constraintWindowTooNarrow))
    }

    /// 春进下的 endNoEarlierThan 反解：x − 持续 必须按日历日，否则会提前 1 小时误报。
    @Test func endNoEarlierThanResolutionStaysOnCalendarDays() {
        let t = task("结束不早于任务", duration: 2,
                     constraint: .endNoEarlierThan(nyDay(2025, 3, 10)))
        let result = ScheduleEngine.compute(
            tasks: [t],
            projectStart: nyDay(2025, 3, 8),
            projectEnd: nyDay(2025, 3, 20),
            calendar: newYork
        )
        let conflicts = nyViolations(result, [t]).filter { $0.code == .constraintVsDependency }
        #expect(conflicts.isEmpty, "跨前拨不应误报窗口装不下持续时间：\(conflicts.map(\.reason))")
    }
}
