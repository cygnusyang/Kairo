import Foundation

/// 调度引擎（ADR-007：调度为纯函数，无副作用，只依赖 Foundation）。
///
/// 输入任务清单与项目边界，输出每任务的最早/最晚可行窗口与选定安排；
/// 不改写 TaskItem 的原始字段（startDate/dueDate 是用户输入意图，调度结果是另一张表）。
/// `startDate` 作为「开始不早于」下界参与前向传播（S8 / D-021）：不驱动提前，
/// 但排期结果不得早于该日；群组忽略自身 `startDate`，里程碑同样适用。
///
/// 日历简化：以「日历日」为最小单位做日期算术（按 Calendar 整日加减，跨夏令时切换
/// 仍落在本地零点，不按 86 400 秒折算）；工作周日历（US-E2-04）不在本 Sprint 范围，
/// 代码注释保留该口径。
///
/// 相关性传播（F-22-07）：FS/FF/SS/SF 四型不等式 + lagDays（天，可正负）：
///   FS：后继开始 ≥ 前驱结束 + lag
///   FF：后继结束 ≥ 前驱结束 + lag
///   SS：后继开始 ≥ 前驱开始 + lag
///   SF：后继结束 ≥ 前驱开始 + lag
public enum ScheduleEngine {
    public static func compute(
        tasks: [TaskItem],
        resources: [Resource] = [],
        projectStart: Date? = nil,
        projectEnd: Date? = nil,
        direction: ScheduleDirection = .forward,
        calendar: Calendar = Calendar(identifier: .gregorian),
        now: Date = Date()
    ) -> ScheduleResult {
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let resourceByID = Dictionary(uniqueKeysWithValues: resources.map { ($0.id, $0) })
        // 未设项目开始日期时按「最早任务 startDate → 今天」推导，禁止 1970 起排（D-003）。
        let scheduleAnchor = ScheduleAnchor.derive(
            tasks: tasks, projectStart: projectStart, now: now, calendar: calendar
        )
        let startAnchor: Date? = scheduleAnchor.date
        let endAnchor = projectEnd.map { calendar.startOfDay(for: $0) }
        let dayZero = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))

        let durations = durationsByTask(tasks, resourceByID: resourceByID)
        let cycleIDs = cycleTaskIDs(tasks, byID: byID)
        let cycleSet = Set(cycleIDs)
        let successorMap = successorMap(of: tasks, byID: byID)

        let earliest = forwardPass(
            tasks: tasks, byID: byID, durations: durations,
            startAnchor: startAnchor, dayZero: dayZero, cycleSet: cycleSet, calendar: calendar
        )
        let anchor = endAnchor ?? (earliest.values.map(\.finish).max() ?? dayZero)
        let latest = backwardPass(
            tasks: tasks, byID: byID, durations: durations, successorMap: successorMap,
            anchor: anchor, cycleSet: cycleSet, calendar: calendar
        )

        let scheduled = scheduledTasks(
            tasks: tasks, durations: durations,
            earliest: earliest, latest: latest, successorMap: successorMap,
            calendar: calendar
        )

        // 无法排期：环上任务与空群组。其余任务均有调度条目。
        let parentIDs = Set(tasks.compactMap(\.parentID))
        let unscheduledIDs = tasks.compactMap { task -> UUID? in
            if cycleSet.contains(task.id) { return task.id }
            if task.kind == .group && !parentIDs.contains(task.id) { return task.id }
            return nil
        }

        return ScheduleResult(
            tasks: scheduled,
            projectStart: startAnchor,
            projectEnd: endAnchor,
            direction: direction,
            cycleTaskIDs: cycleIDs,
            projectStartDerived: scheduleAnchor.isDerived,
            unscheduledTaskIDs: unscheduledIDs
        )
    }

    // MARK: - 持续时间

    /// 每任务持续时间（天）：里程碑恒为 0；有 durationDays 用之；有投入时
    /// 按 duration = effort / Σ(units × efficiency) 换算（F-22-03，8h/日工作周简化）。
    /// 无分配资源时按 1 个 100% 单位（8h/日）换算（US-E1-05 验收 1）。
    private static func durationsByTask(_ tasks: [TaskItem], resourceByID: [UUID: Resource]) -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        for task in tasks {
            result[task.id] = duration(of: task, resourceByID: resourceByID)
        }
        return result
    }

    private static func duration(of task: TaskItem, resourceByID: [UUID: Resource]) -> Double {
        if task.kind == .milestone { return 0 }
        if let d = task.durationDays, d > 0 { return d }
        if let effort = task.effortHours, effort > 0 {
            let capacity = task.assignments.isEmpty ? 1 : capacity(of: task, resourceByID: resourceByID)
            if capacity > 0 { return effort / 8 / capacity }
        }
        return 1 // 无 duration 的叶子任务默认 1 天
    }

    /// 分配容量 Σ(units × efficiency)；未命中的资源按效率 1 计。
    private static func capacity(of task: TaskItem, resourceByID: [UUID: Resource]) -> Double {
        task.assignments.reduce(0) { sum, a in
            let efficiency = resourceByID[a.resourceID]?.efficiency ?? 1
            return sum + a.units * efficiency
        }
    }

    // MARK: - 环检测（F-30-08）

    /// 找出所有处于相关性环中的任务（三色 DFS）。环上任务不参与拓扑传播。
    private static func cycleTaskIDs(_ tasks: [TaskItem], byID: [UUID: TaskItem]) -> [UUID] {
        var successors: [UUID: [UUID]] = [:]
        for task in tasks {
            for dep in task.dependencies where byID[dep.predecessorID] != nil {
                successors[dep.predecessorID, default: []].append(task.id)
            }
        }
        enum Color { case white, gray, black }
        var color: [UUID: Color] = [:]
        var inCycle = Set<UUID>()
        var stack: [UUID] = []

        func visit(_ id: UUID) {
            color[id] = .gray
            stack.append(id)
            for next in successors[id] ?? [] {
                guard color[next] != .black else { continue }
                if color[next] == .gray, let idx = stack.firstIndex(of: next) {
                    for node in stack[idx...] { inCycle.insert(node) }
                } else {
                    visit(next)
                }
            }
            stack.removeLast()
            color[id] = .black
        }

        for task in tasks where color[task.id] == nil {
            visit(task.id)
        }
        // 保持输入顺序输出。
        return tasks.compactMap { inCycle.contains($0.id) ? $0.id : nil }
    }

    /// 后继邻接表：predecessor → [依赖它的任务]。悬空相关性（前驱不存在）被忽略。
    private static func successorMap(of tasks: [TaskItem], byID: [UUID: TaskItem]) -> [UUID: [TaskItem]] {
        var map: [UUID: [TaskItem]] = [:]
        for task in tasks {
            for dep in task.dependencies where byID[dep.predecessorID] != nil {
                map[dep.predecessorID, default: []].append(task)
            }
        }
        return map
    }

    /// Kahn 拓扑序（仅非环任务；环任务不入序）。依赖计数只算有效前驱。
    private static func topologicalOrder(_ tasks: [TaskItem], byID: [UUID: TaskItem]) -> [UUID] {
        var inDegree: [UUID: Int] = [:]
        var successors: [UUID: [UUID]] = [:]
        for task in tasks {
            inDegree[task.id] = task.dependencies.filter { byID[$0.predecessorID] != nil }.count
            for dep in task.dependencies where byID[dep.predecessorID] != nil {
                successors[dep.predecessorID, default: []].append(task.id)
            }
        }
        var queue: [UUID] = tasks.filter { inDegree[$0.id] == 0 }.map(\.id)
        var order: [UUID] = []
        while !queue.isEmpty {
            let id = queue.removeFirst()
            order.append(id)
            for succ in successors[id] ?? [] {
                inDegree[succ]? -= 1
                if inDegree[succ] == 0 { queue.append(succ) }
            }
        }
        return order
    }

    // MARK: - 前向传播（最早窗口 / ASAP）

    private static func forwardPass(
        tasks: [TaskItem],
        byID: [UUID: TaskItem],
        durations: [UUID: Double],
        startAnchor: Date?,
        dayZero: Date,
        cycleSet: Set<UUID>,
        calendar: Calendar
    ) -> [UUID: Window] {
        let order = topologicalOrder(tasks, byID: byID)
        let base = startAnchor ?? dayZero
        var earliest: [UUID: Window] = [:]

        // 环上任务先定基值，供其后继（非环任务）正常推导。
        for id in cycleSet {
            let task = byID[id]!
            let duration = durations[id] ?? 1
            let start = max(
                base,
                constraintStartLowerBound(task, calendar: calendar),
                startDateLowerBound(task, calendar: calendar)
            )
            earliest[id] = Window(start: start, finish: addDays(start, duration, in: calendar))
        }

        for id in order {
            let task = byID[id]!
            let duration = durations[id] ?? 1
            var start = max(
                base,
                constraintStartLowerBound(task, calendar: calendar),
                startDateLowerBound(task, calendar: calendar)
            )
            for dep in task.dependencies {
                guard let pred = byID[dep.predecessorID], let pw = earliest[pred.id] else { continue }
                start = max(start, forwardStartLowerBound(
                    type: dep.type, lag: dep.lagDays, pred: pw, duration: duration, calendar: calendar
                ))
            }
            earliest[id] = Window(start: start, finish: addDays(start, duration, in: calendar))
        }
        return earliest
    }

    /// 由一条相关性推出的后继「最早开始」下界（前向传播不等式反解）。
    private static func forwardStartLowerBound(
        type: TaskDependency.DependencyType, lag: Double, pred: Window, duration: Double,
        calendar: Calendar
    ) -> Date {
        switch type {
        case .fs: return addDays(pred.finish, lag, in: calendar)
        case .ss: return addDays(pred.start, lag, in: calendar)
        case .ff: return addDays(pred.finish, lag - duration, in: calendar)
        case .sf: return addDays(pred.start, lag - duration, in: calendar)
        }
    }

    // MARK: - 后向传播（最晚窗口 / ALAP）

    private static func backwardPass(
        tasks: [TaskItem],
        byID: [UUID: TaskItem],
        durations: [UUID: Double],
        successorMap: [UUID: [TaskItem]],
        anchor: Date,
        cycleSet: Set<UUID>,
        calendar: Calendar
    ) -> [UUID: Window] {
        let order = topologicalOrder(tasks, byID: byID)
        var latest: [UUID: Window] = [:]

        for id in cycleSet {
            let task = byID[id]!
            let duration = durations[id] ?? 1
            let finish = min(anchor, constraintEndUpperBound(task, duration: duration, calendar: calendar))
            latest[id] = Window(start: addDays(finish, -duration, in: calendar), finish: finish)
        }

        for id in order.reversed() {
            let task = byID[id]!
            let duration = durations[id] ?? 1
            var finish = min(anchor, constraintEndUpperBound(task, duration: duration, calendar: calendar))
            for succ in successorMap[id] ?? [] {
                guard let sw = latest[succ.id] else { continue }
                for dep in succ.dependencies where dep.predecessorID == id {
                    finish = min(finish, backwardFinishUpperBound(
                        type: dep.type, lag: dep.lagDays, succ: sw, duration: duration, calendar: calendar
                    ))
                }
            }
            latest[id] = Window(start: addDays(finish, -duration, in: calendar), finish: finish)
        }
        return latest
    }

    /// 本任务作为前驱时，由后继相关性反解出的本任务「最晚结束」上界。
    private static func backwardFinishUpperBound(
        type: TaskDependency.DependencyType, lag: Double, succ: Window, duration: Double,
        calendar: Calendar
    ) -> Date {
        switch type {
        case .fs: return addDays(succ.start, -lag, in: calendar)
        case .ff: return addDays(succ.finish, -lag, in: calendar)
        case .ss: return addDays(succ.start, -lag + duration, in: calendar)
        case .sf: return addDays(succ.finish, -lag + duration, in: calendar)
        }
    }

    // MARK: - 选定安排与宽延

    private static func scheduledTasks(
        tasks: [TaskItem],
        durations: [UUID: Double],
        earliest: [UUID: Window],
        latest: [UUID: Window],
        successorMap: [UUID: [TaskItem]],
        calendar: Calendar
    ) -> [ScheduledTask] {
        tasks.map { task in
            let duration = durations[task.id] ?? 1
            let e = earliest[task.id] ?? Window(start: Date(timeIntervalSince1970: 0), finish: Date(timeIntervalSince1970: 0))
            let l = latest[task.id] ?? e
            let useLatest = task.schedulingPolicy == .alap
            let totalSlack = daysBetween(e.start, l.start, in: calendar)
            let free = freeSlack(
                of: task.id, earliest: earliest, successorMap: successorMap,
                totalSlack: totalSlack, calendar: calendar
            )
            // 选定安排统一收敛到 startDate 下界（S8 / D-021）：ASAP 已由前向传播保证，
            // ALAP 取最晚窗口时可能早于意图开始（后向传播不消费该下界），此处补齐，
            // 避免两条选定路径口径分叉。
            let selectedStart = max(
                useLatest ? l.start : e.start,
                startDateLowerBound(task, calendar: calendar)
            )
            return ScheduledTask(
                taskID: task.id,
                durationDays: duration,
                earliestStart: e.start, earliestFinish: e.finish,
                latestStart: l.start, latestFinish: l.finish,
                scheduledStart: selectedStart,
                scheduledFinish: addDays(selectedStart, duration, in: calendar),
                totalSlackDays: totalSlack,
                freeSlackDays: free
            )
        }
    }

    /// 自由宽延：不推迟任何后继最早安排的最大推迟量（US-E2-03）。无后继时等于总宽延。
    private static func freeSlack(
        of id: UUID,
        earliest: [UUID: Window],
        successorMap: [UUID: [TaskItem]],
        totalSlack: Double,
        calendar: Calendar
    ) -> Double {
        let successors = successorMap[id] ?? []
        guard !successors.isEmpty, let ew = earliest[id] else { return totalSlack }
        var minGap = Double.greatestFiniteMagnitude
        for succ in successors {
            guard let sw = earliest[succ.id] else { continue }
            for dep in succ.dependencies where dep.predecessorID == id {
                let gap: Double
                switch dep.type {
                case .fs: gap = daysBetween(addDays(ew.finish, dep.lagDays, in: calendar), sw.start, in: calendar)
                case .ff: gap = daysBetween(addDays(ew.finish, dep.lagDays, in: calendar), sw.finish, in: calendar)
                case .ss: gap = daysBetween(addDays(ew.start, dep.lagDays, in: calendar), sw.start, in: calendar)
                case .sf: gap = daysBetween(addDays(ew.start, dep.lagDays, in: calendar), sw.finish, in: calendar)
                }
                minGap = min(minGap, gap)
            }
        }
        return max(0, minGap)
    }

    // MARK: - 时限辅助

    /// 任务意图开始日期对最早开始的下界（S8 / D-021）：显式 `startDate` 归一为当天零点后
    /// 作为「开始不早于」下界，不驱动提前。群组由子任务聚合，忽略自身 `startDate`。
    /// 无下界时返回 `ScheduleBounds.noLowerBound`（`.distantPast`）：它是「不存在下界」的
    /// 哨兵而非日期，不可落到排期里（与 `dayZero` 的纪元零点语义区分，M-7 / D-024）。
    private static func startDateLowerBound(_ task: TaskItem, calendar: Calendar) -> Date {
        guard task.kind != .group, let startDate = task.startDate else {
            return ScheduleBounds.noLowerBound
        }
        return calendar.startOfDay(for: startDate)
    }

    /// 时限对最早开始的抬升：startNoEarlierThan 时取其日期，否则不下限。
    private static func constraintStartLowerBound(_ task: TaskItem, calendar: Calendar) -> Date {
        guard case .startNoEarlierThan(let d) = task.constraint else {
            return ScheduleBounds.noLowerBound
        }
        return calendar.startOfDay(for: d)
    }

    /// 时限对最晚结束的压制：endNoLaterThan 直接限结束；startNoLaterThan 限开始+持续。
    private static func constraintEndUpperBound(_ task: TaskItem, duration: Double, calendar: Calendar) -> Date {
        switch task.constraint {
        case .endNoLaterThan(let d):
            return calendar.startOfDay(for: d)
        case .startNoLaterThan(let d):
            return addDays(calendar.startOfDay(for: d), duration, in: calendar)
        default:
            return .distantFuture
        }
    }

    // MARK: - 日期工具（日历日）

    /// 一天的秒数：仅用于小数天余量与日历换算失败时的兜底，不参与整日算术（H-1）。
    private static let secondsPerDay: Double = 86_400

    /// 按日历日加减（夏令时安全）：整日部分走 `Calendar`，跨 DST 切换后仍落在本地零点；
    /// 小数天（投入驱动的非整数持续）的余量按 86 400 秒折算到日内时刻。
    private static func addDays(_ date: Date, _ days: Double, in calendar: Calendar) -> Date {
        let wholeDays = days.rounded(.towardZero)
        let base: Date
        if let whole = Int(exactly: wholeDays), whole != 0,
           let shifted = calendar.date(byAdding: .day, value: whole, to: date) {
            base = shifted
        } else {
            base = date.addingTimeInterval(wholeDays * secondsPerDay)
        }
        let remainder = days - wholeDays
        return remainder == 0 ? base : base.addingTimeInterval(remainder * secondsPerDay)
    }

    /// 日历日差：整日部分取 `Calendar` 的日差（跨 DST 仍是 N 天），余量按 86 400 秒折算。
    private static func daysBetween(_ from: Date, _ to: Date, in calendar: Calendar) -> Double {
        let wholeDays = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        guard let shifted = calendar.date(byAdding: .day, value: wholeDays, to: from) else {
            return to.timeIntervalSince(from) / secondsPerDay
        }
        return Double(wholeDays) + to.timeIntervalSince(shifted) / secondsPerDay
    }
}

/// 排期边界哨兵（F-0717 / D-024）。
///
/// 「无下界」在排期里只有一个取值：`.distantPast`。它与纪元零点（`dayZero`）语义不同——
/// 后者是真实日期，前者只作 `max` 的比较起点，绝不允许落进排期结果。同一语义两种写法
/// （1970 vs distantPast）会让后续改动者误以为二者可互换，故收敛为具名常量。
public enum ScheduleBounds {
    /// 「不存在下界」的哨兵值。
    public static let noLowerBound = Date.distantPast
}

/// 内部窗口（起止对）。
private struct Window {
    var start: Date
    var finish: Date
}
