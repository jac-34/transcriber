# TranscriptorCore

All application logic, with no dependency on WhisperKit, AVFoundation,
SwiftUI or AppKit. Everything here is unit-tested in
`Tests/TranscriptorCoreTests` using `FakeEngine` in place of a real speech
engine.

## File map

Models
- `Segment.swift`: `Segment` (one engine output span with timestamps and confidence scores) and `Paragraph` (a timestamped block of final text).
- `Transcript.swift`: `Transcript`, the saved unit: metadata, raw segments, formatted paragraphs, Markdown and plain-text rendering. Schema version lives here.
- `ModelChoice.swift`: `ModelChoice` (`preciso`, `rapido`): WhisperKit model names, Spanish labels, worker counts.
- `TranscriptionError.swift`: `TranscriptionError`, every failure shown to the user, with Spanish messages.

Engine contract
- `TranscriptionEngine.swift`: the `TranscriptionEngine` protocol (`prepare`, `transcribe`, `tokenCount`, `cancel`) and `TranscriptionOutput`. Implemented by `TranscriptorEngine.WhisperKitEngine` and by test fakes.
- `CoverageGaps.swift`: arithmetic over decoded time ranges: uncovered gaps, coverage fraction, the minimum coverage a transcript must reach.

Text processing (in pipeline order)
- `HallucinationFilter.swift`: drops empty, duplicated, low-confidence and known hallucinated segments.
- `Glossary.swift`: parses the user's glossary file into prompt terms and `wrong => right` corrections; builds the token-budgeted decoding prompt; applies corrections.
- `TranscriptFormatter.swift`: groups segments into paragraphs by pause length and word count.
- `TranscriptPipeline.swift`: runs filter, corrections and formatting to build a `Transcript`, and re-applies a glossary to an existing one.
- `Timestamp.swift`: `[hh:mm:ss]` and duration formatting.

State and storage
- `JobQueue.swift`: `Job` and `JobQueue`, the sequential processor that drives an engine through prepare, transcribe, build and save, reporting progress and failures through callbacks.
- `Library.swift`: the transcripts folder: saves `.md` plus `.transcriptor.json` sidecars, lists saved transcripts, reads and writes the glossary file.
- `Settings.swift`: user preferences (model choice, library folder) backed by `UserDefaults`.
- `SupportedAudio.swift`: accepted file extensions and the Spanish rejection message for anything else.
- `AsyncLock.swift`: FIFO async mutual exclusion used by engines to serialize `prepare` and `transcribe`.
