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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
