import SwiftUI
import KairoCore
import KairoPresentation

/// 日宽拖动提交节流状态机（引用语义）。
///
/// 独立于 View 存在：`@State` 在未安装视图上按值拷贝、方法调用间状态不延续，
/// 单元测试无法真实驱动「拖动 → 节流 → 松手/关闭」的生命线（连续调用每次都像首拖，
/// 节流分支形同虚设）。引用语义保证真实面板与自动化测试走同一条状态生命线
/// （D-015 自动化验收的基础，也是 D-010 修复的可回归载体）。
@MainActor
final class DayWidthThrottle {
    /// 提交节流间隔（秒）：拖动中最多每 100ms 提交一次。
    static let commitInterval: TimeInterval = 0.1

    /// 拖动中的本地草稿；nil 时面板跟随外部生效值。
    private(set) var draft: Double?
    /// 节流窗口内待提交的收尾任务。
    private(set) var pendingCommit: Task<Void, Never>?
    /// 上次提交时刻（节流基准）。
    private var lastCommitAt = Date.distantPast

    private let commit: @MainActor (Double) -> Void

    init(commit: @escaping @MainActor (Double) -> Void) {
        self.commit = commit
    }

    /// 外部生效值更新（如面板打开时按 ⌘+）：丢弃本地草稿，读数与滑杆回到生效值。
    func discardDraft() {
        draft = nil
    }

    /// 拖动中按节流提交；节流窗口内的最后一次变更由待提交任务补上。
    func slide(_ width: Double) {
        draft = width
        let elapsed = Date().timeIntervalSince(lastCommitAt)
        if elapsed >= Self.commitInterval {
            commitNow(width)
        } else {
            pendingCommit?.cancel()
            let delay = Self.commitInterval - elapsed
            pendingCommit = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.commitNow(width)
            }
        }
    }

    /// 收尾（松手 / 面板消失共用）：提交最终草稿值并取消待提交任务——
    /// 节流窗口内的末值不能丢（设计稿 R-02、D-010）。
    func finish() {
        pendingCommit?.cancel()
        pendingCommit = nil
        if let draft {
            commitNow(draft)
            self.draft = nil
        }
    }

    private func commitNow(_ width: Double) {
        lastCommitAt = Date()
        commit(width)
    }
}

/// 日宽调节面板（工具栏 popover 内容）。
///
/// 构成：连续滑杆（对数映射）+ 读数 + ± 步进 + 档位芯片 + 重置。
/// 拖动中按 ≥100ms 节流提交、松手必提交最终值（设计稿 R-02）；
/// 面板、菜单步进与快捷键共用同一组动作，不产生第二套真相源。
struct DayWidthControl: View {
    @ObservedObject var store: WorkspaceStore
    /// 生效日宽（点/天）：自定义取用户值，fit 取 fit 宽度，预设取档位默认。
    let dayWidth: Double

    /// 拖动提交节流状态机（引用语义，跨重渲染持久）。
    /// 模块内可见：UX 自动化测试经 `@testable import` 直接驱动同一实例。
    @State var throttle: DayWidthThrottle
    /// 拖动中：本地草稿权威，外部生效值的变化不打断手势。
    @State private var isDragging = false

    init(store: WorkspaceStore, dayWidth: Double) {
        self.store = store
        self.dayWidth = dayWidth
        _throttle = State(initialValue: DayWidthThrottle { width in
            store.dispatch(.setCustomDayWidth(width))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(I18n.t("daywidth.title", "Day width"))
                .font(.system(size: DesignTokens.bodyFontSize, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
            stepperRow
            slider
            presetRow
            Text(I18n.t("daywidth.range", "Range %1$@ pts/day", rangeHint))
                .font(.system(size: DesignTokens.captionFontSize))
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(12)
        .frame(width: 268)
        .onChange(of: dayWidth) { _, _ in
            // 外部生效值变了（如面板打开时按 ⌘+）：丢弃本地草稿，读数与滑杆回到生效值。
            // 拖动中不丢弃：节流提交的回声会与手势互相打断，滑杆会往回跳。
            guard !isDragging else { return }
            throttle.discardDraft()
        }
        .onDisappear {
            throttle.finish()
        }
    }

    // MARK: - 子视图

    private var stepperRow: some View {
        HStack(spacing: 8) {
            stepButton(title: I18n.t("daywidth.narrower", "Narrower"), delta: -GanttScale.dayWidthStep, symbol: "minus")
            Spacer(minLength: 0)
            Text(readout)
                .font(.system(size: DesignTokens.bodyFontSize))
                .foregroundStyle(DesignTokens.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 84)
            Spacer(minLength: 0)
            stepButton(title: I18n.t("daywidth.wider", "Wider"), delta: GanttScale.dayWidthStep, symbol: "plus")
        }
    }

    private var slider: some View {
        Slider(
            value: sliderPosition,
            in: 0...1,
            onEditingChanged: { editing in
                isDragging = editing
                if !editing { throttle.finish() }
            }
        )
        .accessibilityLabel(I18n.t("daywidth.accessibility_label", "Daily width"))
        .accessibilityValue(readout)
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            ForEach(GanttZoom.allCases, id: \.self) { zoom in
                Button(presetTitle(zoom)) { applyPreset(zoom) }
                    .buttonStyle(.bordered)
                    .font(.system(size: DesignTokens.captionFontSize))
                    .help(I18n.t("daywidth.preset.help", "%1$@: %2$ld pts/day", presetTitle(zoom), Int(zoom.dayWidth)))
            }
            Button(I18n.t("action.reset", "Reset")) { applyReset() }
                .buttonStyle(.bordered)
                .font(.system(size: DesignTokens.captionFontSize))
                .help(I18n.t("daywidth.reset.help", "Back to the current preset’s default width"))
        }
    }

    private func stepButton(title: String, delta: Double, symbol: String) -> some View {
        Button {
            apply(width: GanttScale.clampDayWidth(currentWidth + delta))
        } label: {
            HStack(spacing: 2) {
                Image(systemName: symbol)
                Text("\(Int(abs(delta)))")
            }
            .font(.system(size: DesignTokens.captionFontSize))
            .frame(minWidth: 34)
        }
        .buttonStyle(.bordered)
        .help(I18n.t("daywidth.step.help", "%1$@ %2$ld pts/day", title, Int(abs(delta))))
        .accessibilityLabel(I18n.t("daywidth.step.help", "%1$@ %2$ld pts/day", title, Int(abs(delta))))
    }

    // MARK: - 读数与映射

    /// 当前面板显示的日宽：拖动中用本地值，否则跟随生效值。
    private var currentWidth: Double {
        throttle.draft ?? dayWidth
    }

    private var readout: String {
        Display.pointsPerDay(currentWidth)
    }

    private var rangeHint: String {
        let lower = Int(GanttScale.dayWidthRange.lowerBound)
        let upper = Int(GanttScale.dayWidthRange.upperBound)
        return "\(lower)–\(upper)"
    }

    /// 档位按钮标题：档位名取 Display 的同一份文案（F-0705），数值为该档位默认日宽。
    private func presetTitle(_ zoom: GanttZoom) -> String {
        let name: String
        switch zoom {
        case .day: name = Display.zoomPresetTitle(.day)
        case .week: name = Display.zoomPresetTitle(.week)
        case .month: name = Display.zoomPresetTitle(.month)
        }
        return "\(name) \(Int(zoom.dayWidth))"
    }

    /// 滑杆位置（0…1）↔ 日宽。
    private var sliderPosition: Binding<Double> {
        Binding(
            get: { Self.position(forDayWidth: currentWidth) },
            set: { throttle.slide(Self.dayWidth(forPosition: $0)) }
        )
    }

    /// 日宽 → 滑杆位置的对数映射。
    ///
    /// 线性映射会把常用区（5–32 点/天）挤在左端四分之一；对数映射下常用区落在中段，
    /// 拖动手感均匀。
    static func position(forDayWidth width: Double) -> Double {
        let clamped = GanttScale.clampDayWidth(width)
        let lower = GanttScale.dayWidthRange.lowerBound
        let upper = GanttScale.dayWidthRange.upperBound
        return log(clamped / lower) / log(upper / lower)
    }

    /// 滑杆位置 → 日宽（点/天），结果落在合法区间内。
    static func dayWidth(forPosition position: Double) -> Double {
        let lower = GanttScale.dayWidthRange.lowerBound
        let upper = GanttScale.dayWidthRange.upperBound
        let t = min(max(position, 0), 1)
        return GanttScale.clampDayWidth(lower * pow(upper / lower, t))
    }

    // MARK: - 提交

    /// 设定宽度：先夹取再提交；提交后本地草稿失效，跟随生效值。
    private func apply(width: Double) {
        throttle.discardDraft()
        store.dispatch(.setCustomDayWidth(width))
    }

    private func applyPreset(_ zoom: GanttZoom) {
        throttle.discardDraft()
        store.dispatch(.setZoom(zoom))
    }

    private func applyReset() {
        throttle.discardDraft()
        store.dispatch(.clearCustomDayWidth)
    }
}
