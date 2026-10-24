import Foundation
import Testing
import KairoCore
import KairoPresentation

// Sprint 6 / T3 呈现层单测：自定义日宽的解析、互斥与文案。
//
// 覆盖点：生效日宽解析（自定义 / fit / 预设三态）、等比性不变式、
// 刻度粒度推导、状态栏文案，以及「未启用自定义 ⇒ 与现状逐位一致」。

// MARK: - 夹具

/// 日宽夹具：跨月跨年的 4 个任务，起点用约束固定以保证排期确定。
private struct DayWidthFixture {
    let projectStart: Date
    let tasks: [TaskItem]
    let state: ProjectState
    let schedule: ScheduleResult
    let now: Date

    init() {
        let projectStart = makeDate(2025, 3, 10)
        let design = TaskItem(
            title: "设计",
            durationDays: 8,
            constraint: .startNoEarlierThan(makeDate(2025, 3, 10))
        )
        let build = TaskItem(
            title: "实现",
            durationDays: 15,
            constraint: .startNoEarlierThan(makeDate(2025, 4, 1))
        )
        let release = TaskItem(
            title: "发布",
            kind: .milestone,
            constraint: .startNoEarlierThan(makeDate(2025, 5, 6))
        )
        let tasks = [design, build, release]
        let now = makeDate(2025, 4, 15)
        self.projectStart = projectStart
        self.tasks = tasks
        self.state = makeState(tasks, projectStart: projectStart)
        self.schedule = makeSchedule(tasks, projectStart: projectStart, now: now)
        self.now = now
    }
}

private func makeDayWidthSnapshot(
    _ fixture: DayWidthFixture,
    customDayWidth: Double? = nil,
    zoom: GanttZoom = .week,
    usesFitZoom: Bool = false,
    canvasWidth: Double = 1200
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

// MARK: - 改动前基线（黄金值）

/// 刻度签名：用于与「改动前基线」逐位比对。
private struct TickSignature: Equatable {
    let date: Date
    let x: Double
    let label: String
    let isMajor: Bool

    init(_ tick: GanttLayout.Tick) {
        date = tick.date
        x = tick.x
        label = tick.label
        isMajor = tick.tier == .upper
    }

    init(_ tick: GanttTick) {
        date = tick.date
        x = tick.x
        label = tick.label
        isMajor = tick.isMajor
    }
}

/// 非工作带签名：用于与「改动前基线」逐位比对。
private struct BandSignature: Equatable {
    let x: Double
    let width: Double

    init(_ band: GanttLayout.Band) {
        x = band.x
        width = band.width
    }

    init(_ band: GanttBand) {
        x = band.x
        width = band.width
    }
}

/// 刻度序列的首个差异描述（nil = 逐位一致）；失败时给出可读定位而非整段数组。
private func firstTickDifference(
    _ current: [TickSignature],
    _ baseline: [TickSignature]
) -> String? {
    if current.count != baseline.count {
        return "刻度数 \(current.count) != 基线 \(baseline.count)"
    }
    for (index, pair) in zip(current, baseline).enumerated() where pair.0 != pair.1 {
        return "第 \(index) 条刻度不同：\(pair.0) vs \(pair.1)"
    }
    return nil
}

/// 非工作带序列的首个差异描述（nil = 逐位一致）。
private func firstBandDifference(
    _ current: [BandSignature],
    _ baseline: [BandSignature]
) -> String? {
    if current.count != baseline.count {
        return "非工作带数 \(current.count) != 基线 \(baseline.count)"
    }
    for (index, pair) in zip(current, baseline).enumerated() where pair.0 != pair.1 {
        return "第 \(index) 条非工作带不同：\(pair.0) vs \(pair.1)"
    }
    return nil
}

/// 改动前（`git show ac8e360:Sources/KairoPresentation/Presenter.swift`）的核心调用参数。
///
/// 旧实现恒传 `zoom: viewState.zoom`；`dayWidthOverride` 仅在「适合项目」时为 fit 宽度。
/// 「未启用自定义 ⇒ 与改动前逐位一致」（A7）由本基线锁定，而不是同一份实现的两份快照自比。
private func legacyGanttLayout(
    _ fixture: DayWidthFixture,
    zoom: GanttZoom,
    usesFitZoom: Bool,
    canvasWidth: Double
) -> GanttLayout {
    let unscheduled = Set(fixture.schedule.unscheduledTaskIDs)
    let layoutSchedule = ScheduleResult(
        tasks: fixture.schedule.tasks.filter { !unscheduled.contains($0.taskID) },
        projectStart: fixture.schedule.projectStart,
        projectEnd: fixture.schedule.projectEnd,
        direction: fixture.schedule.direction,
        cycleTaskIDs: fixture.schedule.cycleTaskIDs,
        projectStartDerived: fixture.schedule.projectStartDerived,
        unscheduledTaskIDs: fixture.schedule.unscheduledTaskIDs
    )
    let content = GanttLayoutEngine.contentRange(
        tasks: fixture.tasks,
        schedule: layoutSchedule,
        calendar: testCalendar
    )
    // 适合项目时在末尾补一天（与改动前一致）。
    let fitRange = content.map {
        DateInterval(start: $0.start, end: $0.end.addingTimeInterval(86_400))
    }
    let canFit = usesFitZoom && fitRange != nil && canvasWidth > 0
    let dayWidthOverride = canFit
        ? GanttLayoutEngine.fitDayWidth(
            contentRange: fitRange!,
            viewWidth: canvasWidth,
            calendar: testCalendar
        )
        : nil
    return GanttLayoutEngine.make(
        tasks: fixture.tasks,
        schedule: layoutSchedule,
        calendar: testCalendar,
        zoom: zoom,
        viewWidth: max(canvasWidth, 1),
        windowStart: content?.start ?? fixture.now,
        dayWidthOverride: dayWidthOverride,
        rowIndexByTaskID: [:],
        rowHeight: 28,
        today: fixture.now
    )
}

// MARK: - 生效日宽解析

@Suite("日宽自定义（呈现层）")
struct DayWidthTests {
    @Test func customDayWidthBecomesTheSingleAuthoritativeWidth() {
        let fixture = DayWidthFixture()
        let gantt = makeDayWidthSnapshot(fixture, customDayWidth: 20).gantt

        #expect(gantt.dayWidth == 20)
        // 刻度粒度由实际日宽推导：20 ≥ 18 → 逐日。
        #expect(gantt.tickGranularity == .day)
        // 用户预设档位语义保持不变。
        #expect(gantt.zoom == .week)
        #expect(gantt.usesFitZoom == false)
    }

    @Test func presetZoomKeepsItsOwnDayWidth() {
        let fixture = DayWidthFixture()
        let presets: [(zoom: GanttZoom, width: Double)] = [(.day, 32), (.week, 12), (.month, 5)]
        for preset in presets {
            let gantt = makeDayWidthSnapshot(fixture, customDayWidth: nil, zoom: preset.zoom).gantt
            #expect(gantt.dayWidth == preset.width)
            #expect(gantt.zoom == preset.zoom)
            #expect(gantt.tickGranularity == preset.zoom, "预设档位与生效粒度必须自洽")
        }
    }

    @Test func customDayWidthWinsOverFitZoom() {
        let fixture = DayWidthFixture()
        // 矛盾状态：fit 与自定义同时为真 → 自定义为唯一真相源。
        let gantt = makeDayWidthSnapshot(
            fixture, customDayWidth: 20, usesFitZoom: true, canvasWidth: 760
        ).gantt
        #expect(gantt.dayWidth == 20)
        #expect(gantt.usesFitZoom == false)
        #expect(gantt.tickGranularity == .day)
    }

    @Test func fitZoomKeepsFitWidthWithoutClamping() throws {
        let fixture = DayWidthFixture()
        let gantt = makeDayWidthSnapshot(
            fixture, customDayWidth: nil, usesFitZoom: true, canvasWidth: 760
        ).gantt
        #expect(gantt.usesFitZoom == true)
        let contentStart = try #require(gantt.contentStart)
        let contentEnd = try #require(gantt.contentEnd)
        let contentDays = contentEnd.timeIntervalSince(contentStart) / 86_400 + 1
        // fit 宽度不夹取：与「画布宽 / 内容天数」逐位一致。
        #expect(abs(gantt.dayWidth - 760 / contentDays) < 1e-9)
    }

    @Test func outOfRangeCustomDayWidthIsClamped() {
        let fixture = DayWidthFixture()
        let cases: [(input: Double, expected: Double)] = [
            (-5, 2), (0, 2), (1.9, 2), (1000, 120), (120.1, 120),
            (Double.nan, 2), (Double.infinity, 120), (-Double.infinity, 2)
        ]
        for item in cases {
            let gantt = makeDayWidthSnapshot(fixture, customDayWidth: item.input).gantt
            #expect(
                gantt.dayWidth == item.expected,
                "自定义日宽 \(item.input) 未夹取到 \(item.expected)，实际 \(gantt.dayWidth)"
            )
            #expect(gantt.dayWidth.isFinite)
        }
    }

    // MARK: - 等比性不变式

    @Test func allCoordinatesAreMultiplesOfTheDayWidth() {
        let fixture = DayWidthFixture()
        for width in [2.0, 5.0, 12.0, 18.0, 33.5, 120.0] {
            let gantt = makeDayWidthSnapshot(fixture, customDayWidth: width).gantt
            #expect(gantt.dayWidth == width)
            for tick in gantt.ticks {
                #expect(
                    isMultiple(of: width, tick.x),
                    "刻度 \(tick.label) 的 x=\(tick.x) 不是日宽 \(width) 的整数倍"
                )
            }
            for band in gantt.bands {
                #expect(isMultiple(of: width, band.x))
                #expect(
                    abs(band.width - width) < 1e-6,
                    "非工作带宽度 \(band.width) != 日宽 \(width)"
                )
            }
            for bar in gantt.bars {
                #expect(isMultiple(of: width, bar.x))
                #expect(isMultiple(of: width, bar.width))
            }
        }
    }

    @Test func dayGranularityKeepsAdjacentTicksOneDayWidthApart() {
        let fixture = DayWidthFixture()
        let width = 18.0
        let gantt = makeDayWidthSnapshot(fixture, customDayWidth: width).gantt
        #expect(gantt.tickGranularity == .day)

        let xs = Array(Set(gantt.ticks.map(\.x))).sorted()
        #expect(xs.count > 10)
        for index in 1..<xs.count {
            #expect(
                abs((xs[index] - xs[index - 1]) - width) < 1e-6,
                "相邻刻度 x 差 \(xs[index] - xs[index - 1]) != 日宽 \(width)"
            )
        }
    }

    @Test func weekGranularityKeepsAdjacentTicksSevenDayWidthsApart() {
        let fixture = DayWidthFixture()
        let width = 12.0
        let gantt = makeDayWidthSnapshot(fixture, customDayWidth: width).gantt
        #expect(gantt.tickGranularity == .week)

        let weekly = gantt.ticks.filter {
            testCalendar.component(.weekday, from: $0.date) == testCalendar.firstWeekday
        }
        #expect(weekly.count > 5)
        var dateByX: [Double: Date] = [:]
        for tick in weekly { dateByX[tick.x] = tick.date }
        let xs = dateByX.keys.sorted()
        for index in 1..<xs.count {
            #expect(abs((xs[index] - xs[index - 1]) - 7 * width) < 1e-6)
        }
    }

    @Test func tinyDayWidthKeepsTickCountBounded() {
        let fixture = DayWidthFixture()
        // 2 点/天：降为逐月，刻度量远小于窗口天数，非工作带隐藏。
        let gantt = makeDayWidthSnapshot(fixture, customDayWidth: 2, canvasWidth: 1200).gantt
        #expect(gantt.tickGranularity == .month)
        #expect(gantt.bands.isEmpty)
        let windowDays: Double = gantt.windowEnd.timeIntervalSince(gantt.windowStart) / 86_400
        #expect(gantt.ticks.count <= 64)
        #expect(Double(gantt.ticks.count) < windowDays / 10)
    }

    // MARK: - 状态栏文案

    @Test func statusBarReportsZoomPresetAndDetail() {
        let fixture = DayWidthFixture()

        // F-0704：快照只带语义档位与数值日宽，文案（「自定义」「20 点/天」）留给视图。
        let custom = makeDayWidthSnapshot(fixture, customDayWidth: 20).statusBar
        #expect(custom.zoom.preset == .custom)
        #expect(custom.zoom.pointsPerDay == 20)

        let fractional = makeDayWidthSnapshot(fixture, customDayWidth: 12.5).statusBar
        #expect(fractional.zoom.preset == .custom)
        #expect(fractional.zoom.pointsPerDay == 12.5)

        let preset = makeDayWidthSnapshot(fixture, customDayWidth: nil, zoom: .day).statusBar
        #expect(preset.zoom.preset == .day)
        #expect(preset.zoom.pointsPerDay == GanttZoom.day.dayWidth)

        let fit = makeDayWidthSnapshot(
            fixture, customDayWidth: nil, usesFitZoom: true, canvasWidth: 760
        ).statusBar
        #expect(fit.zoom.preset == .fit)
        #expect(fit.zoom.pointsPerDay != nil)
    }

    @Test func customDayWidthTakesPriorityInZoomPreset() {
        let fixture = DayWidthFixture()
        // fit 与自定义同时为真时，档位报自定义。
        let statusBar = makeDayWidthSnapshot(
            fixture, customDayWidth: 20, usesFitZoom: true, canvasWidth: 760
        ).statusBar
        #expect(statusBar.zoom.preset == .custom)
    }

    // MARK: - 未启用自定义 ⇒ 与改动前一致（A7）

    @Test func presetModeKeepsTheUserZoomAsTickGranularity() {
        // 断言「核心实际收到的刻度粒度」：未启用自定义时恒为用户预设档位。
        let fixture = DayWidthFixture()
        for preset in [GanttZoom.day, .week, .month] {
            let gantt = makeDayWidthSnapshot(fixture, customDayWidth: nil, zoom: preset).gantt
            #expect(
                gantt.tickGranularity == preset,
                "预设档位 \(preset) 的刻度粒度必须等于用户档位"
            )
        }
    }

    @Test func fitModeKeepsTheUserZoomAsTickGranularity() {
        // 「适合项目」不改写刻度粒度：粒度仍是用户档位，不是由 fit 宽度推导。
        // 画布取窄宽度（fit 宽度 ≈ 5 点/天）：若按 fit 宽度推导会得到逐月，与档位 .day 相反。
        let fixture = DayWidthFixture()
        let gantt = makeDayWidthSnapshot(
            fixture, customDayWidth: nil, zoom: .day, usesFitZoom: true, canvasWidth: 300
        ).gantt
        #expect(gantt.usesFitZoom)
        #expect(
            gantt.tickGranularity == .day,
            "「适合项目」的刻度粒度不得由 fit 宽度推导"
        )
        #expect(gantt.dayWidth < 6, "本用例依赖 fit 宽度低于逐周阈值")
    }

    @Test func customModeDerivesTickGranularityFromTheEffectiveWidth() {
        // 启用自定义后：刻度粒度由实际生效日宽推导。
        let fixture = DayWidthFixture()
        let cases: [(width: Double, granularity: GanttZoom)] = [
            (40, .day), (18, .day), (17.9, .week), (12, .week), (6, .week), (5.9, .month), (2, .month)
        ]
        for item in cases {
            let gantt = makeDayWidthSnapshot(fixture, customDayWidth: item.width).gantt
            #expect(
                gantt.tickGranularity == GanttScale.tickUnit(forDayWidth: gantt.dayWidth),
                "自定义日宽 \(item.width) 的刻度粒度未按生效日宽推导"
            )
            #expect(
                gantt.tickGranularity == item.granularity,
                "日宽 \(item.width) 应推导为 \(item.granularity)"
            )
        }
        // 自定义路径才改写粒度：与用户档位不一致时必须改写（证明推导路径确实生效）。
        let overridden = makeDayWidthSnapshot(
            fixture, customDayWidth: 12, zoom: .day
        ).gantt
        #expect(overridden.zoom == .day)
        #expect(overridden.tickGranularity == .week)
    }

    @Test func presetAndFitOutputMatchThePreChangeBaseline() {
        // 黄金基线：与改动前（ac8e360）的核心调用逐位一致，而非同一份实现的两份快照自比。
        let fixture = DayWidthFixture()

        for preset in [GanttZoom.day, .week, .month] {
            let gantt = makeDayWidthSnapshot(fixture, customDayWidth: nil, zoom: preset).gantt
            let legacy = legacyGanttLayout(
                fixture, zoom: preset, usesFitZoom: false, canvasWidth: 1200
            )
            #expect(gantt.dayWidth == legacy.dayWidth, "预设 \(preset) 的日宽与改动前不一致")
            #expect(gantt.windowStart == legacy.windowStart)
            #expect(gantt.windowEnd == legacy.windowEnd)
            #expect(
                firstTickDifference(
                    gantt.ticks.map(TickSignature.init),
                    legacy.ticks.map(TickSignature.init)
                ) == nil,
                "预设 \(preset) 的刻度序列与改动前不一致"
            )
            #expect(
                firstBandDifference(
                    gantt.bands.map(BandSignature.init),
                    legacy.bands.map(BandSignature.init)
                ) == nil,
                "预设 \(preset) 的非工作带与改动前不一致"
            )
        }

        // 「适合项目」：核心入参同样与改动前一致（zoom = 用户档位，dayWidthOverride = fit 宽度）。
        let fit = makeDayWidthSnapshot(
            fixture, customDayWidth: nil, zoom: .day, usesFitZoom: true, canvasWidth: 300
        ).gantt
        let legacyFit = legacyGanttLayout(
            fixture, zoom: .day, usesFitZoom: true, canvasWidth: 300
        )
        #expect(fit.dayWidth == legacyFit.dayWidth, "fit 日宽与改动前不一致")
        #expect(
            firstTickDifference(
                fit.ticks.map(TickSignature.init),
                legacyFit.ticks.map(TickSignature.init)
            ) == nil,
            "fit 路径的刻度序列与改动前不一致"
        )
        #expect(
            firstBandDifference(
                fit.bands.map(BandSignature.init),
                legacyFit.bands.map(BandSignature.init)
            ) == nil,
            "fit 路径的非工作带与改动前不一致"
        )
    }

    @Test func enablingCustomDayWidthChangesTheOutput() {
        // 非空校验：启用自定义后输出必须不同，否则上面的基线比对是恒真的假断言。
        let fixture = DayWidthFixture()
        let baseline = makeDayWidthSnapshot(fixture, customDayWidth: nil, zoom: .day).gantt
        let custom = makeDayWidthSnapshot(fixture, customDayWidth: 20).gantt
        #expect(custom.dayWidth == 20)
        #expect(custom.tickGranularity == .day)
        #expect(custom != baseline)
    }

    // MARK: - 公开 API 源码兼容

    @Test func legacySnapshotInitDerivesTickGranularityFromZoom() {
        // 旧签名（不传 tickGranularity）必须仍能构造，且粒度由 zoom 派生。
        let snapshot = GanttSnapshot(
            windowStart: makeDate(2025, 3, 10),
            windowEnd: makeDate(2025, 4, 10),
            dayWidth: 12,
            zoom: .week,
            usesFitZoom: false,
            today: makeDate(2025, 4, 15),
            todayX: nil,
            todayOutOfRange: true
        )
        #expect(snapshot.tickGranularity == .week)
    }
}
