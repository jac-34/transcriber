import AppKit

/// Receives files opened from Finder ("Abrir con Transcriptor") and forwards them to the queue.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// URLs that arrived before AppState existed; flushed when `state` is set.
    private var pendingURLs: [URL] = []

    var state: AppState? {
        didSet {
            guard let state, !pendingURLs.isEmpty else { return }
            state.addFiles(pendingURLs)
            pendingURLs = []
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let state {
            state.addFiles(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    private var hasActiveJobs: Bool { state?.hasActiveJobs == true }

    /// Asks before quitting while a transcription is waiting or running.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard hasActiveJobs else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Hay una transcripción en curso."
        alert.informativeText = "Si sales ahora se perderá el progreso de ese archivo."
        alert.addButton(withTitle: "Salir de todos modos")
        alert.addButton(withTitle: "Seguir transcribiendo")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// Closing the window keeps the app running while jobs are active.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !hasActiveJobs }
}
