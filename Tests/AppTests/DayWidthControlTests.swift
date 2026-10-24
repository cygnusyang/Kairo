import Foundation
import Testing
import KairoCommands
import KairoCore
import KairoPresentation
@testable import KairoMacApp

/// 应用适配层日宽交互测试（Sprint 6 / T3）：动作路由、互斥、持久化与命令注册表。
///
/// 画面差异由 `GUIRenderTests` 离屏渲染覆盖；本文件只锁定状态与动作契约。
@MainActor
@Suite("日宽自定义（应用层）")
struct DayWidthControlTests {
    /// 每个测试使用独立偏好域，避免写入开发者真实配置。
    private func makeStore(
        seedsDemoData: Bool = true,
        defaults: UserDefaults? = nil
    ) -> WorkspaceStore {
        let suite = "kairo.apptests.daywidth.\(UUID().uuidString)"
        let store = defaults ?? (UserDefaults(suiteName: suite) ?? .standard)
        store.removePersistentDomain(forName: suite)
        return WorkspaceStore(defaults: store, seedsDemoData: seedsDemoData)
    }

    private func makeCatalog(_ store: WorkspaceStore) -> [KairoCommand] {
        KairoCommandCatalog.make(
            store: store, requestOpen: {}, requestSave: {}, requestSaveAs: {}
        )
    }

    private func command(_ commands: [KairoCommand], _ id: String) throws -> KairoCommand {
        try #require(commands.first { $0.id == id })
    }

    // MARK: - 动作路由

    @Test func setCustomDayWidthStoresClampedValueAndLeavesFitMode() {
        let store = makeStore()
        store.dispatch(.setCustomDayWidth(20))

        #expect(store.viewState.customDayWidth == 20)
        #expect(!store.viewState.usesFitZoom)
        #expect(store.snapshot.gantt.dayWidth == 20)
        #expect(store.snapshot.statusBar.zoom.preset == .custom)
        #expect(store.snapshot.statusBar.zoom.pointsPerDay == 20)
    }

    @Test func setCustomDayWidthClampsOutOfRangeValues() {
        let store = makeStore()
        for (input, expected) in [(-5.0, 2.0), (0.0, 2.0), (1000.0, 120.0)] {
            store.dispatch(.setCustomDayWidth(input))
            #expect(store.viewState.customDayWidth == expected)
            #expect(store.snapshot.gantt.dayWidth == expected)
        }
        store.dispatch(.setCustomDayWidth(.nan))
        #expect(store.viewState.customDayWidth == 2)
        store.dispatch(.setCustomDayWidth(.infinity))
        #expect(store.viewState.customDayWidth == 120)
    }

    @Test func nudgeUsesEffectiveDayWidthAsBase() {
        let store = makeStore()
        store.dispatch(.setCustomDayWidth(20))
        store.dispatch(.nudgeCustomDayWidth(by: 2))
        #expect(store.viewState.customDayWidth == 22)
        #expect(!store.viewState.usesFitZoom)

        store.dispatch(.nudgeCustomDayWidth(by: -5))
        #expect(store.viewState.customDayWidth == 17)
    }

    @Test func nudgeInFitModeUsesFitWidthAsBase() {
        let store = makeStore()
        // fit 模式下基准是 fit 宽度（画布宽 / 内容天数），不是档位默认宽度。
        let fitWidth = store.snapshot.gantt.dayWidth
        let presetWidth = store.viewState.zoom.dayWidth
        #expect(store.viewState.usesFitZoom)
        // 区分度守卫：fit 宽度必须明显异于档位默认宽度，否则「基准取 fit 宽度」与
        // 「基准取档位默认」不可区分，用例会退化为恒真。
        #expect(
            abs(fitWidth - presetWidth) > 0.5,
            "用例失去区分度：fit 宽度 \(fitWidth) 与档位默认宽度 \(presetWidth) 相同"
        )

        store.dispatch(.nudgeCustomDayWidth(by: 1))

        #expect(!store.viewState.usesFitZoom)
        // fit 宽度 + 1 落在合法区间内，动作层的夹取为恒等，
        // 因此期望值即「fit 基准 + 步进」按 0.1 取整后的提交值（M-4：
        // 动作层提交时取整到 0.1，保证落盘偏好与状态栏读数一致）。
        #expect(GanttScale.dayWidthRange.contains(fitWidth + 1))
        #expect(store.viewState.customDayWidth == ((fitWidth + 1) * 10).rounded() / 10)
        // 基准来源是 fit 宽度而非档位默认：若基准取档位默认，结果应为档位默认 + 1。
        #expect(store.viewState.customDayWidth != ((presetWidth + 1) * 10).rounded() / 10)
    }

    @Test func clearCustomDayWidthFallsBackToPresetWidth() {
        let store = makeStore()
        store.dispatch(.setCustomDayWidth(20))
        store.dispatch(.clearCustomDayWidth)

        #expect(store.viewState.customDayWidth == nil)
        #expect(store.snapshot.gantt.dayWidth == GanttZoom.week.dayWidth)
    }

    // MARK: - 互斥规则

    @Test func presetZoomClearsCustomDayWidth() {
        let store = makeStore()
        store.dispatch(.setCustomDayWidth(20))
        store.dispatch(.setZoom(.day))

        #expect(store.viewState.customDayWidth == nil)
        #expect(!store.viewState.usesFitZoom)
        #expect(store.snapshot.gantt.dayWidth == GanttZoom.day.dayWidth)
    }

    @Test func fitZoomClearsCustomDayWidth() {
        let store = makeStore()
        store.dispatch(.setCustomDayWidth(20))
        store.dispatch(.setFitZoom(true))

        #expect(store.viewState.customDayWidth == nil)
        #expect(store.viewState.usesFitZoom)
    }

    @Test func panningKeepsCustomDayWidth() {
        let store = makeStore()
        store.dispatch(.setCustomDayWidth(20))

        store.dispatch(.panWindow(to: Date()))
        #expect(store.viewState.customDayWidth == 20)

        store.dispatch(.goToToday)
        #expect(store.viewState.customDayWidth == 20)
    }

    // MARK: - 持久化

    @Test func customDayWidthPersistsAcrossStores() {
        let suite = "kairo.apptests.daywidth.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = WorkspaceStore(defaults: defaults)
        first.dispatch(.setCustomDayWidth(20))

        let second = WorkspaceStore(defaults: defaults)
        #expect(second.viewState.customDayWidth == 20)
        #expect(second.snapshot.gantt.dayWidth == 20)
    }

    @Test func legacyPreferencesWithoutCustomDayWidthStillLoad() throws {
        let suite = "kairo.apptests.daywidth.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        // 旧偏好 JSON：不含 customDayWidth 键。
        let legacy = """
        {
          "outlineWidth": 480,
          "outlineVisible": true,
          "expandedTaskIDs": [],
          "zoom": "day",
          "usesFitZoom": false,
          "windowStart": null,
          "inspectorWidth": 360,
          "inspectorTab": "violations"
        }
        """
        defaults.set(Data(legacy.utf8), forKey: WorkspaceStore.preferencesKey)

        let store = WorkspaceStore(defaults: defaults)
        #expect(store.viewState.customDayWidth == nil)
        // 其余偏好完整保留。
        #expect(store.viewState.outlineWidth == 480)
        #expect(store.viewState.zoom == .day)
        #expect(store.viewState.inspectorWidth == 360)
        #expect(store.viewState.inspectorTab == .violations)
    }

    @Test func persistedOutOfRangeCustomDayWidthIsClampedOnLoad() {
        let suite = "kairo.apptests.daywidth.range.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let stored = """
        {
          "outlineWidth": 600,
          "outlineVisible": true,
          "expandedTaskIDs": [],
          "zoom": "week",
          "usesFitZoom": true,
          "customDayWidth": 999,
          "windowStart": null,
          "inspectorWidth": 320,
          "inspectorTab": "inspector"
        }
        """
        defaults.set(Data(stored.utf8), forKey: WorkspaceStore.preferencesKey)

        let store = WorkspaceStore(defaults: defaults)
        #expect(store.viewState.customDayWidth == 120)
        // 自定义与 fit 互斥：载入时以自定义为准。
        #expect(!store.viewState.usesFitZoom)
    }

    // MARK: - 命令注册表

    @Test func catalogExposesDayWidthCommandsWithShortcuts() throws {
        let store = makeStore()
        let commands = makeCatalog(store)

        #expect(try command(commands, "view.dayWidthWider").shortcut?.label == "⌘+")
        #expect(try command(commands, "view.dayWidthNarrower").shortcut?.label == "⌘-")
        #expect(try command(commands, "view.dayWidthReset").shortcut?.label == "⌘0")
    }

    @Test func dayWidthCommandsDriveTheStore() throws {
        let store = makeStore()
        let commands = makeCatalog(store)
        store.dispatch(.setCustomDayWidth(20))

        try command(commands, "view.dayWidthWider").action()
        #expect(store.viewState.customDayWidth == 21)

        try command(commands, "view.dayWidthNarrower").action()
        #expect(store.viewState.customDayWidth == 20)

        try command(commands, "view.dayWidthReset").action()
        #expect(store.viewState.customDayWidth == nil)
    }

    // MARK: - 滑杆映射

    @Test func sliderPositionMapsDayWidthBothWays() {
        // 对数映射：位置 0 ↔ 下界 2，位置 1 ↔ 上界 120。
        #expect(abs(DayWidthControl.position(forDayWidth: 2) - 0) < 1e-9)
        #expect(abs(DayWidthControl.position(forDayWidth: 120) - 1) < 1e-9)
        // 常用区（5–32 点/天）占据的滑杆比例必须大于线性映射，
        // 否则常用宽度仍挤在左端，拖动手感不均。
        let lower = DayWidthControl.position(forDayWidth: 5)
        let upper = DayWidthControl.position(forDayWidth: 32)
        let linearBand = (32.0 - 5.0) / (120.0 - 2.0)
        #expect(upper - lower > linearBand)
        #expect(lower > 0 && lower < 0.3)
        #expect(upper > 0.6 && upper < 0.75)

        // 往返一致。
        for width in [2.0, 5.0, 12.0, 32.0, 90.0, 120.0] {
            let position = DayWidthControl.position(forDayWidth: width)
            #expect(abs(DayWidthControl.dayWidth(forPosition: position) - width) < 1e-6)
        }
    }

    @Test func sliderDayWidthStaysInsideLegalRange() {
        #expect(DayWidthControl.dayWidth(forPosition: -1) == 2)
        #expect(DayWidthControl.dayWidth(forPosition: 2) == 120)
        for step in 0...20 {
            let position = Double(step) / 20
            let width = DayWidthControl.dayWidth(forPosition: position)
            #expect(width >= GanttScale.dayWidthRange.lowerBound)
            #expect(width <= GanttScale.dayWidthRange.upperBound)
        }
    }

    // MARK: - 面板渲染

    /// 面板可渲染（滑杆 / 步进 / 芯片 / 重置均落在面板内）。
    @Test func dayWidthControlRenders() throws {
        let store = makeStore()
        let rendered = try #require(
            GUIRenderer.snapshot(
                DayWidthControl(store: store, dayWidth: store.snapshot.gantt.dayWidth),
                width: 292,
                height: 180
            )
        )
        #expect(rendered.width == 292)
        #expect(rendered.height == 180)
        #expect(rendered.distinctColorCount > 5)
    }
}
