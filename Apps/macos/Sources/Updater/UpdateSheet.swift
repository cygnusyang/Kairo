// UpdateSheet.swift —— 更新面板（状态化头部 + 详情 + 尾部动作）。
//
// 纪律（沿 COFFER 裁定）：安装唯一入口为 .downloaded 态确认弹窗——
// 「退出 + 替换二进制」动作单点化确认；.installing 态放开交互关闭
//（关闭即走「关面板 → 0.5s → terminate」序列）；检查失败绝不静默归
// 「已是最新」。
//
// 视觉（ui-redesign §2 表面/字号 token）：头部 = 语义图标徽章 + 标题 + 说明，
// 详情区按状态给进度/版本说明/错误，尾部按钮右对齐；不再用「一行文字 + 好」
// 的裸对话框形态。

import SwiftUI
import KairoUpdater

/// 更新面板（由「检查更新…」菜单触发挂载）。
struct UpdateSheet: View {
    @ObservedObject var updater: UpdaterManager
    /// 关闭请求（.installing 确认后由本面板发起，交宿主执行退出序列）。
    let onRequestClose: () -> Void

    private enum Layout {
        static let width: CGFloat = 400
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 16
        static let badgeSize: CGFloat = 40
        static let notesMaxHeight: CGFloat = 132
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if showsDetail {
                Divider().overlay(DesignTokens.separator)
                detail
            }
            Divider().overlay(DesignTokens.separator)
            footer
        }
        .frame(width: Layout.width)
        .background(DesignTokens.surfaceBase)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(statusTint.opacity(0.12))
                Image(systemName: statusSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(statusTint)
            }
            .frame(width: Layout.badgeSize, height: Layout.badgeSize)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(subheadline)
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 详情

    /// 只有需要额外说明/进度的状态才占详情区，避免「已是最新」出现空档。
    private var showsDetail: Bool {
        switch updater.state {
        case .idle, .checking, .updateAvailable, .downloading, .installing, .failed:
            return true
        case .upToDate, .downloaded:
            return false
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch updater.state {
        case .idle, .checking, .installing:
            progressBar(nil)
        case .downloading(let progress):
            progressBar(progress)
        case .updateAvailable(let info):
            updateAvailableDetail(info)
        case .failed(let failure):
            Text(UpdaterFailureText.text(failure))
                .font(.system(size: DesignTokens.captionFontSize))
                .foregroundStyle(DesignTokens.violationError)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.vertical, Layout.verticalPadding)
        case .upToDate, .downloaded:
            EmptyView()
        }
    }

    private func progressBar(_ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let value {
                ProgressView(value: min(max(value, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(DesignTokens.progressFill)
                Text("\(Int((min(max(value, 0), 1) * 100).rounded()))%")
                    .font(.system(size: DesignTokens.captionFontSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.textSecondary)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(DesignTokens.progressFill)
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
    }

    private func updateAvailableDetail(_ info: UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let notes = info.notes, !notes.isEmpty {
                ScrollView {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: Layout.notesMaxHeight)
                .padding(10)
                .background(
                    DesignTokens.surfaceChrome,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            }
            Text(info.securityCritical
                ? I18n.t("update.headline.security_critical_note", "This update contains security fixes and should be installed now. The app must quit after the download is verified to finish installing.")
                : I18n.t("update.headline.install_note", "The app must quit after the download is verified to finish installing."))
                .font(.system(size: DesignTokens.captionFontSize))
                .foregroundStyle(
                    info.securityCritical
                        ? DesignTokens.violationWarning
                        : DesignTokens.textSecondary
                )
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
    }

    // MARK: - 尾部动作

    @ViewBuilder
    private var footer: some View {
        switch updater.state {
        case .idle, .checking, .downloading, .installing:
            EmptyView()
        case .upToDate:
            actionRow {
                Button(I18n.t("action.ok", "OK")) { close() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.accentBase)
            }
        case .updateAvailable(let info):
            HStack(spacing: 8) {
                if !info.securityCritical {
                    Button(I18n.t("update.action.skip_version", "Skip This Version")) {
                        updater.skipCurrentUpdate()
                        onRequestClose()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
                }
                Spacer(minLength: 0)
                Button(I18n.t("update.action.later", "Later")) { onRequestClose() }
                    .buttonStyle(.bordered)
                Button(I18n.t("update.action.download", "Download Update")) { Task { await updater.download() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.accentBase)
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, 14)
        case .downloaded:
            actionRow {
                Button(I18n.t("action.cancel", "Cancel")) { close() }
                    .buttonStyle(.bordered)
                Button(I18n.t("update.action.quit_and_install", "Quit and Install")) { install() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.accentBase)
            }
        case .failed:
            actionRow {
                Button(I18n.t("action.close", "Close")) { close() }
                    .buttonStyle(.bordered)
                Button(I18n.t("update.action.retry", "Retry")) { Task { await updater.check() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.accentBase)
            }
        }
    }

    private func actionRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            content()
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, 14)
    }

    // MARK: - 动作

    private func close() {
        updater.dismiss()
        onRequestClose()
    }

    /// 下载完成后唯一的安装入口：退出 + 替换二进制 + 自动重启。
    private func install() {
        Task {
            await updater.install()
            // install() 成功路径不返回状态迁移（保持 .installing）；
            // 失败会转 .failed，仅在 still installing 时执行退出序列。
            if case .installing = updater.state {
                try? await Task.sleep(nanoseconds: 500_000_000)
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - 状态文案

    private var statusSymbol: String {
        switch updater.state {
        case .idle, .checking: return "arrow.triangle.2.circlepath"
        case .upToDate: return "checkmark.seal.fill"
        case .updateAvailable: return "arrow.down.circle.fill"
        case .downloading: return "arrow.down.circle"
        case .downloaded: return "shippingbox.fill"
        case .installing: return "gearshape.2.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusTint: Color {
        switch updater.state {
        case .upToDate, .downloaded: return DesignTokens.statusSuccess
        case .failed: return DesignTokens.violationError
        default: return DesignTokens.accentBase
        }
    }

    private var headline: String {
        switch updater.state {
        case .idle, .checking: return I18n.t("update.state.checking.title", "Checking for updates")
        case .upToDate: return I18n.t("update.state.up_to_date.title", "Kairo is up to date")
        case .updateAvailable(let info): return I18n.t("update.state.available.title", "Version %1$@ is available", info.version)
        case .downloading: return I18n.t("update.state.downloading.title", "Downloading the update")
        case .downloaded: return I18n.t("update.state.downloaded.title", "Update downloaded and verified")
        case .installing: return I18n.t("update.state.installing.title", "Installing the update")
        case .failed: return I18n.t("update.state.failed.title", "Update check failed")
        }
    }

    private var subheadline: String {
        switch updater.state {
        case .idle, .checking:
            return I18n.t("update.state.checking.subtitle", "Confirming the version with the update server…")
        case .upToDate:
            return I18n.t("update.state.up_to_date.subtitle", "Current version %1$@; no update needed.", Self.currentVersionDescription)
        case .updateAvailable:
            return I18n.t("update.state.available.subtitle", "Current version %1$@.", Self.currentVersionDescription)
        case .downloading:
            return I18n.t("update.state.downloading.subtitle", "The app must quit to finish installing; keep it open until the download completes.")
        case .downloaded:
            return I18n.t("update.state.downloaded.subtitle", "Kairo will quit, replace the binary, and restart automatically.")
        case .installing:
            return I18n.t("update.state.installing.subtitle", "The app is about to quit and restart automatically; do not close it manually.")
        case .failed:
            return I18n.t("update.state.failed.subtitle", "The update check could not be completed; try again later.")
        }
    }

    private static var currentVersionDescription: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard let build = info["CFBundleVersion"] as? String, !build.isEmpty else {
            return version
        }
        return I18n.t("update.version_description", "%1$@ (Build %2$@)", version, build)
    }
}
