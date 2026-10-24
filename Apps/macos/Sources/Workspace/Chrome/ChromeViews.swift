import SwiftUI
import KairoCore
import KairoPresentation

/// 筛选栏（32pt）：自然语言筛选 + 令牌 + 查找入口。
struct FilterBar: View {
    @ObservedObject var store: WorkspaceStore
    @FocusState private var filterFocused: Bool

    private var filterBinding: Binding<String> {
        Binding(
            get: { store.viewState.filterText },
            set: { store.dispatch(.setFilter($0)) }
        )
    }

    private var clauses: [FilterClause] {
        AIFilterTranslator.translate(store.viewState.filterText)
    }

    private var tokens: [String] {
        AIFilterTranslator.tokenize(store.viewState.filterText)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(DesignTokens.textSecondary)
            TextField("筛选任务（如：进行中 逾期 tag:设计）", text: filterBinding)
                .textFieldStyle(.plain)
                .font(.system(size: DesignTokens.bodyFontSize))
                .focused($filterFocused)
                .onSubmit { filterFocused = false }

            if !clauses.isEmpty {
                Text(AIFilterTranslator.explanation(for: clauses))
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
                ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                    FilterChip(label: token) {
                        store.dispatch(.setFilter(removing(tokens: tokens, at: index)))
                    }
                }
            }

            Spacer(minLength: 0)

            if store.showFindBar {
                FindBar(find: store.find, focusToken: store.findFocusToken)
            }

            Button {
                store.showFindBar.toggle()
                if store.showFindBar { store.findFocusToken += 1 }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("查找任务（⌘F）")

            Button {
                store.filterBarVisible = false
                if !store.viewState.filterText.isEmpty {
                    store.dispatch(.setFilter(""))
                }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("收起筛选栏")
        }
        .padding(.horizontal, 12)
        .frame(height: DesignTokens.filterBarHeight)
        .background(DesignTokens.surfaceChrome)
    }

    private func removing(tokens: [String], at index: Int) -> String {
        var copy = tokens
        guard copy.indices.contains(index) else { return copy.joined(separator: " ") }
        copy.remove(at: index)
        return copy.joined(separator: " ")
    }
}

/// 筛选令牌。
struct FilterChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: DesignTokens.captionFontSize))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(DesignTokens.selection, in: Capsule())
    }
}

/// 查找栏（嵌在筛选栏内）。
struct FindBar: View {
    @ObservedObject var find: FindModel
    let focusToken: Int
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("查找", text: $find.lastFindString)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
                .focused($focused)
                .onAppear {
                    DispatchQueue.main.async { focused = true }
                }
                .onChange(of: focusToken) { _, _ in focused = true }
                .onSubmit { find.findNext() }
                .onChange(of: find.lastFindString) { _, _ in find.rescan() }
                .onChange(of: find.regexMode) { _, _ in find.rescan() }
            Text("\(find.currentIndex.map { $0 + 1 } ?? 0)/\(find.matchCount)")
                .font(.system(size: DesignTokens.captionFontSize))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(minWidth: 40, alignment: .trailing)
            Button { find.findPrevious() } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(find.matchCount == 0)
            Button { find.findNext() } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(find.matchCount == 0)
            Button { find.regexMode.toggle() } label: {
                Image(systemName: "textformat.abc.dottedunderline")
                    .foregroundStyle(find.regexMode ? DesignTokens.accentStrong : DesignTokens.textSecondary)
            }
            .buttonStyle(.plain)
            .help("正则模式")
            if find.invalidRegex {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(DesignTokens.violationWarning)
                    .help("正则表达式无效")
            }
        }
    }
}

/// 状态栏（26pt）：健康、进度、计数、可见范围、缩放与保存状态。
struct StatusBarView: View {
    @ObservedObject var store: WorkspaceStore

    private var status: StatusBarSnapshot { store.snapshot.statusBar }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 12) {
                healthItem
                metric(Display.percent(status.weightedProgress), help: "加权总进度")
                metric("逾期 \(status.overdueCount)", help: "逾期未完成叶子任务")
                if status.violationErrorCount + status.violationWarningCount > 0 {
                    metric(
                        "违例 \(status.violationErrorCount + status.violationWarningCount)",
                        help: "错误 \(status.violationErrorCount) / 警告 \(status.violationWarningCount)"
                    )
                }
                if width >= 980, status.criticalPathCount > 0 {
                    metric("重要路径 \(status.criticalPathCount)", help: "总宽延为 0 的任务数")
                }
                if width >= 1100, let days = status.remainingDays {
                    metric("剩余 \(days) 天", help: "距项目结束")
                }
                if width >= 1100, let summary = status.selectionSummary {
                    Text(summary)
                        .lineLimit(1)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .help(summary)
                }

                Spacer(minLength: 0)

                if width >= 980, let start = status.visibleStart, let end = status.visibleEnd {
                    Text("\(Display.shortDate(start)) – \(Display.shortDate(end))")
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                if width >= 900 {
                    // 档位 + 实际日宽（如「自定义 · 20 点/天」）。
                    Text(Display.zoomIndicator(status.zoom))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                if !status.todayVisible {
                    Button("今天") { store.dispatch(.goToToday) }
                        .buttonStyle(.plain)
                        .foregroundStyle(DesignTokens.accentStrong)
                        .help("回到今天（⌥⌘T）")
                }
                Text(Display.saveStateTitle(status.saveState))
                    .foregroundStyle(saveColor)
                    .help(Display.saveStateTitle(status.saveState))
            }
            .font(.system(size: DesignTokens.captionFontSize))
            .padding(.horizontal, 10)
        }
        .frame(height: DesignTokens.statusBarHeight)
        .background(DesignTokens.surfaceChrome)
    }

    private var healthItem: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(healthColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(Display.healthTitle(status.health))
                .foregroundStyle(DesignTokens.textPrimary)
        }
        .help("项目健康度：\(Display.healthTitle(status.health))")
    }

    private var healthColor: Color {
        switch status.health {
        case .green: return DesignTokens.statusSuccess
        case .orange: return DesignTokens.violationWarning
        case .red: return DesignTokens.violationError
        }
    }

    private var saveColor: Color {
        switch status.saveState {
        case .saved: return DesignTokens.textSecondary
        case .unsaved: return DesignTokens.textPrimary
        case .failed: return DesignTokens.violationError
        }
    }

    private func metric(_ text: String, help: String) -> some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(DesignTokens.textPrimary)
            .help(help)
    }
}

/// 外部更新条：磁盘文件变化且本地有未保存修改时出现（ADR-013 第 8 条）。
struct ExternalUpdateBar: View {
    @ObservedObject var store: WorkspaceStore
    @State private var confirmingReload = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: DesignTokens.captionFontSize))
                .foregroundStyle(DesignTokens.violationWarning)
            Text("项目已在磁盘上更新")
                .font(.system(size: DesignTokens.bodyFontSize))
            Spacer(minLength: 0)
            Button("重新载入") { confirmingReload = true }
                .controlSize(.small)
            Button("保留本地") { store.dispatch(.keepLocal) }
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(DesignTokens.surfaceChrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.separator).frame(height: 1)
        }
        .confirmationDialog(
            "重新载入会丢弃未保存的修改",
            isPresented: $confirmingReload
        ) {
            Button("丢弃修改并重新载入", role: .destructive) {
                store.dispatch(.reloadExternal)
            }
            Button("取消", role: .cancel) {}
        }
    }
}

/// 加载骨架屏：仅在载入超过 150ms 时覆盖工作区（阶段 5）。
struct LoadingSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在载入项目…")
                    .font(.system(size: DesignTokens.bodyFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            ForEach(0..<10, id: \.self) { index in
                HStack(spacing: 8) {
                    Capsule()
                        .fill(DesignTokens.progressTrack)
                        .frame(width: 18, height: 10)
                    Capsule()
                        .fill(DesignTokens.progressTrack.opacity(index.isMultiple(of: 2) ? 0.9 : 0.6))
                        .frame(width: index.isMultiple(of: 3) ? 220 : 320, height: 10)
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(DesignTokens.progressTrack.opacity(0.7))
                        .frame(width: 90, height: 10)
                }
                .padding(.horizontal, 12)
                .frame(height: DesignTokens.rowHeight)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.surfaceBase)
        .accessibilityLabel("正在载入项目")
    }
}
