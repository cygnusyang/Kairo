import AppKit
import Foundation
import KairoPresentation
import os

/// 横向滚动捕获所需的「最新画布上下文」（F-14-18，引用语义 + 全进程单例）。
///
/// 滚动监听是长生命周期的 AppKit 回调，闭包不能直接捕获 `TimelineBody` 的值型
/// `gantt`（会锁住创建时刻的旧窗口起点），故把日宽 / 窗口起点 / 视口 / 所属窗口
/// 统一放进引用对象，由视图在快照变化时同步，监听侧只读最新值。
///
/// **为什么是单例**（D-027 二次排查）：SwiftUI 会因结构身份变化重建 `TimelineBody`
/// 并重复触发 `onAppear`，旧实例的 `onDisappear` 未必执行。若每个 `TimelineBody`
/// 各持一份上下文，监听可能绑在**已销毁**的那一份上（视口恒为 nil ⇒ 事件全被放行），
/// 表现为「双指横滑画布不动」。全进程一份上下文 + 一个监听，实例与数据不再错配。
@MainActor
final class HorizontalPanContext {
    static let shared = HorizontalPanContext()

    private static let logger = Logger(subsystem: "ai.kairo.app", category: "gantt-pan")

    /// 画布视口矩形（`CanvasViewportProbe` 上报的**窗口坐标**，左下原点）。
    private(set) var viewportInWindow: CGRect?
    /// 视口所属窗口（弱引用，窗口销毁即失效）。
    private(set) weak var window: NSWindow?
    /// 当前工作台各自持有的 store（弱引用，视图重建后由新实例接管）。
    private(set) weak var store: WorkspaceStore?
    private(set) var dayWidth: Double = 1
    private(set) var windowStart = Date()
    private var accumulator = HorizontalPanAccumulator()

    /// 快照变化时同步几何（视图在 `onAppear` / `onChange(of: gantt)` 调用）。
    func sync(dayWidth: Double, windowStart: Date) {
        self.dayWidth = max(dayWidth, 0.5)
        self.windowStart = windowStart
    }

    /// 视图挂载/重建时登记 store：监听常驻，但派发目标必须跟着当前工作台走。
    func attach(store: WorkspaceStore) {
        if self.store !== store { self.store = store }
    }

    /// 探针上报视口（窗口或几何变化时才写，避免逐帧赋值）。
    func attach(window: NSWindow, viewportInWindow: CGRect) {
        if self.window !== window { self.window = window }
        if self.viewportInWindow != viewportInWindow { self.viewportInWindow = viewportInWindow }
    }

    /// 消费一段横向像素位移，返回可提交的整天数（余量留存，跨整天才释放）。
    func consumeScroll(deltaX: Double) -> Int {
        accumulator.consume(deltaX: deltaX, dayWidth: dayWidth)
    }

    /// 监听回调的唯一出口：像素 → 整天 → 新窗口起点 → 派发。
    func applyScroll(deltaX: Double) {
        let days = consumeScroll(deltaX: deltaX)
        guard days != 0, let store else { return }
        // 内容跟手：向右滑（正位移）看更早日期 ⇒ 窗口起点减小。
        // 起点由本方法就地推进，避免连续事件拿到旧快照重复派发同一目标。
        let target = advance(byDays: days)
        Self.logger.notice("pan commit: \(days, privacy: .public) days → \(target, privacy: .public)")
        store.dispatch(.panWindow(to: target))
    }

    /// 提交平移后推进本地起点并返回目标日期（正 = 看更早日期）。
    func advance(byDays days: Int) -> Date {
        guard days != 0 else { return windowStart }
        let calendar = Calendar.current
        let shifted = calendar.date(byAdding: .day, value: -days, to: windowStart) ?? windowStart
        windowStart = calendar.startOfDay(for: shifted)
        return windowStart
    }

    /// 缩放档位 / 窗口被外部重置时清空余量，避免旧余量在新尺度下突变。
    func resetAccumulator() {
        accumulator.reset()
    }
}
