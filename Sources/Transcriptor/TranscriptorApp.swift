import SwiftUI

/// The app's entry point. Creates the single shared `AppState` and the single window, and
/// injects `AppState` into the environment for all views in `Transcriptor.Views`.
@main
struct TranscriptorApp: App {
    /// Handles Finder-opened files and the quit confirmation.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// The app's shared observable state, created once for the app's lifetime.
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup("Transcriptor") {
            ContentView()
                .environment(state)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear { appDelegate.state = state }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Agregar audios…") { state.openFilesPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
