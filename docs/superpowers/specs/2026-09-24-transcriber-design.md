# Transcriptor: offline medical-lecture transcriber for macOS

Date: 2026-09-24
Status: draft for review

## 1. Purpose

A macOS desktop app for one non-technical user (a medical student) to turn
recorded lectures in Chilean Spanish into clean, readable, timestamped text
she can study from and export. Everything runs on-device on her Apple Silicon
M5 Mac. After a one-time model download the app needs no internet, no account,
and costs nothing per lecture.

Working name: **Transcriptor**. All user-facing text is in Spanish.

## 2. Scope

### In scope (v1)

- Input: audio files she already has, added by drag-and-drop or an open
  dialog. Formats decodable by AVFoundation: m4a, mp3, wav, aac, aiff, caf,
  flac, and the audio track of mp4/mov/m4v.
- Batch queue: many files added at once, processed one after another.
- Output: punctuated Spanish text split into paragraphs, each paragraph
  prefixed with a `[hh:mm:ss]` timestamp.
- Glossary she edits inside the app: terms that bias the speech model, and
  explicit corrections applied after transcription.
- Re-apply the glossary to an existing transcript without re-transcribing.
- Library: every finished transcript is saved automatically and listed in the
  app on later launches.
- Export as `.txt` or `.md` via a save dialog.
- Two model choices: **Preciso** (Whisper large-v3-turbo, default) and
  **Rápido** (Whisper small).
- Distributed as a zipped `.app`, ad-hoc signed.

### Out of scope (v1)

- Live recording from the microphone.
- Speaker labels.
- `.opus` / `.ogg` (Android WhatsApp voice notes). AVFoundation cannot decode
  them; the app shows a clear message naming the format.
- Any cloud service: no LLM cleanup, no summaries, no sync.
- Windows or Intel Mac builds.
- Notarization / Developer ID signing (needs a paid Apple account).
- Editing the transcript inside the app. She edits the exported file.

## 3. Constraints and decisions

- **No Xcode on the development machine.** Build with Swift Package Manager
  under Command Line Tools (Swift 6.3, macOS 26 SDK). The `.app` bundle is
  assembled by a script. Verified in a spike on 2026-09-24: WhisperKit and its
  CLI compile with `swift build -c release` under CLT in about 2 minutes, and
  `swift test` with Swift Testing works when given extra framework/rpath flags
  (wrapped in the Makefile).
- **Speech engine: WhisperKit** (argmaxinc/WhisperKit, Swift package, CoreML
  on the Neural Engine and GPU). Chosen over whisper.cpp and Apple's
  SpeechTranscriber because it is native Swift, fastest on Apple Silicon, and
  accepts a vocabulary prompt. Models download from the `argmaxinc/whisperkit-coreml`
  Hugging Face repo.
- **Model settings**, measured on this M5 Pro (Preciso: full 93-minute
  lecture with the glossary prompt, 2026-09-29; Rápido: spike, 5-minute
  Spanish clip, VAD chunking):

  | Setting | Model | Disk | Speed vs realtime | 90-min lecture |
  |---|---|---|---|---|
  | Preciso (default) | `openai_whisper-large-v3_turbo` | ~3.0 GB | ~3.5x | ~26 min |
  | Rápido | `openai_whisper-small` | ~0.5 GB | ~30x | ~3 min |

  Both models run the audio encoder and the text decoder on
  `cpuAndNeuralEngine`, `chunkingStrategy = .vad`,
  `firstTokenLogProbThreshold = nil`; Preciso uses `concurrentWorkerCount = 16`
  (24 was no faster). The spike's faster Preciso setting (decoder on
  `cpuAndGPU`, 8.2x on a 5-minute clip) is ruled out: CoreML's GPU path leaks
  ~0.35 MB per decoder step on macOS 26, and a 93-minute lecture reached
  31 GB and took down the GUI session. On the Neural Engine the footprint stays
  flat at ~1.8 GB (peak 2.5 GB during audio loading). First load of a model
  after download spends ~2 minutes compiling for the Neural Engine, once per
  model. The engine stops decoding and fails the job with a Spanish error when
  the process footprint passes half of physical RAM; remaining VAD chunks still
  get one cheap pass before the failure surfaces (same path as cancel).
- **Language forced to `es`.** No language detection. Chilean Spanish needs no
  separate model; the glossary handles vocabulary.
- **Minimum macOS 14.** Swift 6 language mode, strict concurrency. Minimum hardware: Apple Silicon Mac with 16 GB RAM.

## 4. Architecture

One Swift package, three targets plus tests:

```
Package.swift
Sources/
  TranscriptorCore/      # pure logic, no WhisperKit, fully unit-tested
    Glossary.swift
    TranscriptFormatter.swift
    Transcript.swift         # data model + JSON sidecar + Markdown/txt rendering
    JobQueue.swift
    TranscriptionEngine.swift   # protocol only
    Library.swift
    Settings.swift
    HallucinationFilter.swift
  TranscriptorEngine/    # WhisperKit adapter, conforms to TranscriptionEngine
    WhisperKitEngine.swift
    ModelManager.swift       # download, load, switch models, progress
  Transcriptor/          # SwiftUI app (@main), views, AppKit bits (panels, drag-drop)
Tests/
  TranscriptorCoreTests/        # fast, run on every change
  TranscriptorEngineTests/      # slow, real model on a 30 s fixture; opt-in
scripts/
  make-app.sh            # assembles Transcriptor.app, icon, Info.plist, codesign
  make-icon.sh           # PNG -> .icns via sips + iconutil
Makefile                 # build / test / test-integration / app / run / zip
```

Dependency direction: `Transcriptor` → `TranscriptorEngine` → `TranscriptorCore`.
`TranscriptorCore` depends on Foundation only, so its tests run in seconds and
never touch a model.

### 4.1 Data flow

```
files dropped
  → JobQueue (one job at a time)
    → AudioLoader (WhisperKit's AudioProcessor: file → 16 kHz mono Float32)
    → TranscriptionEngine.transcribe(samples, options, progress)
        options: language "es", promptTokens from Glossary, thresholds, VAD chunking
    → [Segment]  (text, start, end, avgLogprob, noSpeechProb, compressionRatio)
    → HallucinationFilter
    → Glossary.applyCorrections
    → TranscriptFormatter → [Paragraph]
    → Transcript (metadata + segments + paragraphs)
    → Library.save → <name>.md + <name>.transcriptor.json
  → UI shows the transcript
```

"Re-aplicar glosario" starts at `Glossary.applyCorrections` using the raw
segments stored in the JSON sidecar, then re-formats and re-saves.

### 4.2 Units

**Glossary** (`TranscriptorCore`)
- Source of truth: a UTF-8 text file `glosario.txt` in the library folder.
  She edits it through a sheet in the app; the file is also human-editable.
- Line grammar, one entry per line, `#` starts a comment, blank lines ignored:
  - `hipokalemia` — a term. Terms bias decoding.
  - `hipocalemia => hipokalemia` — a correction. Applied after transcription,
    case-insensitive, whole-word, preserving the capitalization of the first
    letter if the original was capitalized. The right-hand side is also added
    to the terms list.
- `promptText(maxTokens:) -> (text: String, truncated: Bool)`: builds
  `"Clase de medicina. Términos: t1, t2, ..."` taking terms in file order until
  the token budget is hit. Budget is 200 tokens (Whisper's prompt window is
  224). Tokenization is injected as a closure so Core stays free of WhisperKit;
  the engine supplies WhisperKit's tokenizer. The UI shows a warning when
  `truncated` is true.
- `applyCorrections(to text: String) -> String`.
- Parse errors (a line with `=>` but an empty side) are reported by line
  number and shown in the glossary sheet; valid lines still work.

**TranscriptFormatter** (`TranscriptorCore`)
- Input: `[Segment]`. Output: `[Paragraph]` where each has `start: TimeInterval`
  and `text: String`.
- Rules, in order: start a new paragraph when the gap between consecutive
  segments exceeds 1.5 s; or when the current paragraph exceeds 120 words and
  the segment ends in `.`, `?` or `!`; or unconditionally when it exceeds 220
  words. Segment texts are trimmed and joined with single spaces.
- Timestamp rendering `[hh:mm:ss]`, hours always present so columns align.

**HallucinationFilter** (`TranscriptorCore`)
- Drops a segment when: its text equals the previous segment's text
  (normalized); or it matches a known Whisper Spanish hallucination list
  ("Subtítulos realizados por la comunidad de Amara.org", "Gracias por ver",
  "Suscríbete", and similar, kept in one array); or `noSpeechProb > 0.6` and
  `avgLogprob < -1.0` together.
- The engine also passes WhisperKit thresholds: `compressionRatioThreshold 2.4`,
  `logProbThreshold -1.0`, `noSpeechThreshold 0.6`.

**Transcript** (`TranscriptorCore`)
- Fields: `id`, `title` (audio file name without extension), `sourcePath`,
  `audioDuration`, `createdAt`, `modelName`, `glossaryPromptUsed`,
  `segments: [Segment]` (raw, pre-correction), `paragraphs: [Paragraph]`.
- `renderMarkdown()`: `# <title>`, a metadata line (date, duration, model),
  then one paragraph per block as `[hh:mm:ss] text`.
- `renderPlainText()`: same body without the header lines.
- JSON sidecar is the Codable encoding of the whole struct, versioned with a
  `schemaVersion: 1` field.

**JobQueue** (`TranscriptorCore`, `@MainActor @Observable`)
- `Job` states: `waiting`, `loadingModel`, `decodingAudio`,
  `transcribing(progress: Double)`, `applyingGlossary`, `done(Transcript)`,
  `failed(message: String)`.
- Processes strictly one job at a time. A failure marks that job and continues
  with the next. Cancel removes waiting jobs and asks the engine to stop the
  current one (WhisperKit's callback returns `false`).
- Takes the engine as a protocol so tests use a fake.

**TranscriptionEngine** (protocol in Core, implementation in Engine)
```swift
protocol TranscriptionEngine: Sendable {
    func prepare(model: ModelChoice, progress: @Sendable (Double) -> Void) async throws
    func transcribe(fileURL: URL, prompt: String?, progress: @Sendable (Double) -> Void) async throws -> [Segment]
    func tokenCount(_ text: String) async throws -> Int
    func cancel()
}
```
- `WhisperKitEngine` owns one `WhisperKit` instance, reloads it only when the
  model choice changes, maps `TranscriptionSegment` → `Segment`, and derives
  progress from `TranscriptionProgress` (windows processed over total audio).

**ModelManager** (`TranscriptorEngine`)
- Model folder: `~/Library/Application Support/Transcriptor/models`.
- `isDownloaded(model)`, `download(model, progress)` wrapping
  `WhisperKit.download(variant:downloadBase:progressCallback:)`.
- Errors: no network, disk full, interrupted download. Each has a Spanish
  message and a retry path. A partial download is resumed or restarted by
  WhisperKit's Hugging Face client.

**Library** (`TranscriptorCore`)
- Folder: `~/Documents/Transcripciones/` (created on first run; the user can
  pick another folder in settings, stored in `UserDefaults`).
- `save(transcript)` writes `<title>.md` and `<title>.transcriptor.json`,
  disambiguating with ` (2)`, ` (3)` on collision.
- `list()` reads all `*.transcriptor.json`, newest first. A JSON that fails
  to decode is skipped and logged, never fatal.
- Also holds `glosario.txt`.

**Settings** (`TranscriptorCore`)
- `modelChoice: ModelChoice` (`.preciso` default, `.rapido`), `libraryFolder`.
- Backed by `UserDefaults`.

### 4.3 UI (`Transcriptor` target, SwiftUI)

- `NavigationSplitView`. Sidebar sections: **En proceso** (jobs with a state
  label and progress bar) and **Transcripciones** (library, newest first, with
  date and duration). Detail pane: transcript title, metadata line, and the
  paragraphs as selectable text in a scroll view with a search field that
  highlights matches.
- Toolbar: **Agregar audios** (NSOpenPanel, multiple selection, allowed
  content types = the supported list), **Exportar** (NSSavePanel, `.md` or
  `.txt`), **Abrir carpeta** (reveals the library folder in Finder),
  **Glosario** (sheet), **Re-aplicar glosario** (on the selected transcript),
  settings gear (sheet: model picker with size and speed hints, library folder).
- Whole window accepts dropped files. Unsupported files are rejected with a
  toast naming the extension and listing the supported ones.
- First launch, or when the selected model is missing: a modal
  **Descargando modelo** view with progress, size, a note that this happens
  once, and **Reintentar** on failure. The queue waits until the model is
  ready.
- Empty states in Spanish for no transcripts and no selection.

### 4.4 Error handling

- Every failure is surfaced per item, never as an app crash: unsupported
  format, unreadable file, decode failure, model load failure, out of memory
  (caught as a thrown error where possible), cancellation.
- Messages are plain Spanish, one sentence, no stack traces. Technical detail
  goes to the log.
- Logging: `os.Logger` plus a rolling file at
  `~/Library/Logs/Transcriptor/transcriptor.log` (max 5 MB, one rotation) so
  she can send the file when something goes wrong.

## 5. Testing

- **Unit (fast, `make test`)**, Swift Testing, `TranscriptorCoreTests`:
  - Glossary: parsing (terms, corrections, comments, blanks, malformed lines),
    prompt building and truncation with a fake tokenizer, corrections
    (case-insensitive, whole-word, capitalization preserved, no partial-word
    replacement such as `hipokalemia` inside `pseudohipokalemia`).
  - TranscriptFormatter: gap split, word-count split at sentence end, hard
    cap, timestamp formatting including hours.
  - HallucinationFilter: duplicate removal, phrase list, probability rule.
  - Transcript: Markdown and plain-text rendering, JSON round-trip, schema
    version present.
  - JobQueue: state transitions with a fake engine, failure continues the
    queue, cancel behavior.
  - Library: save with collision suffixes, list ordering, corrupt sidecar
    skipped.
- **Integration (slow, `make test-integration`)**, `TranscriptorEngineTests`,
  gated on an environment variable so it never runs by accident: runs the
  30-second Spanish fixture generated with macOS `say` through the Rápido
  model and asserts a few expected words appear, and that a glossary prompt
  changes `hipocalemia` to `hipokalemia`.
- **Acceptance**: one of her real lectures through Preciso, judged by her for
  readability and medical terms. Timing recorded in the README.

## 6. Build and distribution

- `make build`: `swift build -c release`.
- `make test`: `swift test` with the CLT Testing framework flags:
  `-Xswiftc -F<CLT>/Library/Developer/Frameworks -Xlinker -F<same>
  -Xlinker -rpath -Xlinker <same> -Xlinker -rpath -Xlinker <CLT>/Library/Developer/usr/lib`.
- `make app`: `scripts/make-app.sh` creates `dist/Transcriptor.app` with
  `Contents/MacOS/Transcriptor`, `Contents/Resources/AppIcon.icns`,
  `Contents/Info.plist` (bundle id `com.jac.transcriptor`,
  `LSMinimumSystemVersion 14.0`, `NSHighResolutionCapable`,
  `CFBundleDocumentTypes` for the supported audio types so files can be
  opened with the app), then `codesign --force --deep --sign -`. The script
  checks with `otool -L` that WhisperKit is statically linked and no
  non-system dylibs are referenced.
- `make zip`: `dist/Transcriptor-<version>.zip` using `ditto` to keep
  resource forks and signatures.
- `make run`: builds and opens the app for manual testing.
- Install on her Mac: unzip, drag to Applications, right-click → Abrir the
  first time (on macOS 15+ also System Settings → Privacy & Security → Open
  Anyway). A one-page `README.md` in Spanish documents this and the glossary
  format.

## 7. Success criteria

- `make app` produces a working `.app` on a machine with only Command Line
  Tools.
- A 90-minute lecture transcribes in ≤ 12 minutes on Preciso and ≤ 4 minutes
  on Rápido on an M5.
- Glossary terms present in the prompt appear spelled as listed; corrections
  are applied everywhere they match as whole words.
- Paragraphs are readable without editing: no wall of text, no repeated
  hallucinated lines, timestamps line up.
- She can add files, wait, read, export, and re-apply the glossary without
  touching a terminal.

## 8. Risks

- **Real lecture audio is worse than the spike clip.** Lecture halls have
  echo, distance, and students talking. Mitigation: Preciso as default, VAD
  chunking, thresholds, hallucination filter, and acceptance on a real lecture
  before calling v1 done.
- **Prompt budget.** A long glossary is truncated at 200 tokens. Mitigation:
  the UI warns, and corrections have no limit. A later version could pick
  prompt terms per lecture.
- **Gatekeeper friction** each time a new build is sent. Mitigation: document
  the right-click step; keep releases rare.
- **WhisperKit API churn.** Pin the package to a tagged release in
  `Package.swift`.

## 9. Spike record (2026-09-24)

Throwaway work in the session scratchpad, not committed:
- WhisperKit `main` at commit 3111602 built with `swift build -c release
  --product whisperkit-cli` under CLT in 118 s.
- 37 s synthetic Spanish medical clip (`say -v Paulina`): small and
  large-v3-turbo both transcribed correctly except medical terms; a glossary
  prompt fixed all of them.
- 5-minute clip, VAD chunking: turbo defaults 5.2x realtime; turbo with
  decoder on GPU and 8 workers 8.2x; encoder on GPU did not help (7.1x); small
  30.5x. Turbo on disk 3.0 GB, small 0.48 GB. First model load after download
  ~111 s (CoreML compilation), later loads ~1 s.
