import SwiftUI

@main
struct TranscriptorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
