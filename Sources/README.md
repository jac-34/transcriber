# Sources

Three SwiftPM targets. Dependencies point downward only.

```
Transcriptor          SwiftUI app: windows, sheets, file panels, logging
    │
    ├── TranscriptorEngine   WhisperKit adapter behind Core's TranscriptionEngine protocol
    │       │
    └───────┴── TranscriptorCore   models, text processing, job queue, library (Foundation only)
```

| Folder | Imports allowed | Tests |
|---|---|---|
| `TranscriptorCore/` | Foundation, Observation | `Tests/TranscriptorCoreTests` (fast, no model) |
| `TranscriptorEngine/` | Core, WhisperKit, AVFoundation, os | `Tests/TranscriptorEngineTests` (fast + env-gated integration) |
| `Transcriptor/` | Core, Engine, SwiftUI, AppKit | none; checked by the headless launch in `CLAUDE.md` |

Each folder has its own `README.md` with a file map. Build and test commands
are in `CLAUDE.md`; behavior and design decisions are in
`docs/superpowers/specs/2026-09-24-transcriber-design.md`.

Conventions: identifiers and comments in English, user-visible strings in
Spanish, `///` documentation on every public and internal declaration.
