# Transcriptor

Offline macOS app that transcribes medical lectures (Chilean Spanish) with WhisperKit. Single non-technical end user.
Spec: `docs/superpowers/specs/2026-09-24-transcriber-design.md` (binding). Plan: `docs/superpowers/plans/2026-09-24-transcriber.md`.

## Build & test (no Xcode on this machine)
- Command Line Tools only (Swift 6.3). Never add an `.xcodeproj`; SwiftPM + scripts build everything.
- `make test` - fast suite; ALWAYS use this, never bare `swift test` (Makefile adds the CLT Testing.framework `-F`/`-rpath` flags).
- `make test-integration` - real WhisperKit run; downloads the ~0.5 GB small model into `~/Library/Application Support/Transcriptor` on first run, needs network then. Suite is `.serialized` on purpose (concurrent downloads corrupt the cache).
- `swift build -c release` - first build compiles WhisperKit (~2-3 min); use a 10-min timeout.
- `make app` / `make zip` - assemble and ad-hoc sign `dist/Transcriptor.app` via `scripts/make-app.sh`; `dist/` is gitignored, never commit it.
- Headless launch check: `.build/release/Transcriptor & PID=$!; sleep 6; kill -0 $PID && echo RUNNING; kill $PID` then `tail ~/Library/Logs/Transcriptor/transcriptor.log`.

## Layering (enforced by review)
- `TranscriptorCore` imports Foundation/Observation ONLY - no WhisperKit, AVFoundation, SwiftUI, AppKit. All logic + unit tests live here.
- `TranscriptorEngine` wraps WhisperKit behind the `TranscriptionEngine` protocol; `Transcriptor` is the SwiftUI app.
- User-visible strings Spanish; identifiers and comments English.

## Swift 6 / WhisperKit gotchas
- WhisperKit 1.1.0 is pinned `exact`. Its `WhisperKit` class is not Sendable: `WhisperKitEngine` is `@unchecked Sendable`, holds it in `OSAllocatedUnfairLock(uncheckedState:)` and uses `withLockUnchecked`.
- `prepare` and `transcribe` are serialized through Core's `AsyncLock`; `cancel()` stays outside it. Do not call `unloadModels()` while a transcription may be running.
- Pass `tokenizerFolder: downloadBase` in `WhisperKitConfig` so the cached tokenizer is found offline.
- Prompt tokens: `tokenizer.encode(text: " " + prompt).filter { $0 < specialTokens.specialTokenBegin }` with `usePrefillPrompt = true`.
- Glossary corrections use `(?<![\p{L}\p{N}])…(?![\p{L}\p{N}])` lookarounds, not `\b` (fails on `v.o.`).
- `@Observable` classes are `@MainActor`; progress callbacks hop with `Task { @MainActor in … }`.
- Memory: never run the text decoder on `.cpuAndGPU` - CoreML's GPU path leaks ~0.35 MB per decoder step on macOS 26 (93-min lecture hit 31 GB and killed WindowServer). Decoders stay on `.cpuAndNeuralEngine`; the engine stops decoding and fails the job with a Spanish error when the process footprint passes half of physical RAM; remaining VAD chunks still get one cheap pass before the failure surfaces (same path as cancel). Measure with `footprint -p PID`, not `ps` RSS (leaked pages get compressed, RSS stays flat). Test any engine change on a full-length lecture under a cap-and-kill monitor.
- Minimum hardware: Apple Silicon with 16 GB RAM (fixed footprint ~2.5 GB; 8 GB Macs are unsupported).

## Measured on this M5 Pro (spike 2026-09-24)
- large-v3-turbo (Preciso): ~3.5x realtime, decoder on Neural Engine + glossary prompt (26.5 min for the 93-min lecture headless with 16 workers, footprint ~1.8 GB, peak 2.5 GB), 3 GB on disk. small (Rápido): ~9x realtime in-app on the Neural Engine (~10 min per 90-min lecture); the 30x spike figure was CLI-only. 0.5 GB on disk.
- Neural Engine worker limit: inside the GUI app, turbo with 6+ `concurrentWorkerCount` makes CoreML time out ANE predictions and WhisperKit silently drops those VAD chunks (half a lecture lost at 16). Preciso uses 2 (as fast as 4). The engine re-decodes coverage gaps (`CoverageGaps`) and fails the job below 90% coverage; measure worker changes in the app (`open -a dist/Transcriptor.app <file>`), the CLI and headless runs do not reproduce the timeouts.
- `firstTokenLogProbThreshold` must stay `nil`: WhisperKit's default -1.5 makes VAD chunks fall back to high temperatures and come back empty (10-25% of speech lost, 2x decode work).
- First load after download compiles the model for the Neural Engine (~2 min, once).
