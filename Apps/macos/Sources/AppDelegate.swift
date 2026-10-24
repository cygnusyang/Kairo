import AppKit
import UniformTypeIdentifiers

/// 退出守卫（ADR-013）：有未保存修改时，⌘Q 前必须由用户选择保存、丢弃或取消。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: WorkspaceStore?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.hasUnsavedChanges else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = I18n.t("alert.unsaved_quit.title", "Unsaved changes")
        alert.informativeText = I18n.t("alert.unsaved_quit.message", "Quitting will discard unsaved changes to the current project.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: I18n.t("alert.unsaved_quit.save_and_quit", "Save and Quit"))
        alert.addButton(withTitle: I18n.t("alert.unsaved_quit.discard_and_quit", "Discard Changes and Quit"))
        alert.addButton(withTitle: I18n.t("action.cancel", "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveAndTerminate(store)
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    private func saveAndTerminate(_ store: WorkspaceStore) -> NSApplication.TerminateReply {
        if store.projectURL != nil {
            store.save()
            guard store.saveState != .failed else {
                showSaveError(store)
                return .terminateCancel
            }
            return .terminateNow
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.kairo]
        panel.nameFieldStringValue = store.suggestedSaveFilename
        guard panel.runModal() == .OK, let url = panel.url else { return .terminateCancel }
        store.save(to: url)
        guard store.saveState != .failed else {
            showSaveError(store)
            return .terminateCancel
        }
        return .terminateNow
    }

    private func showSaveError(_ store: WorkspaceStore) {
        let alert = NSAlert()
        alert.messageText = I18n.t("alert.save_failed.title", "Save Failed")
        alert.informativeText = store.alertMessage ?? I18n.t("alert.save_failed.message", "The project file could not be saved; quit cancelled.")
        alert.alertStyle = .critical
        alert.addButton(withTitle: I18n.t("action.ok", "OK"))
        alert.runModal()
        store.alertMessage = nil
    }
}
