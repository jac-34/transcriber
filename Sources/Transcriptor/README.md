# Transcriptor (app target)

The SwiftUI macOS app. Holds no transcription logic: it wires Core's
`JobQueue`, `Settings` and `Library` to the WhisperKit engine and renders
their state. All strings shown to the user are Spanish.

## File map

- `TranscriptorApp.swift`: `@main` entry point. Creates the single `AppState`, the main window and the app menu commands, and installs `AppDelegate`.
- `AppDelegate.swift`: receives files opened from Finder (buffering any that arrive before `AppState` exists) and asks for confirmation before quitting while a job is running.
- `AppState.swift`: `@Observable` root state. Owns settings, model manager, engine, library and job queue; exposes the actions views call (add files, export, re-apply glossary, change library folder, save glossary) and the alerts they present.
- `AppLog.swift`: file log at `~/Library/Logs/Transcriptor/transcriptor.log` with 5 MB rotation, plus console logging.
- `FilePanels.swift`: `NSOpenPanel` and `NSSavePanel` wrappers and `ExportFormat` (`.md`, `.txt`).
- `Views/`: one file per view, see `Views/README.md`.

## Runtime layout

`AppState` is injected through the SwiftUI environment. Views read it and
call its methods; they never touch the engine, the library or the queue
directly. Progress from the engine reaches the UI through `JobQueue`'s
observable `jobs`.

Assembly into a signed `.app` is done by `scripts/make-app.sh`
(`make app`, `make zip`); `scripts/Info.plist` carries the bundle metadata
and the version number.
