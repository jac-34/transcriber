import AppKit

/// Receives files opened from Finder ("Abrir con Transcriptor") and forwards them to the queue.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var state: AppState?

    func application(_ application: NSApplication, open urls: [URL]) {
        state?.addFiles(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
