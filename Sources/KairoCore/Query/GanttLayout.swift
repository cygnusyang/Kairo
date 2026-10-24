import Foundation

/// 甘特缩放档位（F-14-13）：每日占用的像素宽度。
public enum GanttZoom: String, CaseIterable, Codable, Sendable {
    case day, week, month

    public var dayWidth: Double {
        switch self {
        case .day: return 32
        case .week: return 12
        case .month: return 5
        }
    }
}

/// 甘特视图的几何布局（ADR-004 纯逻辑，无 UI 依赖）。
///
/// 时间窗为半开区间 `[windowStart, windowEnd)`；任务条按
/// `(计划开始 − 窗口起点)` 折算横坐标，超出窗口的条保留（由视图裁剪），
/// 以便拖动窗口时条不会在边缘跳变。
public struct GanttLayout: Equatable, Sendable {
    /// 表头层级：上层月/年，下层日/周。
    public enum TickTier: String, Codable, Sendable {
        case upper
        case lower
    }

    public struct Bar: Equatable, Sendable {
        public var taskID: UUID
        public var x: Double
        public var width: Double
        public var isMilestone: Bool
        public var isGroup: Bool
        /// 0...1 完成度，用于条内进度填充。
        public var progress: Double
        /// 重要路径任务（总宽延 ≤ 0）。
        public var isCritical: Bool
    }

    public struct Tick: Equatable, Sendable {
        public var date: Date
        public var x: Double
        public var label: String
        /// 主要刻度（日档位的每月首日、月档位的每年首月）。
        public var isMajor: Bool
        public var tier: TickTier

        public init(date: Date, x: Double, label: String, isMajor: Bool, tier: TickTier = .lower) {
            self.date = date
            self.x = x
            self.label = label
            self.isMajor = isMajor
            self.tier = tier
        }
    }

    /// 非工作时段背景带（F-14-14）。
    public struct Band: Equatable, Sendable {
        public var x: Double
        public var width: Double
    }

    /// 直角折线段（依赖线由多段组成）。
    public struct Segment: Equatable, Sendable {
        public var startX: Double
        public var startY: Double
        public var endX: Double
        public var endY: Double

        public init(startX: Double, startY: Double, endX: Double, endY: Double) {
            self.startX = startX
            self.startY = startY
            self.endX = endX
            self.endY = endY
        }
    }

    /// 一条依赖线：从 `predecessorID` 指向 `successorID`，最后一段终点即箭头位置。
    public struct DependencyRoute: Equatable, Sendable {
        public var predecessorID: UUID
        public var successorID: UUID
        public var type: TaskDependency.DependencyType
        public var isCritical: Bool
        public var segments: [Segment]

        public init(
            predecessorID: UUID,
            successorID: UUID,
            type: TaskDependency.DependencyType,
            isCritical: Bool,
            segments: [Segment]
        ) {
            self.predecessorID = predecessorID
            self.successorID = successorID
            self.type = type
            self.isCritical = isCritical
            self.segments = segments
        }
    }

    public var windowStart: Date
    /// 窗口结束（不含）。
    public var windowEnd: Date
    public var dayWidth: Double
    /// 视图可用宽度（点）。
    public var windowWidth: Double
    /// 内容范围（项目与任务排期边界的并集）；无排期数据时为 nil。
    public var contentStart: Date?
    public var contentEnd: Date?
    public var bars: [Bar]
    /// 两级表头刻度：`tier == .lower` 为日/周标签，`.upper` 为月/年标签。
    public var ticks: [Tick]
    public var bands: [Band]
    /// 今天线横坐标；今天不在窗口内时为 nil。
    public var todayX: Double?
    /// 可见任务之间的依赖路由。
    public var dependencyRoutes: [DependencyRoute]
}

public enum GanttLayoutEngine {
    /// 内容范围：项目边界与全部任务排期边界的并集（F-14-01「缩放以适合项目」）。
    public static func contentRange(
        tasks: [TaskItem],
        schedule: ScheduleResult?,
        calendar: Calendar
    ) -> DateInterval? {
        guard let schedule else { return nil }
        var starts: [Date] = []
        var ends: [Date] = []
        if let projectStart = schedule.projectStart { starts.append(projectStart) }
        if let projectEnd = schedule.projectEnd { ends.append(projectEnd) }
        let unscheduled = Set(schedule.unscheduledTaskIDs)
        for scheduled in schedule.tasks where !unscheduled.contains(scheduled.taskID) {
            starts.append(scheduled.scheduledStart)
            ends.append(scheduled.scheduledFinish)
        }
        guard let firstStart = starts.min(), let lastEnd = ends.max() else { return nil }
        let start = calendar.startOfDay(for: firstStart)
        var end = calendar.startOfDay(for: lastEnd)
        if end <= start {
            end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        }
        return DateInterval(start: start, end: end)
    }

    /// 生成可见区布局。
    ///
    /// - Parameters:
    ///   - windowStart: 可见起点；nil 时取内容范围起点（无内容时取今天）。
    ///   - nonWorkingWeekdays: 非工作星期（`Calendar` 星期序号，1=周日）；默认周六、周日。
    ///     工作日历模型（F-22-06）落地前以此为视图默认。
    ///   - dayWidthOverride: 覆盖档位默认宽度（「缩放以适合项目」传 `fitDayWidth` 结果）。
    ///   - rowIndexByTaskID: 可见行索引；提供时生成依赖路由（缺省不生成）。
    ///   - rowHeight: 行高（点），用于依赖路由的行中心与行边界。
    ///   - today: 今天线基准日；nil 时不生成 `todayX`。
    ///   - locale: 刻度标签的格式化语言（F-0702）。必填且不读 `Locale.current`：
    ///     核心层是纯函数，同一输入必须产生同一输出（ADR-007 / ADR-013）。
    public static func make(
        tasks: [TaskItem],
        schedule: ScheduleResult?,
        calendar: Calendar,
        locale: Locale,
        zoom: GanttZoom,
        viewWidth: Double,
        windowStart requestedStart: Date? = nil,
        nonWorkingWeekdays: Set<Int> = [1, 7],
        dayWidthOverride: Double? = nil,
        rowIndexByTaskID: [UUID: Int] = [:],
        rowHeight: Double = 28,
        today: Date? = nil
    ) -> GanttLayout {
        let content = contentRange(tasks: tasks, schedule: schedule, calendar: calendar)
        let width = max(viewWidth, 1)
        let dayWidth = max(dayWidthOverride ?? zoom.dayWidth, 0.5)
        let windowStart = calendar.startOfDay(
            for: requestedStart ?? content?.start ?? Date()
        )
        var labels = TickLabels(calendar: calendar, locale: locale)
        let windowSeconds = width / dayWidth * 86_400
        let windowEnd = windowStart.addingTimeInterval(windowSeconds)

        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let criticalIDs = Set(
            schedule.map { CriticalPathEngine.compute(result: $0) }
                .map { $0.filter(\.isCritical).map(\.taskID) } ?? []
        )
        var bars: [GanttLayout.Bar] = []
        let unscheduledIDs = Set(schedule?.unscheduledTaskIDs ?? [])
        for scheduled in schedule?.tasks ?? [] where !unscheduledIDs.contains(scheduled.taskID) {
            let start = scheduled.scheduledStart
            let finish = scheduled.scheduledFinish
            guard finish > windowStart, start < windowEnd else { continue }
            let task = tasksByID[scheduled.taskID]
            let x = start.timeIntervalSince(windowStart) / 86_400 * dayWidth
            let barWidth = max(0, finish.timeIntervalSince(start) / 86_400 * dayWidth)
            bars.append(
                GanttLayout.Bar(
                    taskID: scheduled.taskID,
                    x: x,
                    width: barWidth,
                    isMilestone: task?.kind == .milestone || scheduled.durationDays == 0,
                    isGroup: task?.kind == .group,
                    progress: min(max(task?.progress ?? 0, 0), 1),
                    isCritical: criticalIDs.contains(scheduled.taskID)
                )
            )
        }

        var lowerTicks: [GanttLayout.Tick] = []
        var upperTicks: [GanttLayout.Tick] = []
        var upperDates: Set<Date> = []
        var bands: [GanttLayout.Band] = []

        func appendUpper(_ date: Date, x: Double, label: String) {
            let day = calendar.startOfDay(for: date)
            guard upperDates.insert(day).inserted else { return }
            upperTicks.append(GanttLayout.Tick(
                date: day, x: x, label: label, isMajor: true, tier: .upper
            ))
        }

        let firstDay = calendar.component(.day, from: windowStart)
        let firstMonth = calendar.component(.month, from: windowStart)
        switch zoom {
        case .day, .week:
            // 窗口起点不在月初时补当月上层标签，避免上层表头空白。
            if firstDay != 1 {
                appendUpper(
                    windowStart,
                    x: 0,
                    label: firstMonth == 1 ? labels.monthYear(windowStart) : labels.month(windowStart)
                )
            }
        case .month:
            if firstMonth != 1 {
                appendUpper(windowStart, x: 0, label: labels.year(windowStart))
            }
        }

        var cursor = windowStart
        if zoom == .month {
            // 快路径（D-017）：month 档仅在每月 1 日产生刻度/上层标签，非工作带
            // 已隐藏（上方 zoom != .month 守卫）——按月首迭代输出与逐日循环
            // 完全一致，长项目不再逐日扫描（fit 路径窗口可达数千天）。
            var monthCursor = windowStart
            if calendar.component(.day, from: monthCursor) != 1 {
                let daysInMonth = calendar.range(of: .day, in: .month, for: monthCursor)?.count ?? 30
                monthCursor = calendar.date(
                    byAdding: .day,
                    value: daysInMonth - calendar.component(.day, from: monthCursor) + 1,
                    to: monthCursor
                ) ?? monthCursor
            }
            while monthCursor < windowEnd {
                let month = calendar.component(.month, from: monthCursor)
                let offset = monthCursor.timeIntervalSince(windowStart) / 86_400
                let x = offset * dayWidth
                lowerTicks.append(GanttLayout.Tick(
                    date: monthCursor,
                    x: x,
                    label: month == 1 ? labels.year(monthCursor) : labels.month(monthCursor),
                    isMajor: month == 1,
                    tier: .lower
                ))
                if month == 1 {
                    appendUpper(monthCursor, x: x, label: labels.year(monthCursor))
                }
                guard let next = calendar.date(byAdding: .month, value: 1, to: monthCursor) else { break }
                // 归一化回月初零点（跨 DST 边界时与逐日循环的 startOfDay 序列对齐）。
                monthCursor = calendar.startOfDay(for: next)
            }
        } else {
            while cursor < windowEnd {
                let weekday = calendar.component(.weekday, from: cursor)
                let day = calendar.component(.day, from: cursor)
                let month = calendar.component(.month, from: cursor)
                let offset = cursor.timeIntervalSince(windowStart) / 86_400
                let x = offset * dayWidth

                // 非工作带：month 档已走快路径，本循环仅服务 day / week 档。
                if nonWorkingWeekdays.contains(weekday) {
                    bands.append(GanttLayout.Band(x: x, width: dayWidth))
                }

                switch zoom {
                case .day:
                    lowerTicks.append(GanttLayout.Tick(
                        date: cursor, x: x, label: "\(day)", isMajor: false, tier: .lower
                    ))
                    if day == 1 {
                        appendUpper(
                            cursor,
                            x: x,
                            label: month == 1 ? labels.monthYear(cursor) : labels.month(cursor)
                        )
                    }
                case .week:
                    if weekday == calendar.firstWeekday {
                        lowerTicks.append(GanttLayout.Tick(
                            date: cursor, x: x, label: labels.monthDay(cursor), isMajor: false, tier: .lower
                        ))
                    }
                    if day == 1 {
                        appendUpper(
                            cursor,
                            x: x,
                            label: month == 1 ? labels.monthYear(cursor) : labels.month(cursor)
                        )
                    }
                case .month:
                    break // 不可达：month 档已走快路径
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        let todayX: Double? = {
            guard let today else { return nil }
            let day = calendar.startOfDay(for: today)
            guard day >= windowStart, day < windowEnd else { return nil }
            return day.timeIntervalSince(windowStart) / 86_400 * dayWidth
        }()

        let routes = dependencyRoutes(
            tasks: tasks,
            bars: bars,
            rowIndexByTaskID: rowIndexByTaskID,
            rowHeight: rowHeight,
            criticalIDs: criticalIDs
        )

        return GanttLayout(
            windowStart: windowStart,
            windowEnd: windowEnd,
            dayWidth: dayWidth,
            windowWidth: width,
            contentStart: content?.start,
            contentEnd: content?.end,
            bars: bars,
            ticks: lowerTicks + upperTicks,
            bands: bands,
            todayX: todayX,
            dependencyRoutes: routes
        )
    }

    // MARK: - 依赖路由

    /// 生成可见任务之间的直角折线路由（ADR-013）。
    ///
    /// 路由沿行边界横向走线，只在起点/终点行内垂直，避免穿越其他任务条；
    /// 跨行时在中间行选择无条体遮挡的垂直通道。
    private static func dependencyRoutes(
        tasks: [TaskItem],
        bars: [GanttLayout.Bar],
        rowIndexByTaskID: [UUID: Int],
        rowHeight: Double,
        criticalIDs: Set<UUID>
    ) -> [GanttLayout.DependencyRoute] {
        guard !rowIndexByTaskID.isEmpty, rowHeight > 0 else { return [] }
        let barByID = Dictionary(uniqueKeysWithValues: bars.map { ($0.taskID, $0) })
        let rowByID = rowIndexByTaskID
        // 按行分桶：逐条跨行路由只扫描中间行，避免 1000 任务 × 依赖数退化为 O(n²)。
        var barsByRow: [Int: [GanttLayout.Bar]] = [:]
        for bar in bars {
            guard let row = rowByID[bar.taskID] else { continue }
            barsByRow[row, default: []].append(bar)
        }

        func centerY(_ row: Int) -> Double {
            Double(row) * rowHeight + rowHeight / 2
        }

        /// 跨行通道：优先取两端点中点；若中间行有条体遮挡，移到这些条体右侧。
        func laneX(sourceX: Double, targetX: Double, sourceRow: Int, targetRow: Int) -> Double {
            let preferred = (sourceX + targetX) / 2
            let lowRow = min(sourceRow, targetRow) + 1
            let highRow = max(sourceRow, targetRow) - 1
            guard lowRow <= highRow else { return preferred }
            var middleBars: [GanttLayout.Bar] = []
            for row in lowRow...highRow {
                middleBars.append(contentsOf: barsByRow[row] ?? [])
            }
            let collides = middleBars.contains {
                preferred > $0.x - 2 && preferred < $0.x + $0.width + 2
            }
            guard collides else { return preferred }
            let rightEdge = middleBars.map { $0.x + $0.width }.max() ?? preferred
            return rightEdge + 6
        }

        var routes: [GanttLayout.DependencyRoute] = []
        for task in tasks {
            guard let successorRow = rowByID[task.id], let successorBar = barByID[task.id] else {
                continue
            }
            for dependency in task.dependencies {
                guard let predecessorRow = rowByID[dependency.predecessorID],
                      let predecessorBar = barByID[dependency.predecessorID] else { continue }

                let gap: Double = 4
                let sourceX: Double
                let targetX: Double
                switch dependency.type {
                case .fs:
                    sourceX = predecessorBar.x + predecessorBar.width + gap
                    targetX = successorBar.x - gap
                case .ff:
                    sourceX = predecessorBar.x + predecessorBar.width + gap
                    targetX = successorBar.x + successorBar.width + gap
                case .ss:
                    sourceX = predecessorBar.x - gap
                    targetX = successorBar.x - gap
                case .sf:
                    sourceX = predecessorBar.x - gap
                    targetX = successorBar.x + successorBar.width + gap
                }
                let sourceY = centerY(predecessorRow)
                let targetY = centerY(successorRow)

                let segments: [GanttLayout.Segment]
                if predecessorRow == successorRow {
                    if sourceX < targetX {
                        segments = [GanttLayout.Segment(
                            startX: sourceX, startY: sourceY, endX: targetX, endY: targetY
                        )]
                    } else {
                        // 同向后折：从行上边界绕行。
                        let corridorY = Double(predecessorRow) * rowHeight
                        segments = compactSegments([
                            GanttLayout.Segment(
                                startX: sourceX, startY: sourceY, endX: sourceX, endY: corridorY
                            ),
                            GanttLayout.Segment(
                                startX: sourceX, startY: corridorY, endX: targetX, endY: corridorY
                            ),
                            GanttLayout.Segment(
                                startX: targetX, startY: corridorY, endX: targetX, endY: targetY
                            )
                        ])
                    }
                } else {
                    let downward = successorRow > predecessorRow
                    let sourceBoundary = downward
                        ? Double(predecessorRow + 1) * rowHeight
                        : Double(predecessorRow) * rowHeight
                    let targetBoundary = downward
                        ? Double(successorRow) * rowHeight
                        : Double(successorRow + 1) * rowHeight
                    let lane = laneX(
                        sourceX: sourceX,
                        targetX: targetX,
                        sourceRow: predecessorRow,
                        targetRow: successorRow
                    )
                    var path: [GanttLayout.Segment] = [
                        GanttLayout.Segment(
                            startX: sourceX, startY: sourceY, endX: sourceX, endY: sourceBoundary
                        )
                    ]
                    if sourceBoundary == targetBoundary {
                        // 相邻行：行边界即共同走廊。
                        path.append(GanttLayout.Segment(
                            startX: sourceX, startY: sourceBoundary, endX: targetX, endY: targetBoundary
                        ))
                    } else {
                        path.append(GanttLayout.Segment(
                            startX: sourceX, startY: sourceBoundary, endX: lane, endY: sourceBoundary
                        ))
                        path.append(GanttLayout.Segment(
                            startX: lane, startY: sourceBoundary, endX: lane, endY: targetBoundary
                        ))
                        path.append(GanttLayout.Segment(
                            startX: lane, startY: targetBoundary, endX: targetX, endY: targetBoundary
                        ))
                    }
                    path.append(GanttLayout.Segment(
                        startX: targetX, startY: targetBoundary, endX: targetX, endY: targetY
                    ))
                    segments = compactSegments(path)
                }

                routes.append(GanttLayout.DependencyRoute(
                    predecessorID: dependency.predecessorID,
                    successorID: task.id,
                    type: dependency.type,
                    isCritical: criticalIDs.contains(dependency.predecessorID)
                        && criticalIDs.contains(task.id),
                    segments: segments
                ))
            }
        }
        return routes
    }

    /// 去掉零长度线段：端点重合段无绘制意义，且会干扰命中与箭头方向判断。
    private static func compactSegments(_ segments: [GanttLayout.Segment]) -> [GanttLayout.Segment] {
        segments.filter {
            abs($0.endX - $0.startX) > 0.001 || abs($0.endY - $0.startY) > 0.001
        }
    }

    /// 「缩放以适合项目」：让内容范围恰好铺满可用宽度（F-14-13）。
    public static func fitDayWidth(
        contentRange: DateInterval,
        viewWidth: Double,
        calendar: Calendar
    ) -> Double {
        let days = contentRange.duration / 86_400
        guard days > 0 else { return GanttZoom.day.dayWidth }
        return max(viewWidth, 1) / days
    }

    /// 拖动日期标头后的窗口起点（F-14-13）：向右拖动使时间窗左移，
    /// 向左拖动使时间窗右移。
    public static func pannedWindowStart(
        from anchor: Date,
        translationX: Double,
        dayWidth: Double
    ) -> Date {
        let days = -translationX / max(dayWidth, 0.5)
        return anchor.addingTimeInterval(days * 86_400)
    }
}

/// 刻度标签格式化（F-0702）：语言与日历都来自注入，核心层不读进程级 Locale。
///
/// 用 `setLocalizedDateFormatFromTemplate` 而不是硬编码 pattern：模板只声明「要哪些字段」，
/// 字段顺序、分隔符、是否出现「年 / 月」由 CLDR 按语言决定。模板选择对齐 v0.8.5 的中文标签：
///   - 月 + 年（跨年首月）：yMMM → zh「2026年1月」/ en「Jan 2026」
///   - 月份：MMM → zh「1月」/ en「Jan」
///   - 年份：y → zh「2026年」/ en「2026」
///   - 月 / 日：Md → zh「3/8」/ en「3/8」
/// 日号（日档下层刻度）保留十进制数字：它是数量而非语言文本，两种目标语言都用 ASCII 数字。
struct TickLabels {
    private let calendar: Calendar
    private let locale: Locale
    private var cache: [String: DateFormatter] = [:]

    init(calendar: Calendar, locale: Locale) {
        self.calendar = calendar
        self.locale = locale
    }

    mutating func monthYear(_ date: Date) -> String { label("yMMM", date) }
    mutating func month(_ date: Date) -> String { label("MMM", date) }
    mutating func year(_ date: Date) -> String { label("y", date) }
    mutating func monthDay(_ date: Date) -> String { label("Md", date) }

    /// 同一模板只建一次 formatter：逐日循环里重复 `DateFormatter()` 是纯浪费。
    private mutating func label(_ template: String, _ date: Date) -> String {
        if let cached = cache[template] { return cached.string(from: date) }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        cache[template] = formatter
        return formatter.string(from: date)
    }
}
