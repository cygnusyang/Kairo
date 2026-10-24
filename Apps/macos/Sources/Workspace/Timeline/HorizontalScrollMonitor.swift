import AppKit
import Foundation
import KairoPresentation
import os

/// 画布横向滚动捕获（F-14-18，薄胶水层）。
///
/// SwiftUI 没有 scrollWheel 钩子，且画布是「视口宽的 Canvas + 时间窗」模型
/// （无横向 ScrollView），故用本地事件监听把画布内的横向滚动换算成窗口平移。
///
/// 判定依据只有两条：**光标在画布视口内** 且 **当前不在文本编辑**。
/// 不按「事件属于哪个窗口」判定 —— 2026-10-24 现场日志实证：
/// `scrollWheel` 的 `event.window` 为 nil、`NSApp.keyWindow` 指向辅助窗口，
/// 按窗口身份比会把真机双指横滑全部当作「非画布事件」放行（D-027 二次回归）。
///
/// 坐标：视口来自 `CanvasViewportProbe`（AppKit 窗口坐标，左下原点），光标由屏幕
/// 坐标经 `NSWindow.convertPoint(fromScreen:)` 换到同一空间，不做手工翻转。
///
/// 单实例：`start()` 为接管语义，且生产侧统一使用 `shared`（D-027）。
@MainActor
final class HorizontalScrollMonitor {
    /// 采集环境：全部用闭包注入，便于单测替换窗口与光标。
    struct Environment {
        /// 画布视口（画布所在窗口坐标，左下原点）；未挂载时 nil。
        var viewportInWindow: () -> CGRect?
        /// 画布所在窗口；未挂载时 nil。
        var window: () -> NSWindow?
        /// 光标屏幕坐标（测试注入固定点，生产用 `NSEvent.mouseLocation`）。
        var cursorInScreen: () -> CGPoint
        /// 平移回调（点；正 = 内容右移）。
        var handler: (Double) -> Void
    }

    /// 全进程单例：与 `HorizontalPanContext.shared` 配套（D-027）。
    ///
    /// 监听常驻、几何随探针更新；视图重建只是重新 `start()`（幂等），不会叠出新实例。
    static let shared = HorizontalScrollMonitor(.init(
        viewportInWindow: { HorizontalPanContext.shared.viewportInWindow },
        window: { HorizontalPanContext.shared.window },
        cursorInScreen: { NSEvent.mouseLocation },
        handler: { HorizontalPanContext.shared.applyScroll(deltaX: $0) }
    ))

    /// 当前唯一活动的监听实例（D-027）。
    ///
    /// SwiftUI 在结构身份变化时会重复触发 `onAppear`，而旧实例的 `onDisappear`
    /// 不保证执行；若放任多个实例同时 `start()`，先安装的实例会持续抢占事件，
    /// 并用自己那份已经过期的窗口起点派发 `.panWindow`，表现为「双指横滑画布不动」。
    /// 因此 `start()` 是接管语义：新实例启动即停掉旧实例。
    private static weak var active: HorizontalScrollMonitor?

    private static let logger = Logger(subsystem: "ai.kairo.app", category: "gantt-pan")
    /// 每种放行原因每次运行只记一条，避免高频滚动刷屏。
    private static var reportedReasons: Set<String> = []
    /// 首次成功消费只记一条（便于现场核对「事件到底有没有到」）。
    private static var reportedFirstPan = false
    /// 首个滚动事件的完整上下文只记一条（现场排查的黄金证据）。
    private static var reportedFirstDecision = false

    private let environment: Environment
    private var token: Any?

    /// 是否正在监听（单实例仲裁的可测口径）。
    var isRunning: Bool { token != nil }

    /// 当前活动实例（测试断言用）。
    static var activeInstance: HorizontalScrollMonitor? { active }

    init(_ environment: Environment) {
        self.environment = environment
    }

    func start() {
        // 接管：先停掉可能残留的旧实例，保证同一时刻只有一个监听在消费事件。
        if let previous = Self.active, previous !== self {
            previous.stop()
        }
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        Self.active = self
        Self.logger.notice("horizontal pan monitor installed (pid=\(ProcessInfo.processInfo.processIdentifier))")
    }

    func stop() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
        if Self.active === self {
            Self.active = nil
        }
    }

    /// 命中则消费事件（返回 nil），否则原样放行。
    func handle(_ event: NSEvent) -> NSEvent? {
        let target = environment.window()
        let decision = decide(
            deltaX: Double(event.scrollingDeltaX),
            deltaY: Double(event.scrollingDeltaY),
            shift: event.modifierFlags.contains(.shift),
            isEditingText: Self.isEditingText(window: target, cursorInScreen: environment.cursorInScreen())
        )
        switch decision {
        case .pan(let pixels):
            if !Self.reportedFirstPan {
                Self.reportedFirstPan = true
                Self.logger.notice("horizontal pan first consume: \(pixels, privacy: .public)pt")
            }
            Self.logger.debug("horizontal pan consume: \(pixels, privacy: .public)pt")
            environment.handler(pixels)
            return nil
        case .ignore(let reason):
            Self.reportOnce(reason)
            return event
        }
    }

    /// 采集几何后交给纯函数判定（单测直接调用此方法，无需构造 `NSEvent`）。
    func decide(
        deltaX: Double,
        deltaY: Double,
        shift: Bool,
        isEditingText: Bool
    ) -> GanttScrollDecision {
        let target = environment.window()
        let cursor: CGPoint? = target.map {
            $0.convertPoint(fromScreen: environment.cursorInScreen())
        }
        // 探针还没上报（视图重建中）时回落到整块内容区：宁可多命中一点，
        // 也不能让「双指横滑」在画布上彻底失效（D-027 二次排查）。
        let viewport: CGRect? = target.map {
            environment.viewportInWindow() ?? $0.contentView?.bounds ?? .zero
        }
        let cursorInside: Bool = {
            guard let cursor, let viewport else { return false }
            return viewport.contains(cursor)
        }()
        if !Self.reportedFirstDecision {
            Self.reportedFirstDecision = true
            Self.logger.notice("""
            first scroll event: dx=\(deltaX, privacy: .public) dy=\(deltaY, privacy: .public) \
            shift=\(shift, privacy: .public) viewport=\(String(describing: viewport), privacy: .public) \
            cursor=\(String(describing: cursor), privacy: .public) inside=\(cursorInside, privacy: .public)
            """)
        }
        return GanttScrollRouter.decide(GanttScrollInput(
            deltaX: deltaX,
            deltaY: deltaY,
            shift: shift,
            hasViewport: viewport != nil,
            hasCursor: cursor != nil,
            cursorInsideViewport: cursorInside,
            isEditingText: isEditingText
        ))
    }

    /// 光标是否正落在可编辑文本里。
    ///
    /// 不能用「窗口首响应者是 `NSTextView`」粗判：SwiftUI 工作台窗口在**没有**
    /// 任何输入框获得焦点时，首响应者也常常是窗口共用的 field editor，
    /// 于是每条滚动都被当作「编辑中」放行 —— 2026-10-24 现场日志实证（D-027）。
    /// 正确口径：只有光标确实落在该文本视图可见范围内，才把滚动让给文本。
    static func isEditingText(window: NSWindow?, cursorInScreen: CGPoint) -> Bool {
        guard let window,
              let textView = window.firstResponder as? NSTextView,
              textView.isEditable else { return false }
        let cursor = window.convertPoint(fromScreen: cursorInScreen)
        let frameInWindow = textView.convert(textView.bounds, to: nil)
        return frameInWindow.contains(cursor)
    }

    private static func reportOnce(_ reason: GanttScrollIgnoreReason) {
        guard reportedReasons.insert(reason.rawValue).inserted else { return }
        logger.notice("horizontal pan passed through: \(reason.rawValue, privacy: .public)")
    }
}
