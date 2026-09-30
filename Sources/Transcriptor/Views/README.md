# Views

One SwiftUI view per file. Every view reads `AppState` from the environment
and forwards user actions to it; none holds business logic.

| File | Shows | Forwards to `AppState` |
|---|---|---|
| `ContentView.swift` | `NavigationSplitView` with sidebar and detail; the toolbar (add audios, export, re-apply glossary, open folder, glossary, settings, cancel all, clear finished); the model-download, settings and glossary sheets; pending alerts; dropped files | every toolbar action, `addFiles` for drops, sheet toggles |
| `SidebarView.swift` | "En proceso" (unfinished and failed jobs) and "Transcripciones" (saved transcripts) | selection changes |
| `JobRowView.swift` | One job: file name, stage text, progress | nothing |
| `TranscriptDetailView.swift` | A transcript's title, metadata line and paragraphs, with a toolbar search field that highlights matches | nothing |
| `EmptyStateView.swift` | Placeholder when the library and the queue are empty | nothing |
| `ModelDownloadView.swift` | Download progress or error for the selected model | `prepareModel` (retry) |
| `SettingsSheet.swift` | Model choice (Preciso / Rápido) and library folder | `settings.modelChoice`, `changeLibraryFolder` |
| `GlossarySheet.swift` | Glossary text editor with parse feedback | `saveGlossary`, optionally `reapplyGlossary` to the open transcript |
