# TranscriptorEngine

Adapts WhisperKit 1.1.0 to Core's `TranscriptionEngine` protocol. The app is
the only client. Nothing here is user-facing except the Spanish error details
in `UserFacingDetail.swift`.

## File map

- `WhisperKitEngine.swift`: `WhisperKitEngine`. Loads and unloads models, transcribes one file at a time, biases decoding with the glossary prompt, re-decodes audio ranges WhisperKit dropped, enforces the memory footprint limit, honors `cancel()`. `prepare` and `transcribe` are serialized through Core's `AsyncLock`.
- `ModelManager.swift`: `ModelManager`. Locates model folders under `~/Library/Application Support/Transcriptor`, reports whether a model is fully downloaded, downloads it from Hugging Face with progress.
- `UserFacingDetail.swift`: maps `URLError`, `CancellationError` and `WhisperError` to the short Spanish detail shown inside error messages.
- `EngineLog.swift`: `os.Logger` for the engine subsystem.

## Contracts callers rely on

- Compute units: audio encoder and text decoder both on the Neural Engine. See `CLAUDE.md` for the operational rules behind this and the worker limits.
- A transcription fails with a Spanish error when the process footprint passes half of physical RAM, or when the transcript covers less than `CoverageGaps.minimumCoverage` of the audio after gap recovery.
- Progress callbacks arrive on arbitrary threads, at most every 0.5% of progress.

## Tests

`Tests/TranscriptorEngineTests`: `ModelManagerTests`, `MemoryGuardTests` and
`UserFacingDetailTests` run with `make test`.
`WhisperKitEngineIntegrationTests` runs only with `make test-integration`
(needs the small model, downloads it on first run, suite is serialized).
