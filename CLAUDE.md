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

## Measured on this M5 Pro (spike 2026-09-24)
- large-v3-turbo (Preciso): ~8x realtime with decoder on GPU + 8 workers (~11 min per 90-min lecture), 3 GB on disk. small (Rápido): ~30x, 0.5 GB.
- First load after download compiles the model for the Neural Engine (~2 min, once).
