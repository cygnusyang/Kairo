import SwiftUI

/// ⌘K 命令面板（US-E4-05 / F-41-01）：模糊过滤注册表中的全部命令并执行。
struct CommandPalette: View {
    let commands: [KairoCommand]
    let onDismiss: () -> Void

    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    private var filtered: [KairoCommand] {
        Self.matching(query, in: commands)
    }

    /// 按命令标题与搜索别名不区分大小写过滤（US-E4-05 验收 2）；空查询返回全部命令。
    static func matching(_ query: String, in commands: [KairoCommand]) -> [KairoCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return commands }
        return commands.filter { command in
            command.title.localizedCaseInsensitiveContains(trimmed)
                || command.aliases.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "command")
                        .foregroundStyle(.secondary)
                    TextField(I18n.t("palette.search.placeholder", "Search commands…"), text: $query)
                        .textFieldStyle(.plain)
                        .focused($fieldFocused)
                        .onSubmit(runFirstMatch)
                }
                .padding(12)

                Divider()

                if filtered.isEmpty {
                    ContentUnavailableView(I18n.t("palette.empty.title", "No matching commands"), systemImage: "magnifyingglass")
                        .frame(height: 160)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { command in
                                row(command)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }

                Divider()
                HStack {
                    Text(I18n.t("palette.result.count", "%1$ld commands", filtered.count))
                    Spacer()
                    Text(I18n.t("palette.hint", "⏎ Run · Esc Close"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(width: 480)
            .background(DesignTokens.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(DesignTokens.separator, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 24)
            .padding(.top, 80)
        }
        .onAppear { fieldFocused = true }
        .onExitCommand(perform: onDismiss)
    }

    private func row(_ command: KairoCommand) -> some View {
        Button {
            run(command)
        } label: {
            HStack(spacing: 10) {
                Text(command.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(command.group.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let shortcut = command.shortcut {
                    Text(shortcut.label)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func runFirstMatch() {
        guard let first = filtered.first else { return }
        run(first)
    }

    private func run(_ command: KairoCommand) {
        command.action()
        onDismiss()
    }
}
