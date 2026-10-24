import Foundation
import SwiftUI
import KairoCore

@main
struct KairoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = WorkspaceStore()
    @StateObject private var updater = UpdaterConfiguration.makeUpdater()
    @State private var showOpenPanel = false
    @State private var showSavePanel = false
    @State private var showUpdateSheet = false
    @State private var errorMessage: String?

    var body: some Scene {
        WindowGroup("Kairo") {
            WorkspaceView(store: store, commands: commandCatalog)
                .frame(
                    minWidth: DesignTokens.minimumWindowWidth,
                    minHeight: DesignTokens.minimumWindowHeight
                )
                .onAppear {
                    appDelegate.store = store
                    // 首启消费上次 OTA 安装结果（幂等；无 pending 则 no-op）。
                    updater.consumePendingInstallResult()
                    scheduleAutoUpdateChecks()
                }
                .onOpenURL { handleDeepLink($0) }
                .sheet(isPresented: $showUpdateSheet) {
                    UpdateSheet(
                        updater: updater,
                        onRequestClose: { showUpdateSheet = false }
                    )
                }
                .fileImporter(
                    isPresented: $showOpenPanel,
                    allowedContentTypes: [.kairo],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        openFile(url)
                    }
                }
                .fileExporter(
                    isPresented: $showSavePanel,
                    document: KairoDocument(state: store.exportState),
                    contentType: .kairo,
                    defaultFilename: store.suggestedSaveFilename
                ) { result in
                    switch result {
                    case .success(let url):
                        finishExport(to: url)
                    case .failure(let error):
                        store.cancelExport()
                        if let message = ExportFailure.message(for: error) {
                            errorMessage = message
                        }
                    }
                }
                .alert(
                    I18n.t("alert.error.title", "Error"),
                    isPresented: Binding(
                        get: { errorMessage != nil },
                        set: { if !$0 { errorMessage = nil } }
                    )
                ) {
                    Button(I18n.t("action.ok", "OK"), role: .cancel) {}
                } message: {
                    Text(errorMessage ?? "")
                }
        }
        .defaultSize(
            width: DesignTokens.defaultWindowWidth,
            height: DesignTokens.defaultWindowHeight
        )
        .commands {
            KairoMenuCommands(
                commands: commandCatalog,
                checkForUpdates: {
                    showUpdateSheet = true
                    Task { await updater.check() }
                }
            )
        }
    }

    /// 全应用命令注册表：菜单栏与 ⌘K 面板共用（US-E4-05 验收 3）。
    private var commandCatalog: [KairoCommand] {
        KairoCommandCatalog.make(
            store: store,
            requestOpen: { showOpenPanel = true },
            requestSave: { saveDocument() },
            requestSaveAs: { saveDocumentAs() }
        )
    }

    // MARK: - OTA 自动检查

    /// 已自动弹过面板的版本（同一版本一次运行内只弹一次；用户「跳过此版本」
    /// 后 check() 会解析为 upToDate，不再打扰）。
    @State private var autoPresentedVersion: String?

    /// 自动检查：启动后 5s 静默查一次，此后每 4 小时一次。静默 = 网络失败不弹
    /// 面板（状态留在 manager，手动检查可见）；发现新版本（未跳过）才自动
    /// 展示更新面板，同版本去重。
    private func scheduleAutoUpdateChecks() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UpdaterConfiguration.autoCheckInitialDelayNanoseconds)
            await silentCheck()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UpdaterConfiguration.autoCheckIntervalNanoseconds)
                await silentCheck()
            }
        }
    }

    @MainActor
    private func silentCheck() async {
        await updater.check()
        if case .updateAvailable(let info) = updater.state,
           autoPresentedVersion != info.version {
            autoPresentedVersion = info.version
            showUpdateSheet = true
        }
    }

    // MARK: - 深链

    /// `kairo://task/<id>`、`kairo://task?title=<标题>`、`kairo://project/<id>`（US-E5-04）。
    /// 双击 `.kairo` 文件走 LaunchServices 的 `file://` 事件，直接按文件打开。
    private func handleDeepLink(_ url: URL) {
        if url.isFileURL {
            openFile(url)
            return
        }
        guard let link = KairoDeepLink.parse(url) else {
            errorMessage = I18n.t("error.deeplink.unrecognized", "Unrecognized Kairo link: %1$@", url.absoluteString)
            return
        }
        let project = store.exportProject
        let match = KairoDeepLinkResolver.resolve(link, in: project)
        switch link.target {
        case .projectID:
            if !match.projectMatched {
                errorMessage = I18n.t("error.deeplink.other_project", "The link points to another project; the current project is “%1$@”", project.metadata.title)
            }
        case .taskID, .taskTitle:
            guard let id = match.taskID else {
                errorMessage = I18n.t("error.deeplink.task_missing", "The task in the link is not part of the current project: %1$@", url.absoluteString)
                return
            }
            store.reveal(id)
            if match.matchCount > 1 {
                errorMessage = I18n.t("error.deeplink.duplicate_titles", "%1$ld tasks share that title; the first match was revealed", match.matchCount)
            }
        }
    }

    // MARK: - 文件操作

    private func openFile(_ url: URL) {
        store.openAsync(url: url)
    }

    private func saveDocument() {
        if store.projectURL != nil {
            store.save()
            if let message = store.alertMessage {
                errorMessage = message
                store.alertMessage = nil
            }
        } else {
            // 尚无保存路径：走 fileExporter 选择位置。
            store.beginExport()
            showSavePanel = true
        }
    }

    /// 另存为：始终打开位置选择面板，默认文件名由存储层按当前状态生成。
    private func saveDocumentAs() {
        store.beginExport()
        showSavePanel = true
    }

    private func finishExport(to url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        // 文件导出器已写入快照；再次 save 会重复写同一文件。
        store.rememberSaveURL(url)
        if let message = store.alertMessage {
            errorMessage = message
            store.alertMessage = nil
        }
    }
}

/// `fileExporter` 失败回调分类：用户取消是正常路径，不弹错误。
enum ExportFailure {
    /// 用户取消返回 nil；其他错误返回可展示的消息。
    static func message(for error: Error) -> String? {
        let nsError = error as NSError
        guard nsError.domain == NSCocoaErrorDomain,
              nsError.code == NSUserCancelledError else {
            return error.localizedDescription
        }
        return nil
    }
}
