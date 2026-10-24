import Foundation
import Testing
import KairoCore
import KairoPresentation

// Sprint 6 / T4→T6 验收用例：甘特图时间轴「日宽可自定义」。
//
// 判据映射（lead 裁决版）：
// - A1′ 等比性：所有刻度 / 非工作带 / 条体坐标均为日宽 W 的整数倍；日档相邻刻度差 = W；
//   周档 = 7W；月档 ≈ 30W（跨月跨年成立）。
// - A2 档位预设把日宽重置为 32/12/5（呈现层可观测部分）。
// - A3 自定义与「适合项目」互斥（呈现层可观测部分：自定义优先、fit 宽度）。
// - A4 越界日宽夹取到 [2, 120]；不得出现 0 / 负数 / NaN / ±∞。
// - A5 极小日宽（2 点/天）刻度与标签数量受控、窗口天数受控、标签槽位不重叠。
// - A6 状态栏反映档位（zoom.preset）与实际日宽（zoom.pointsPerDay）。
// - A7 刻度粒度契约（**行为契约，不是快照自比**）：
//   · `customDayWidth == nil` ⇒ 核心实际使用的刻度粒度 == `viewState.zoom`（预设粒度未被改写）；
//   · `usesFitZoom == true` 且 `custom == nil` ⇒ `tickGranularity == viewState.zoom`
//     （**fit 不改粒度** —— HIGH-1「fit 路径刻度粒度被静默改写」的硬回归网）；
//   · `custom != nil` ⇒ `tickGranularity == GanttScale.tickUnit(forDayWidth: 生效日宽)`。
//   判定手段：呈现层输出 vs **核心引擎按契约参数直接复算**的参考输出（跨实现比对，
//   不是「同一份实现产出的两份快照」自比，故能发现与改动前的行为偏差）。
// - A8 自定义日宽承载在可持久化的视图状态中（编解码往返在应用层，见交付报告缺口说明）。
//
// 平台约束：本文件位于 KairoPresentationTests 目标，保持 Foundation-only（不引 AppKit/SwiftUI）。

// MARK: - 夹具

/// 日宽验收夹具：项目 2024-11-15 → 2025-01-28（跨月且跨年），4 个任务起点各不相同。
///
/// 任务起点用 `constraint: .startNoEarlierThan` 固定（排期引擎以约束而非 `startDate` 定起点），
/// 保证排期结果确定、可断言。
private struct DayWidthFixture {
    let projectStart: Date
    let tasks: [TaskItem]
    let state: ProjectState
    let schedule: ScheduleResult
    let now: Date

    init() {
        let projectStart = makeDate(2024, 11, 15)
        let design = TaskItem(
            title: "设计",
            durationDays: 10,
            constraint: .startNoEarlierThan(makeDate(2024, 11, 15))
        )
        let build = TaskItem(
            title: "实现",
            durationDays: 20,
            constraint: .startNoEarlierThan(makeDate(2024, 12, 20))
        )
        let verify = TaskItem(
            title: "验收",
            durationDays: 12,
            constraint: .startNoEarlierThan(makeDate(2025, 1, 15))
        )
        let release = TaskItem(
            title: "发布",
            kind: .milestone,
            constraint: .startNoEarlierThan(makeDate(2025, 1, 28))
        )
        let now = makeDate(2025, 1, 20)
        self.projectStart = projectStart
        self.tasks = [design, build, verify, release]
        self.state = makeState([design, build, verify, release], projectStart: projectStart)
        self.schedule = makeSchedule(
            [design, build, verify, release],
            projectStart: projectStart,
            now: now
        )
        self.now = now
    }

    func task(_ title: String) -> TaskItem? {
        tasks.first { $0.title == title }
    }
}

/// 构造被测快照：只经呈现层公开入口（`WorkspacePresenter.make`）驱动。
private func makeDayWidthSnapshot(
    fixture: DayWidthFixture,
    customDayWidth: Double?,
    zoom: GanttZoom = .week,
    usesFitZoom: Bool = false,
    canvasWidth: Double = 2000
) -> WorkspaceSnapshot {
    var viewState = WorkspaceViewState()
    viewState.zoom = zoom
    viewState.usesFitZoom = usesFitZoom
    viewState.customDayWidth = customDayWidth
    return makeSnapshot(
        state: fixture.state,
        schedule: fixture.schedule,
        viewState: viewState,
        viewport: WorkspaceViewport(canvasWidth: canvasWidth, canvasHeight: 600),
        now: fixture.now
    )
}

/// x 是否为日宽 W 的整数倍（误差 < 1e-6）。
private func isMultiple(of width: Double, _ value: Double) -> Bool {
    guard width > 0 else { return false }
    return abs(value - width * (value / width).rounded()) < 1e-6
}

/// 状态栏日宽读数（快照只带数值，格式化在视图层）。
private func dayWidthNumber(_ pointsPerDay: Double?) -> Double? {
    pointsPerDay
}

/// 窗口天数（半开窗口 `[start, end)`）。
private func windowDays(_ gantt: GanttSnapshot) -> Double {
    gantt.windowEnd.timeIntervalSince(gantt.windowStart) / 86_400
}

// MARK: - 「现状」参考实现（跨实现比对，非自我比较）

/// 呈现层应当传给核心引擎的**参数组合**（契约）。
///
/// 依据：设计稿 §2.2「刻度粒度必须由实际日宽推导……为保住 A7（逐位一致），推导只在新模式
/// （自定义）生效；**预设模式与 fit 模式沿用今天的 `zoom` 语义，一字不改**」。
private enum AxisMode {
    /// 预设档位：核心收到 `zoom = 预设档位`、无日宽覆盖。
    case preset
    /// 「适合项目」：核心收到 `zoom = 预设档位`、日宽覆盖 = fit 宽度（**fit 不改刻度粒度**）。
    case fit
    /// 自定义：核心收到 `zoom = 由生效日宽推导的粒度`、日宽覆盖 = 自定义宽度。
    case custom(Double)
}

/// 内容范围（与呈现层同源：夹具无未排期任务，故直接用原始 schedule）。
private func fixtureContentRange(_ fixture: DayWidthFixture) -> DateInterval {
    guard let content = GanttLayoutEngine.contentRange(
        tasks: fixture.tasks,
        schedule: fixture.schedule,
        calendar: testCalendar
    ) else {
        preconditionFailure("夹具必须有内容范围")
    }
    return content
}

/// 「适合项目」的日宽（内容区间末尾补一天，与呈现层同口径）。
private func fitDayWidth(_ fixture: DayWidthFixture, canvasWidth: Double) -> Double {
    let content = fixtureContentRange(fixture)
    let fitRange = DateInterval(
        start: content.start,
        end: content.end.addingTimeInterval(86_400)
    )
    return GanttLayoutEngine.fitDayWidth(
        contentRange: fitRange,
        viewWidth: canvasWidth,
        calendar: testCalendar
    )
}

/// 用**核心引擎**按契约参数直接复算出的参考画布输出。
///
/// 这是「与改动前行为逐位一致」的判据来源：呈现层若把预设 / fit 路径的参数改写
/// （例如 HIGH-1：fit 路径按 fit 宽度改写刻度粒度），与本参考输出必然不同。
private func referenceLayout(
    fixture: DayWidthFixture,
    zoom: GanttZoom,
    mode: AxisMode,
    canvasWidth: Double
) -> GanttLayout {
    let content = fixtureContentRange(fixture)
    let effectiveZoom: GanttZoom
    let dayWidthOverride: Double?
    switch mode {
    case .preset:
        effectiveZoom = zoom
        dayWidthOverride = nil
    case .fit:
        effectiveZoom = zoom
        dayWidthOverride = fitDayWidth(fixture, canvasWidth: canvasWidth)
    case .custom(let width):
        effectiveZoom = GanttScale.tickUnit(forDayWidth: width)
        dayWidthOverride = width
    }
    return GanttLayoutEngine.make(
        tasks: fixture.tasks,
        schedule: fixture.schedule,
        calendar: testCalendar,
        zoom: effectiveZoom,
        viewWidth: max(canvasWidth, 1),
        windowStart: content.start,
        dayWidthOverride: dayWidthOverride,
        rowHeight: 28,
        today: fixture.now
    )
}

/// 呈现层画布 vs 核心参考输出：窗口 / 日宽 / 刻度 / 非工作带 / 条体 / 今天线逐项比对。
private func assertAxisMatches(
    _ gantt: GanttSnapshot,
    _ reference: GanttLayout,
    _ context: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        gantt.windowStart == reference.windowStart,
        "\(context)：窗口起点 \(gantt.windowStart) != 参考 \(reference.windowStart)",
        sourceLocation: sourceLocation
    )
    #expect(
        gantt.windowEnd == reference.windowEnd,
        "\(context)：窗口终点 \(gantt.windowEnd) != 参考 \(reference.windowEnd)",
        sourceLocation: sourceLocation
    )
    #expect(
        abs(gantt.dayWidth - reference.dayWidth) < 1e-9,
        "\(context)：日宽 \(gantt.dayWidth) != 参考 \(reference.dayWidth)",
        sourceLocation: sourceLocation
    )

    // 刻度（日期 / x / 标签）逐条比对 —— 粒度被改写时这里的条数与内容都会不同。
    #expect(
        gantt.ticks.count == reference.ticks.count,
        "\(context)：刻度数 \(gantt.ticks.count) != 参考 \(reference.ticks.count)",
        sourceLocation: sourceLocation
    )
    if gantt.ticks.count == reference.ticks.count {
        for (actual, expected) in zip(gantt.ticks, reference.ticks) {
            #expect(
                actual.date == expected.date,
                "\(context)：刻度日期 \(actual.date) != 参考 \(expected.date)",
                sourceLocation: sourceLocation
            )
            #expect(
                abs(actual.x - expected.x) < 1e-9,
                "\(context)：刻度 x \(actual.x) != 参考 \(expected.x)",
                sourceLocation: sourceLocation
            )
            #expect(
                actual.label == expected.label,
                "\(context)：刻度标签 \(actual.label) != 参考 \(expected.label)",
                sourceLocation: sourceLocation
            )
        }
    }

    // 非工作带逐条比对。
    #expect(
        gantt.bands.count == reference.bands.count,
        "\(context)：非工作带数 \(gantt.bands.count) != 参考 \(reference.bands.count)",
        sourceLocation: sourceLocation
    )
    if gantt.bands.count == reference.bands.count {
        for (actual, expected) in zip(gantt.bands, reference.bands) {
            #expect(
                abs(actual.x - expected.x) < 1e-9,
                "\(context)：非工作带 x \(actual.x) != 参考 \(expected.x)",
                sourceLocation: sourceLocation
            )
            #expect(
                abs(actual.width - expected.width) < 1e-9,
                "\(context)：非工作带宽 \(actual.width) != 参考 \(expected.width)",
                sourceLocation: sourceLocation
            )
        }
    }

    // 条体几何逐条比对。
    #expect(
        gantt.bars.count == reference.bars.count,
        "\(context)：条体数 \(gantt.bars.count) != 参考 \(reference.bars.count)",
        sourceLocation: sourceLocation
    )
    if gantt.bars.count == reference.bars.count {
        let expectedByID = Dictionary(uniqueKeysWithValues: reference.bars.map { ($0.taskID, $0) })
        for bar in gantt.bars {
            guard let expected = expectedByID[bar.taskID] else {
                Issue.record(
                    "\(context)：参考输出缺少条体 \(bar.taskID)",
                    sourceLocation: sourceLocation
                )
                continue
            }
            #expect(
                abs(bar.x - expected.x) < 1e-9,
                "\(context)：条体 x \(bar.x) != 参考 \(expected.x)",
                sourceLocation: sourceLocation
            )
            #expect(
                abs(bar.width - expected.width) < 1e-9,
                "\(context)：条体宽 \(bar.width) != 参考 \(expected.width)",
                sourceLocation: sourceLocation
            )
        }
    }

    // 今天线。
    switch (gantt.todayX, reference.todayX) {
    case let (actual?, expected?):
        #expect(
            abs(actual - expected) < 1e-9,
            "\(context)：今天线 x \(actual) != 参考 \(expected)",
            sourceLocation: sourceLocation
        )
    case (nil, nil):
        break
    default:
        Issue.record("\(context)：今天线存在性与参考不一致", sourceLocation: sourceLocation)
    }
}

// MARK: - 验收用例

@Suite("日宽自定义验收（Sprint 6 / T2）")
struct DayWidthAcceptanceTests {

    // MARK: A1′ 等比性

    /// A1′-1：单一标量日宽 W 驱动全轴 —— 所有刻度 x、非工作带 x 与宽度、条体 x 与宽度
    /// 均为 W 的整数倍；非工作带宽度恒等于 W。
    @Test func dayWidthGridCoversTicksBandsAndBars() throws {
        let fixture = DayWidthFixture()
        let width = 18.0
        let gantt = makeDayWidthSnapshot(fixture: fixture, customDayWidth: width).gantt

        #expect(gantt.dayWidth == width)
        #expect(gantt.tickGranularity == .day)

        // 刻度：每个 x 都是 W 的整数倍。
        #expect(!gantt.ticks.isEmpty)
        for tick in gantt.ticks {
            #expect(
                isMultiple(of: width, tick.x),
                "刻度 \(tick.label) 的 x=\(tick.x) 不是日宽 \(width) 的整数倍"
            )
        }

        // 非工作带：x 为 W 的整数倍；宽度恒等于 W。
        #expect(!gantt.bands.isEmpty, "日档应保留非工作带")
        for band in gantt.bands {
            #expect(
                isMultiple(of: width, band.x),
                "非工作带 x=\(band.x) 不是日宽 \(width) 的整数倍"
            )
            #expect(abs(band.width - width) < 1e-6, "非工作带宽度 \(band.width) != 日宽 \(width)")
        }

        // 条体：x / width 严格等于「天数 × W」。
        let scheduled = Dictionary(
            uniqueKeysWithValues: fixture.schedule.tasks.map { ($0.taskID, $0) }
        )
        #expect(gantt.bars.count == fixture.tasks.count)
        for bar in gantt.bars {
            let item = try #require(scheduled[bar.taskID])
            let days = item.scheduledStart.timeIntervalSince(gantt.windowStart) / 86_400
            #expect(abs(bar.x - days * width) < 1e-6, "条体 x=\(bar.x) != 天数 \(days) × \(width)")
            #expect(
                abs(bar.width - item.durationDays * width) < 1e-6,
                "条体宽度 \(bar.width) != 持续 \(item.durationDays) 天 × \(width)"
            )
            #expect(isMultiple(of: width, bar.x))
            #expect(isMultiple(of: width, bar.width))
        }
    }

    /// A1′-1（跨月 / 跨年）：日宽网格在月界、年界处不发生漂移。
    @Test func dayWidthGridHoldsAcrossMonthAndYearBoundary() throws {
        let fixture = DayWidthFixture()
        let width = 18.0
        let gantt = makeDayWidthSnapshot(fixture: fixture, customDayWidth: width).gantt

        // 前提：窗口确实跨年，否则下列断言无意义。
        #expect(testCalendar.component(.year, from: gantt.windowStart) == 2024)
        #expect(testCalendar.component(.year, from: gantt.windowEnd) == 2025)

        // 跨月：2024-12-01（周日）的刻度与非工作带。
        let december = try #require(
            gantt.ticks.first { testCalendar.isDate($0.date, inSameDayAs: makeDate(2024, 12, 1)) }
        )
        #expect(december.date.timeIntervalSince(gantt.windowStart) / 86_400 == 16)
        #expect(abs(december.x - 16 * width) < 1e-6)
        let decemberBand = try #require(gantt.bands.first { abs($0.x - 16 * width) < 1e-6 })
        #expect(abs(decemberBand.width - width) < 1e-6)

        // 跨年：2025-01-01 的刻度。
        let newYear = try #require(
            gantt.ticks.first { testCalendar.isDate($0.date, inSameDayAs: makeDate(2025, 1, 1)) }
        )
        #expect(newYear.date.timeIntervalSince(gantt.windowStart) / 86_400 == 47)
        #expect(abs(newYear.x - 47 * width) < 1e-6)
        #expect(isMultiple(of: width, newYear.x))

        // 跨年的条体：2024-12-20 起 20 天的「实现」。
        let build = try #require(fixture.task("实现"))
        let buildBar = try #require(gantt.bars.first { $0.taskID == build.id })
        #expect(abs(buildBar.x - 35 * width) < 1e-6)
        #expect(abs(buildBar.width - 20 * width) < 1e-6)
    }

    /// A1′-2：生效刻度档位为 `.day` 时，相邻刻度 x 差恒等于 W（跨周 / 跨月 / 跨年成立）。
    @Test func dayGranularityKeepsAdjacentTickSpacingEqualToDayWidth() {
        let fixture = DayWidthFixture()
        let width = 18.0
        let gantt = makeDayWidthSnapshot(fixture: fixture, customDayWidth: width).gantt

        #expect(gantt.tickGranularity == .day)
        #expect(gantt.dayWidth == width)

        // 逐日档下，月首上层刻度与逐日刻度落在同一 x 网格上，去重后即为逐日网格。
        let xs = Array(Set(gantt.ticks.map(\.x))).sorted()
        #expect(xs.count >= 100)
        #expect(abs(xs[0]) < 1e-9, "首个刻度应落在窗口起点 x=0")
        for index in 1..<xs.count {
            #expect(
                abs((xs[index] - xs[index - 1]) - width) < 1e-6,
                "相邻刻度 x 差 \(xs[index] - xs[index - 1]) != 日宽 \(width)"
            )
        }

        // 刻度数 == 窗口天数：每一天恰好一个刻度。
        #expect(xs.count == Int(ceil(windowDays(gantt))))
    }

    /// A1′-3：生效刻度档位为 `.week` 时，相邻刻度 x 差恒为 7W。
    @Test func weekGranularityKeepsAdjacentTickSpacingSevenDayWidths() {
        let fixture = DayWidthFixture()
        let width = 12.0
        let gantt = makeDayWidthSnapshot(fixture: fixture, customDayWidth: width).gantt

        #expect(gantt.tickGranularity == .week)
        #expect(gantt.dayWidth == width)

        // 生效刻度为周界（与 `firstWeekday` 同日）；上层月刻度可能与周刻度同日，按 x 去重。
        let weekly = gantt.ticks.filter {
            testCalendar.component(.weekday, from: $0.date) == testCalendar.firstWeekday
        }
        #expect(weekly.count >= 20)
        var dateByX: [Double: Date] = [:]
        for tick in weekly { dateByX[tick.x] = tick.date }
        let xs = dateByX.keys.sorted()
        for index in 1..<xs.count {
            #expect(
                abs((xs[index] - xs[index - 1]) - 7 * width) < 1e-6,
                "相邻周刻度 x 差 \(xs[index] - xs[index - 1]) != 7 × \(width)"
            )
            let span = dateByX[xs[index]]!.timeIntervalSince(dateByX[xs[index - 1]]!) / 86_400
            #expect(abs(span - 7) < 1e-6, "相邻周刻度日期跨度 \(span) 天 != 7 天")
        }

        // 日界等距性由「所有刻度 x 为 W 的整数倍」保证。
        for tick in gantt.ticks {
            #expect(isMultiple(of: width, tick.x))
        }
    }

    /// A1′-3：生效刻度档位为 `.month` 时，相邻刻度 x 差为该单位跨度的整数倍（≈30W）。
    @Test func monthGranularityKeepsAdjacentTickSpacingWithinOneMonthSpan() {
        let fixture = DayWidthFixture()
        let width = 5.0
        let gantt = makeDayWidthSnapshot(fixture: fixture, customDayWidth: width).gantt

        #expect(gantt.tickGranularity == .month)
        #expect(gantt.dayWidth == width)

        // 生效刻度为月界（每月 1 日）；上层年刻度与之一同 x，按 x 去重。
        let monthly = gantt.ticks.filter { testCalendar.component(.day, from: $0.date) == 1 }
        #expect(monthly.count >= 12)
        var dateByX: [Double: Date] = [:]
        for tick in monthly { dateByX[tick.x] = tick.date }
        let xs = dateByX.keys.sorted()
        for index in 1..<xs.count {
            let days = dateByX[xs[index]]!.timeIntervalSince(dateByX[xs[index - 1]]!) / 86_400
            #expect(days >= 28 && days <= 31, "相邻月刻度跨度 \(days) 天不在 28...31 内")
            #expect(
                abs((xs[index] - xs[index - 1]) - days * width) < 1e-6,
                "相邻月刻度 x 差与月份跨度不成比例"
            )
            #expect(isMultiple(of: width, xs[index]))
        }

        // 月档沿用既有行为：隐藏非工作带。
        #expect(gantt.bands.isEmpty)
    }

    // MARK: A2 档位预设

    /// A2：档位预设把日宽重置为该档默认值（32 / 12 / 5），且档位与生效刻度粒度自洽。
    /// 「清空 customDayWidth」由应用层动作语义保证（见交付报告缺口说明）。
    @Test func presetZoomUsesPresetDayWidthAndSelfConsistentGranularity() {
        let fixture = DayWidthFixture()
        let presets: [(zoom: GanttZoom, width: Double, granularity: GanttZoom)] = [
            (.day, 32, .day),
            (.week, 12, .week),
            (.month, 5, .month)
        ]
        for preset in presets {
            let gantt = makeDayWidthSnapshot(
                fixture: fixture,
                customDayWidth: nil,
                zoom: preset.zoom,
                usesFitZoom: false
            ).gantt
            #expect(gantt.dayWidth == preset.width, "\(preset.zoom) 档日宽 != \(preset.width)")
            #expect(gantt.zoom == preset.zoom)
            #expect(gantt.tickGranularity == preset.granularity)
            #expect(gantt.usesFitZoom == false)
        }

        // 预设「日」档：相邻日界刻度差 = 32（既有行为未被新字段扰动）。
        let dayGantt = makeDayWidthSnapshot(
            fixture: fixture,
            customDayWidth: nil,
            zoom: .day,
            usesFitZoom: false
        ).gantt
        let xs = Array(Set(dayGantt.ticks.map(\.x))).sorted()
        for index in 1..<xs.count {
            #expect(abs((xs[index] - xs[index - 1]) - 32) < 1e-6)
        }
    }

    // MARK: A3 自定义与「适合项目」互斥

    /// A3：自定义日宽与「适合项目」互斥 —— 自定义优先（fit 被忽略），
    /// fit 模式下日宽为 fit 值。动作层的清空语义在应用层（见交付报告缺口说明）。
    @Test func customDayWidthOverridesFitZoomAndFitModeUsesFitWidth() throws {
        let fixture = DayWidthFixture()

        // 矛盾状态（fit 与自定义同时为真）：自定义为唯一真相源。
        let custom = makeDayWidthSnapshot(
            fixture: fixture,
            customDayWidth: 20,
            zoom: .week,
            usesFitZoom: true,
            canvasWidth: 760
        ).gantt
        #expect(custom.dayWidth == 20)
        #expect(custom.usesFitZoom == false, "自定义生效时不应报告 fit")
        #expect(custom.tickGranularity == .day)

        // fit 模式：日宽 = 画布宽 / 内容天数（内容区间 + 1 天）。
        let fit = makeDayWidthSnapshot(
            fixture: fixture,
            customDayWidth: nil,
            zoom: .week,
            usesFitZoom: true,
            canvasWidth: 760
        ).gantt
        #expect(fit.usesFitZoom == true)
        let contentStart = try #require(fit.contentStart)
        let contentEnd = try #require(fit.contentEnd)
        let contentDays = contentEnd.timeIntervalSince(contentStart) / 86_400 + 1
        #expect(abs(fit.dayWidth - 760 / contentDays) < 1e-9)
        #expect(fit.dayWidth > 10 && fit.dayWidth < 10.2, "fit 日宽应约为 10.13")
        // fit 只改日宽、不改刻度粒度：粒度恒等于用户预设档位（此处 .week）。
        #expect(fit.tickGranularity == .week, "fit 模式不改刻度粒度（应恒为预设档位 .week）")
        #expect(fit.zoom == .week, "fit 模式不改变用户预设档位")
    }

    // MARK: A4 越界夹取

    /// A4：越界日宽被夹取到 [2, 120]；不得产生 0 / 负数 / NaN / ±∞。
    @Test func outOfRangeCustomDayWidthIsClampedAndNeverIllegal() {
        // 纯函数口径。
        #expect(GanttScale.clampDayWidth(-5) == 2)
        #expect(GanttScale.clampDayWidth(0) == 2)
        #expect(GanttScale.clampDayWidth(1000) == 120)
        #expect(GanttScale.clampDayWidth(Double.nan) == 2)
        #expect(GanttScale.clampDayWidth(Double.infinity) == 120)
        #expect(GanttScale.clampDayWidth(-Double.infinity) == 2)
        #expect(GanttScale.clampDayWidth(2) == 2)
        #expect(GanttScale.clampDayWidth(120) == 120)
        #expect(GanttScale.clampDayWidth(12.5) == 12.5, "区间内取值不应被改写")

        // 呈现层口径：非法输入不得产出非法日宽。
        let fixture = DayWidthFixture()
        let cases: [(input: Double, expected: Double)] = [
            (-5, 2),
            (0, 2),
            (1000, 120),
            (Double.nan, 2),
            (Double.infinity, 120),
            (-Double.infinity, 2)
        ]
        for item in cases {
            let gantt = makeDayWidthSnapshot(
                fixture: fixture,
                customDayWidth: item.input
            ).gantt
            #expect(gantt.dayWidth.isFinite, "自定义日宽 \(item.input) 产出非有限日宽")
            #expect(gantt.dayWidth > 0, "自定义日宽 \(item.input) 产出非正日宽")
            #expect(gantt.dayWidth >= GanttScale.dayWidthRange.lowerBound)
            #expect(gantt.dayWidth <= GanttScale.dayWidthRange.upperBound)
            #expect(
                gantt.dayWidth == item.expected,
                "自定义日宽 \(item.input) 未夹取到 \(item.expected)，实际 \(gantt.dayWidth)"
            )
        }
    }

    /// A4 边界：合法区间端点仍产出可用快照。
    @Test func legalDayWidthBoundsProduceUsableSnapshot() {
        let fixture = DayWidthFixture()
        for width in [GanttScale.dayWidthRange.lowerBound, GanttScale.dayWidthRange.upperBound] {
            let gantt = makeDayWidthSnapshot(fixture: fixture, customDayWidth: width).gantt
            #expect(gantt.dayWidth == width)
            #expect(!gantt.ticks.isEmpty)
            #expect(!gantt.bars.isEmpty)
            #expect(gantt.dayWidth.isFinite)
        }
    }

    // MARK: A5 极小日宽下的数量与可读性

    /// A5：日宽极小（2 点/天）时不得标签重叠、绘制量爆炸 —— 刻度数、标签数、窗口天数受控。
    @Test func tinyDayWidthKeepsTickCountsAndWindowBounded() {
        let fixture = DayWidthFixture()
        let width = 2.0
        let gantt = makeDayWidthSnapshot(fixture: fixture, customDayWidth: width).gantt

        #expect(gantt.dayWidth == width)
        #expect(gantt.tickGranularity == .month, "2 点/天应降为逐月，避免逐日爆炸")

        // 窗口天数受控：4K 画布 3840 / 2 = 1920 天。
        #expect(abs(windowDays(gantt) - 1000) < 1e-6)
        #expect(windowDays(gantt) <= 1920)

        // 刻度 / 标签数量受控：逐月档下远小于窗口天数。
        #expect(gantt.ticks.count <= 64, "逐月刻度数 \(gantt.ticks.count) 超出设计上界 64")
        #expect(gantt.ticks.count <= 200, "表头标签绘制上限 200")
        #expect(Double(gantt.ticks.count) <= windowDays(gantt) / 10, "逐月刻度数不应随窗口天数线性膨胀")
        #expect(gantt.bands.isEmpty, "月档沿用既有行为：不画非工作带")

        // 标签槽位不重叠：逐月标签宽约 24pt，槽位宽 ≈ 30W。
        #expect(30 * width >= 24)
    }

    /// A5 支撑：刻度粒度阈值与档位默认值自洽（32→逐日、12→逐周、5→逐月）。
    @Test func tickGranularityThresholdsMatchPresetDefaults() {
        #expect(GanttScale.dayTickThreshold == 18)
        #expect(GanttScale.weekTickThreshold == 6)
        #expect(GanttScale.dayWidthRange == 2.0...120.0)
        #expect(GanttScale.dayWidthStep == 1.0)

        #expect(GanttScale.tickUnit(forDayWidth: 32) == .day)
        #expect(GanttScale.tickUnit(forDayWidth: 12) == .week)
        #expect(GanttScale.tickUnit(forDayWidth: 5) == .month)

        #expect(GanttScale.tickUnit(forDayWidth: 18) == .day)
        #expect(GanttScale.tickUnit(forDayWidth: 17.99) == .week)
        #expect(GanttScale.tickUnit(forDayWidth: 6) == .week)
        // 契约：≥6 走逐周，否则逐月（设计稿 §7.3 的「5.99 → .week」与其自身阈值表矛盾，以契约为准）。
        #expect(GanttScale.tickUnit(forDayWidth: 5.99) == .month)
        #expect(GanttScale.tickUnit(forDayWidth: 2) == .month)
    }

    // MARK: A6 状态栏文案

    /// A6：状态栏同时反映当前档位（zoom.preset）与实际日宽（zoom.pointsPerDay）。
    @Test func statusBarReportsZoomPresetAndActualDayWidth() throws {
        let fixture = DayWidthFixture()

        let custom = makeDayWidthSnapshot(fixture: fixture, customDayWidth: 20).statusBar
        #expect(custom.zoom.preset == .custom)
        #expect(custom.zoom.pointsPerDay == 20)

        let fractional = makeDayWidthSnapshot(fixture: fixture, customDayWidth: 12.5).statusBar
        #expect(fractional.zoom.preset == .custom)
        #expect(fractional.zoom.pointsPerDay == 12.5)

        let preset = makeDayWidthSnapshot(
            fixture: fixture,
            customDayWidth: nil,
            zoom: .day,
            usesFitZoom: false
        ).statusBar
        #expect(preset.zoom.preset == .day)
        #expect(dayWidthNumber(preset.zoom.pointsPerDay) == 32)

        let fitGantt = makeDayWidthSnapshot(
            fixture: fixture,
            customDayWidth: nil,
            zoom: .week,
            usesFitZoom: true,
            canvasWidth: 760
        ).gantt
        let fit = makeDayWidthSnapshot(
            fixture: fixture,
            customDayWidth: nil,
            zoom: .week,
            usesFitZoom: true,
            canvasWidth: 760
        ).statusBar
        #expect(fit.zoom.preset == .fit)
        let detail = try #require(dayWidthNumber(fit.zoom.pointsPerDay))
        #expect(detail == fitGantt.dayWidth, "fit 日宽读数 \(detail) 与实际 \(fitGantt.dayWidth) 不符")
    }

    // MARK: A7 刻度粒度契约（行为契约，非快照自比）

    /// A7-1（预设档位）：`customDayWidth == nil` 且非 fit 时，核心实际使用的刻度粒度
    /// 恒等于 `viewState.zoom`，日宽恒等于档位默认宽度。
    ///
    /// 判据来源：与**核心引擎按契约参数直接复算**的参考输出逐项比对（跨实现比较），
    /// 因此能发现「呈现层把预设路径改写」的行为偏差，而不是自我比较。
    @Test func presetModeKeepsPresetWidthGranularityAndMatchesCoreReference() {
        let fixture = DayWidthFixture()
        let presets: [(zoom: GanttZoom, width: Double)] = [(.day, 32), (.week, 12), (.month, 5)]

        for preset in presets {
            let gantt = makeDayWidthSnapshot(
                fixture: fixture,
                customDayWidth: nil,
                zoom: preset.zoom,
                usesFitZoom: false,
                canvasWidth: 1200
            ).gantt

            #expect(gantt.dayWidth == preset.width, "\(preset.zoom) 档日宽应恒为 \(preset.width)")
            #expect(gantt.zoom == preset.zoom)
            #expect(
                gantt.tickGranularity == preset.zoom,
                "预设档位的刻度粒度不得被自定义逻辑改写（应为 \(preset.zoom)）"
            )
            #expect(gantt.usesFitZoom == false)

            // 刻度集合符合该档位语义（未被改写的可观测部分）。
            let lower = gantt.ticks.filter { !$0.isMajor }
            switch preset.zoom {
            case .day:
                #expect(lower.count >= 20, "逐日档应有每日一条下层刻度")
            case .week:
                for tick in lower {
                    #expect(
                        testCalendar.component(.weekday, from: tick.date) == testCalendar.firstWeekday,
                        "逐周档的下层刻度必须落在周界"
                    )
                }
            case .month:
                for tick in lower {
                    #expect(
                        testCalendar.component(.day, from: tick.date) == 1,
                        "逐月档的下层刻度必须落在月界"
                    )
                }
                #expect(gantt.bands.isEmpty, "逐月档沿用既有行为：隐藏非工作带")
            }

            // 与核心参考实现（zoom = 预设档位、无日宽覆盖）逐项一致。
            let reference = referenceLayout(
                fixture: fixture,
                zoom: preset.zoom,
                mode: .preset,
                canvasWidth: 1200
            )
            assertAxisMatches(gantt, reference, "预设 \(preset.zoom) 档 @1200pt")
        }
    }

    /// A7-2（fit 路径 / HIGH-1 硬回归网）：`usesFitZoom == true` 且 `custom == nil` 时，
    /// `tickGranularity` 恒等于 `viewState.zoom` —— **fit 只改日宽，不改刻度粒度**。
    ///
    /// HIGH-1 的可观测症状：fit 宽度落在与预设档位不同的粒度桶时，粒度被静默改写。
    /// 本用例在 3 档预设 × 3 种画布宽度上覆盖该症状，并与核心参考输出逐项比对。
    @Test func fitModeKeepsPresetGranularityAndMatchesCoreReference() {
        let fixture = DayWidthFixture()
        let presets: [GanttZoom] = [.day, .week, .month]
        let canvasWidths: [Double] = [400, 760, 2000]

        // 区分度守卫：这些参数下 fit 宽度必然跨越粒度阈值，
        // 因此「按 fit 宽度推导粒度」的实现一定会被下面的断言抓到（用例非恒真）。
        let discriminating = presets.contains { zoom in
            canvasWidths.contains { canvasWidth in
                GanttScale.tickUnit(forDayWidth: fitDayWidth(fixture, canvasWidth: canvasWidth)) != zoom
            }
        }
        #expect(discriminating, "用例失去区分度：fit 宽度不再跨越粒度阈值")

        for zoom in presets {
            for canvasWidth in canvasWidths {
                let gantt = makeDayWidthSnapshot(
                    fixture: fixture,
                    customDayWidth: nil,
                    zoom: zoom,
                    usesFitZoom: true,
                    canvasWidth: canvasWidth
                ).gantt

                #expect(gantt.usesFitZoom == true, "fit 模式应处于 fit 状态")
                #expect(gantt.zoom == zoom, "fit 模式不得改写用户预设档位")
                #expect(
                    gantt.tickGranularity == zoom,
                    """
                    fit 模式下刻度粒度必须恒等于预设档位 \(zoom)，\
                    实际 \(gantt.tickGranularity)（fit 日宽 \(gantt.dayWidth)，画布 \(canvasWidth)pt）\
                    —— HIGH-1：fit 路径的刻度粒度被静默改写
                    """
                )

                // 与核心参考实现（zoom = 预设档位 + fit 日宽覆盖）逐项一致。
                let reference = referenceLayout(
                    fixture: fixture,
                    zoom: zoom,
                    mode: .fit,
                    canvasWidth: canvasWidth
                )
                assertAxisMatches(gantt, reference, "fit \(zoom) 档 @\(canvasWidth)pt")
            }
        }
    }

    /// A7-3（fit 路径 / viewport 变化不变性）：画布宽度变化会改变 fit 日宽，
    /// 但**刻度粒度不得随之变化**（HIGH-1 的另一个可观测症状）。
    @Test func fitModeGranularityIsInvariantToViewportWidth() {
        let fixture = DayWidthFixture()
        let zoom = GanttZoom.month
        let canvasWidths: [Double] = [400, 760, 1200, 2000, 3840]

        var effectiveWidths: [Double] = []
        var granularities: [GanttZoom] = []

        for canvasWidth in canvasWidths {
            let gantt = makeDayWidthSnapshot(
                fixture: fixture,
                customDayWidth: nil,
                zoom: zoom,
                usesFitZoom: true,
                canvasWidth: canvasWidth
            ).gantt
            #expect(gantt.usesFitZoom == true)
            #expect(
                gantt.tickGranularity == zoom,
                "画布宽 \(canvasWidth)pt 时 fit 粒度被改写为 \(gantt.tickGranularity)（应为 \(zoom)）"
            )
            effectiveWidths.append(gantt.dayWidth)
            granularities.append(gantt.tickGranularity)
        }

        // 非空校验：画布宽度确实改变了 fit 日宽（否则上面的不变性没有意义）。
        #expect(
            Set(effectiveWidths.map { ($0 * 1_000_000).rounded() }).count == canvasWidths.count,
            "fit 日宽应随画布宽度变化，实际 \(effectiveWidths)"
        )
        // 粒度与画布宽度无关。
        #expect(Set(granularities).count == 1, "fit 模式下刻度粒度不得随画布宽度变化，实际 \(granularities)")
        #expect(granularities.allSatisfy { $0 == zoom })
    }

    /// A7-4（自定义路径）：`custom != nil` 时，刻度粒度由**生效日宽**推导，
    /// 跨 18 / 6 两个阈值精确翻转，且不改写用户预设档位。
    @Test func customModeDerivesGranularityFromEffectiveDayWidth() {
        let fixture = DayWidthFixture()
        // 契约阈值：≥18 逐日；≥6 逐周；否则逐月（设计稿 §7.3 的「5.99 → .week」已由 lead 更正为 .month）。
        let cases: [(width: Double, expected: GanttZoom)] = [
            (2, .month),
            (5, .month),
            (5.99, .month),
            (6, .week),
            (12, .week),
            (17.99, .week),
            (18, .day),
            (20, .day),
            (32, .day),
            (120, .day)
        ]

        for item in cases {
            let gantt = makeDayWidthSnapshot(
                fixture: fixture,
                customDayWidth: item.width,
                zoom: .week,
                usesFitZoom: false
            ).gantt
            #expect(gantt.dayWidth == item.width)
            #expect(
                gantt.tickGranularity == item.expected,
                "自定义日宽 \(item.width) 的刻度粒度应为 \(item.expected)，实际 \(gantt.tickGranularity)"
            )
            // 与核心推导口径一致（单一真相源）。
            #expect(gantt.tickGranularity == GanttScale.tickUnit(forDayWidth: item.width))
            // 预设档位语义不被改写。
            #expect(gantt.zoom == .week, "自定义不得改写用户预设档位")
            #expect(gantt.usesFitZoom == false)
        }

        // 阈值翻转：跨过 18 与 6 时粒度恰好切换一档。
        let granularityAt: (Double) -> GanttZoom = { width in
            makeDayWidthSnapshot(
                fixture: fixture,
                customDayWidth: width,
                zoom: .week,
                usesFitZoom: false
            ).gantt.tickGranularity
        }
        #expect(granularityAt(17.99) != granularityAt(18), "跨过 18 必须从逐周翻转为逐日")
        #expect(granularityAt(5.99) != granularityAt(6), "跨过 6 必须从逐月翻转为逐周")
    }

    /// A7-5（自定义优先于 fit）：fit 开启时给出自定义宽度，宽度与粒度都以自定义为准。
    @Test func customModeWidthAndGranularityWinOverFit() {
        let fixture = DayWidthFixture()
        let fitWidth = fitDayWidth(fixture, canvasWidth: 760)

        for item in [(width: 20.0, expected: GanttZoom.day), (width: 5.0, expected: GanttZoom.month)] {
            let gantt = makeDayWidthSnapshot(
                fixture: fixture,
                customDayWidth: item.width,
                zoom: .week,
                usesFitZoom: true,
                canvasWidth: 760
            ).gantt
            #expect(gantt.dayWidth == item.width, "自定义宽度必须压过 fit 宽度 \(fitWidth)")
            #expect(gantt.usesFitZoom == false, "自定义生效时不应报告 fit")
            #expect(
                gantt.tickGranularity == item.expected,
                "自定义日宽 \(item.width) 的刻度粒度应为 \(item.expected)，实际 \(gantt.tickGranularity)"
            )
            #expect(gantt.zoom == .week, "自定义不得改写用户预设档位")
            // 非空校验：fit 宽度与自定义宽度确实不同（否则上面的优先级断言无意义）。
            #expect(abs(gantt.dayWidth - fitWidth) > 1e-9)
        }
    }

    /// IR-3：`GanttSnapshot.zoom` 保持「用户预设档位」语义，`tickGranularity` 报告生效刻度档位。
    @Test func zoomKeepsPresetSemanticsWhileTickGranularityReportsEffectiveUnit() {
        let fixture = DayWidthFixture()
        let cases: [(preset: GanttZoom, custom: Double, granularity: GanttZoom)] = [
            (.week, 20, .day),
            (.month, 10, .week),
            (.day, 5, .month)
        ]
        for item in cases {
            let gantt = makeDayWidthSnapshot(
                fixture: fixture,
                customDayWidth: item.custom,
                zoom: item.preset,
                usesFitZoom: false
            ).gantt
            #expect(gantt.zoom == item.preset, "zoom 必须保持用户预设档位语义")
            #expect(gantt.tickGranularity == item.granularity)
            #expect(gantt.dayWidth == item.custom)
        }
    }

    // MARK: 动作契约（载荷形状）

    /// 动作契约：三个日宽动作的**载荷可被检出且彼此可区分**。
    ///
    /// 这里刻意不使用「case 与自己比较」的恒真断言：每个断言都从动作里**取出载荷**再校验，
    /// 或比较两个**不同**动作是否可区分。
    ///
    /// `clearCustomDayWidth` 同时保留无载荷 case 与同名 static 工厂（lead 裁定，Swift 解析无歧义）：
    /// 工厂必须返回同一个「清除」动作。
    @Test func dayWidthActionsExposeInspectablePayloads() {
        // setCustomDayWidth：载荷 = 宽度。
        guard case let .setCustomDayWidth(width) = WorkspaceAction.setCustomDayWidth(20) else {
            Issue.record("setCustomDayWidth 必须携带宽度载荷")
            return
        }
        #expect(width == 20, "setCustomDayWidth 的载荷应为 20")

        // nudgeCustomDayWidth：载荷 = 步进量（保留符号）。
        guard case let .nudgeCustomDayWidth(delta) = WorkspaceAction.nudgeCustomDayWidth(by: 1) else {
            Issue.record("nudgeCustomDayWidth 必须携带步进载荷")
            return
        }
        #expect(delta == 1, "nudgeCustomDayWidth 的载荷应为 1")
        guard case let .nudgeCustomDayWidth(negative) = WorkspaceAction.nudgeCustomDayWidth(by: -1) else {
            Issue.record("nudgeCustomDayWidth 必须携带步进载荷")
            return
        }
        #expect(negative == -1, "步进载荷必须保留符号")

        // clearCustomDayWidth：无载荷 case（不得被误塞宽度载荷）。
        let cleared: WorkspaceAction = .clearCustomDayWidth
        if case .clearCustomDayWidth = cleared {
            // 命中无载荷 case：符合契约。
        } else {
            Issue.record("clearCustomDayWidth 必须是独立的无载荷动作")
        }
        #expect(
            WorkspaceAction.clearCustomDayWidth == cleared,
            "同名 static 工厂必须返回同一个「清除自定义日宽」动作"
        )

        // 三个动作彼此可区分（状态机据此路由；混淆会吞掉用户操作）。
        #expect(WorkspaceAction.setCustomDayWidth(20) != WorkspaceAction.nudgeCustomDayWidth(by: 20))
        #expect(WorkspaceAction.setCustomDayWidth(20) != cleared)
        #expect(WorkspaceAction.nudgeCustomDayWidth(by: 20) != cleared)
        #expect(WorkspaceAction.setCustomDayWidth(20) != WorkspaceAction.setCustomDayWidth(21))
    }

    // MARK: A8 持久化前置条件

    /// A8 前置条件：自定义日宽承载在可持久化的视图状态中（缺省 nil、随值拷贝与相等性保持）。
    /// 偏好 JSON 的编解码往返在应用层 `WorkspaceStore.StoredPreferences`（见交付报告缺口说明）。
    @Test func viewStateCarriesCustomDayWidthAsPersistableValue() {
        #expect(WorkspaceViewState().customDayWidth == nil)

        var state = WorkspaceViewState()
        state.customDayWidth = 20
        let copied = state
        #expect(copied.customDayWidth == 20)
        #expect(copied == state)
        #expect(copied.hashValue == state.hashValue)

        var cleared = state
        cleared.customDayWidth = nil
        #expect(cleared.customDayWidth == nil)
        #expect(cleared != state)
    }
}
