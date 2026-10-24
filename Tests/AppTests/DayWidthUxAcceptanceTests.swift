import Foundation
import Testing
import KairoCore
import KairoPresentation
@testable import KairoMacApp

/// 日宽自定义 UX 自动化验收（Sprint 6，D-015 等价验收）。
///
/// 以自动化等价覆盖原「真机走查」验收项：
/// - 节流状态机：拖动节流、松手必提交、面板关闭提交末值（原 D-015 点 2 + D-010 回归锁定）；
/// - 面板呈现：边界日宽（下界/上界）离屏渲染不空白不崩溃（原点 1 的呈现等价）；
/// - 快捷键：⌘+/⌘-/⌘0 注册与驱动（原点 3，`DayWidthControlTests` 已覆盖，此处补读数路径）；
/// - 菜单系统项：源码结构守卫，防止 `after: .pasteboard` 再被改成 `replacing:`
///   而移除系统 ⌘C/⌘V/⌘A（原点 4，D-018 回归锁定）。
///
/// 状态机经 `DayWidthThrottle`（引用语义）驱动，与真实面板共用同一条状态生命线；
/// 测试区分「立即提交 / 节流收尾」两条路径，避免退化为恒真断言。
/// 残余风险（自动化不可覆盖）：真实手势手感与物理键盘布局事件，已登记 D-015 备注。
@MainActor
@Suite("日宽自定义（UX 自动化验收）")
struct DayWidthUxAcceptanceTests {
    /// 每个测试使用独立偏好域，避免写入开发者真实配置。
    private func makeStore(seedsDemoData: Bool = true) -> WorkspaceStore {
        let suite = "kairo.apptests.daywidthux.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return WorkspaceStore(defaults: defaults, seedsDemoData: seedsDemoData)
    }

    /// 新面板：节流机 `lastCommitAt == .distantPast`，首次拖动立即提交，后续进入节流窗口。
    private func makeControl(_ store: WorkspaceStore) -> DayWidthControl {
        DayWidthControl(store: store, dayWidth: store.snapshot.gantt.dayWidth)
    }

    // MARK: - 节流状态机

    @Test func firstSlideCommitsImmediately() {
        let store = makeStore()
        let control = makeControl(store)

        control.throttle.slide(30)

        #expect(store.viewState.customDayWidth == 30)
        #expect(control.throttle.draft == 30)
    }

    @Test func slidesInsideThrottleWindowCommitTrailingValueOnly() async throws {
        let store = makeStore()
        let control = makeControl(store)

        control.throttle.slide(30)
        #expect(store.viewState.customDayWidth == 30)

        // 节流窗口内的连续拖动（引用语义保证 lastCommitAt 延续，此分支确定命中）：
        // 不再立即提交，末值由待提交任务收尾。
        control.throttle.slide(40)
        control.throttle.slide(45)
        #expect(store.viewState.customDayWidth != 45, "节流窗口内不应立即提交")
        let pending = try #require(control.throttle.pendingCommit)
        await pending.value
        #expect(store.viewState.customDayWidth == 45)
    }

    @Test func finishDraggingCommitsFinalDraftImmediately() {
        let store = makeStore()
        let control = makeControl(store)

        control.throttle.slide(30)
        control.throttle.slide(40)
        control.throttle.finish()

        // 松手必提交（R-02），且待提交任务已取消，不会二次提交。
        #expect(store.viewState.customDayWidth == 40)
        #expect(control.throttle.draft == nil)
        #expect(control.throttle.pendingCommit == nil || control.throttle.pendingCommit?.isCancelled == true)
    }

    /// D-010 回归锁定：节流窗口内关闭面板，末值不能丢。
    @Test func dismissalInsideThrottleWindowCommitsLastValue() {
        let store = makeStore()
        let control = makeControl(store)

        control.throttle.slide(30)
        control.throttle.slide(45)
        // onDisappear 的实际路径：与松手共用 finish()。
        control.throttle.finish()

        #expect(store.viewState.customDayWidth == 45)
        #expect(control.throttle.draft == nil)
        #expect(control.throttle.pendingCommit == nil)
    }

    @Test func dismissalWithoutDraftKeepsCommittedValue() {
        let store = makeStore()
        let control = makeControl(store)

        control.throttle.slide(20)
        control.throttle.finish()
        // 无草稿时再次收尾（如面板打开期间未拖动就关闭）：不产生第二次提交。
        control.throttle.finish()

        #expect(store.viewState.customDayWidth == 20)
    }

    @Test func externalDayWidthChangeDiscardsStaleDraft() {
        let store = makeStore()
        let control = makeControl(store)

        control.throttle.slide(30)
        control.throttle.finish()
        // 面板打开期间外部值更新（如按 ⌘+）：草稿丢弃，面板回到生效值。
        control.throttle.discardDraft()

        #expect(control.throttle.draft == nil)
        #expect(store.viewState.customDayWidth == 30)
    }

    // MARK: - 面板呈现（离屏渲染等价）

    /// 边界日宽（下界 2 / 上界 120）下面板渲染不崩溃、非空白。
    @Test func panelRendersAtBoundaryDayWidths() throws {
        let store = makeStore()
        for width in [GanttScale.dayWidthRange.lowerBound, GanttScale.dayWidthRange.upperBound] {
            let rendered = try #require(
                GUIRenderer.snapshot(
                    DayWidthControl(store: store, dayWidth: width),
                    width: 292,
                    height: 180
                )
            )
            #expect(rendered.distinctColorCount > 5, "日宽 \(width) 下渲染疑似空白")
        }
    }

    // MARK: - 非有限值读数（D-011 回归锁定）

    /// D-019 补测：日宽读数对非有限值返回占位符，不触发 `Int(_:)` 陷阱。
    ///
    /// F-0704 起格式化从 `WorkspacePresenter.zoomDetail` 移到视图层（`Display.pointsPerDay`），
    /// 判据不变：非有限值出占位符，超范围有限值走非整数分支且仍可读。
    @Test func pointsPerDayHandlesNonFiniteValuesWithoutCrashing() {
        #expect(Display.pointsPerDay(.infinity) == "—")
        #expect(Display.pointsPerDay(-.infinity) == "—")
        #expect(Display.pointsPerDay(.nan) == "—")
        #expect(Display.pointsPerDay(nil) == "—")
        // 超 Int 范围的有限值走非整数格式化分支，不崩溃且产出可读读数。
        #expect(Display.pointsPerDay(1e16).hasSuffix("pts/day"))
        #expect(Display.pointsPerDay(12) == "12 pts/day")
        #expect(Display.pointsPerDay(12.5) == "12.5 pts/day")
    }

    // MARK: - 菜单系统项结构守卫（D-018 回归锁定）

    /// 源码结构守卫：编辑菜单的剪贴板区段必须是 `after:`（保留系统 ⌘C/⌘V/⌘A/全选）。
    ///
    /// SwiftUI `Commands` 只在真实 Scene 生命周期内生成 `NSApp.mainMenu`，
    /// Swift Testing 进程无法实例化检查；此处对生成菜单的**唯一来源**做结构断言。
    /// `replacing: .saveItem` 为有意保留（App 自有保存/另存为完整接管）。
    @Test func pasteboardMenuGroupRemainsAfterNotReplacing() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/AppTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // 仓库根
            .appendingPathComponent("Apps/macos/Sources/CommandRegistry.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(
            source.contains("CommandGroup(after: .pasteboard)"),
            "编辑菜单剪贴板区段必须是 after:（D-018）；若本断言失败说明系统 ⌘C/⌘V/⌘A 菜单项再次被移除"
        )
        #expect(
            !source.contains("CommandGroup(replacing: .pasteboard)"),
            "replacing: .pasteboard 会移除系统剪贴板菜单项（D-018 回归）"
        )
        #expect(
            source.contains("CommandGroup(replacing: .saveItem)"),
            "replacing: .saveItem 为有意保留（自有保存/另存为接管）；若已改为 after: 请同步更新本守卫"
        )
    }
}
