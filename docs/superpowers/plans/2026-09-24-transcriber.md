# Transcriptor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fully offline macOS app that turns recorded medical lectures in Chilean Spanish into clean, timestamped, exportable text, using WhisperKit and a user-editable glossary.

**Architecture:** One Swift package with three targets. `TranscriptorCore` holds all pure logic (glossary, paragraph formatting, hallucination filter, transcript model, job queue, library on disk) and depends on Foundation only. `TranscriptorEngine` adapts WhisperKit behind a `TranscriptionEngine` protocol and manages model downloads. `Transcriptor` is the SwiftUI app. The `.app` bundle is assembled by a shell script because the build machine has no Xcode.

**Tech Stack:** Swift 6.3 (Command Line Tools only), Swift Package Manager, SwiftUI + AppKit panels, AVFoundation, WhisperKit 1.1.0 (CoreML), Swift Testing, zsh scripts, `codesign`, `iconutil`.

**Spec:** `docs/superpowers/specs/2026-09-24-transcriber-design.md`

## Global Constraints

- No Xcode. Everything builds with `swift build` / `swift test` under `/Library/Developer/CommandLineTools`. Never add an `.xcodeproj`.
- `swift-tools-version: 6.0`, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v14)]`.
- WhisperKit pinned: `.package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.0")`, product `WhisperKit`.
- `TranscriptorCore` imports Foundation (and Observation) only. Never WhisperKit, AVFoundation, SwiftUI or AppKit.
- All user-visible strings are Spanish. Code identifiers and comments are English.
- Model variants: Preciso = `openai_whisper-large-v3_turbo`, Rápido = `openai_whisper-small`. Repo `argmaxinc/whisperkit-coreml`.
- Decoding: language `es`, no language detection, `chunkingStrategy = .vad`, `compressionRatioThreshold 2.4`, `logProbThreshold -1.0`, `noSpeechThreshold 0.6`. Preciso: audio encoder `.cpuAndNeuralEngine`, text decoder `.cpuAndGPU`, `concurrentWorkerCount 8`.
- Prompt budget 200 tokens. Paragraph rules: gap > 1.5 s, soft limit 120 words at sentence end, hard limit 220 words.
- Model folder: `~/Library/Application Support/Transcriptor`. Library folder default: `~/Documents/Transcripciones`. Log: `~/Library/Logs/Transcriptor/transcriptor.log`.
- Bundle id `com.jac.transcriptor`, `LSMinimumSystemVersion 14.0`.
- Commit after every task with a Conventional Commits message. Run `make test` before every commit from Task 1 onward.

## Review Focus

Inputs the spec implies but did not spell out. Each has a pinned test in the task named.

1. **Audio with no detectable speech** (silence, music) yields zero segments. The transcript must still save and render a line saying no speech was detected, not an empty page or a crash. Pinned in Task 3 (formatter on empty input) and Task 2 (empty render).
2. **Lecture titles that are not valid file names** (`Clase 3: Riñón / Túbulo`) must save without error; `/` and `:` are replaced by `-`. Pinned in Task 7.
3. **Glossary files edited on other machines**: Windows `\r\n` line endings, trailing spaces, duplicate terms in different casing, and correction sources containing regex metacharacters (`v.o. => vía oral`). Pinned in Task 5.
4. **Segments returned out of order** (VAD windows finish concurrently) and timestamps past one hour. The formatter must sort first and render `[01:02:03]`. Pinned in Task 3.
5. **A queued file that disappears or is unreadable** (moved, deleted, on an ejected drive) must fail only that job with a Spanish message, and the queue must continue. Pinned in Task 8.

---

### Task 1: Package scaffold, Makefile, first passing test

**Files:**
- Create: `Package.swift`
- Create: `Makefile`
- Create: `Sources/TranscriptorCore/SupportedAudio.swift`
- Create: `Sources/TranscriptorEngine/Placeholder.swift` (removed in Task 9)
- Create: `Sources/Transcriptor/main.swift` (replaced in Task 10)
- Create: `Tests/TranscriptorCoreTests/SupportedAudioTests.swift`
- Create: `Tests/TranscriptorEngineTests/EngineSmokeTests.swift`

**Interfaces:**
- Produces: `SupportedAudio.extensions: Set<String>`, `SupportedAudio.isSupported(_ url: URL) -> Bool`, `SupportedAudio.rejectionMessage(for url: URL) -> String`.
- Produces: `make build`, `make test`, `make test-integration` targets used by every later task.

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Transcriptor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Transcriptor", targets: ["Transcriptor"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "TranscriptorCore"),
        .target(name: "TranscriptorEngine", dependencies: ["TranscriptorCore"]),
        .executableTarget(
            name: "Transcriptor",
            dependencies: ["TranscriptorCore", "TranscriptorEngine"]
        ),
        .testTarget(name: "TranscriptorCoreTests", dependencies: ["TranscriptorCore"]),
        .testTarget(name: "TranscriptorEngineTests", dependencies: ["TranscriptorEngine", "TranscriptorCore"]),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 2: Create the Makefile**

Recipe lines must start with a real tab character.

```make
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := -Xswiftc -F$(CLT_DEV)/Frameworks \
              -Xlinker -F$(CLT_DEV)/Frameworks \
              -Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
              -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib
VERSION ?= 0.1.0

.PHONY: build test test-integration app run zip clean

build:
	swift build -c release

test:
	swift test $(TEST_FLAGS) --skip TranscriptorEngineTests

test-integration:
	TRANSCRIPTOR_INTEGRATION=1 swift test $(TEST_FLAGS) --filter TranscriptorEngineTests

app: build
	VERSION=$(VERSION) scripts/make-app.sh

run: app
	open dist/Transcriptor.app

zip: app
	ditto -c -k --keepParent dist/Transcriptor.app dist/Transcriptor-$(VERSION).zip

clean:
	rm -rf .build dist
```

- [ ] **Step 3: Create placeholder sources so all targets compile**

`Sources/TranscriptorEngine/Placeholder.swift`:
```swift
// Replaced by the WhisperKit engine in Task 9.
public enum EnginePlaceholder {}
```

`Sources/Transcriptor/main.swift`:
```swift
// Replaced by the SwiftUI app in Task 10.
print("Transcriptor")
```

`Tests/TranscriptorEngineTests/EngineSmokeTests.swift`:
```swift
import Testing
@testable import TranscriptorEngine

@Test func enginePackageCompiles() {
    _ = EnginePlaceholder.self
}
```

- [ ] **Step 4: Write the failing SupportedAudio test**

`Tests/TranscriptorCoreTests/SupportedAudioTests.swift`:
```swift
import Foundation
import Testing
@testable import TranscriptorCore

@Suite struct SupportedAudioTests {
    @Test func acceptsCommonAudioAndVideoExtensions() {
        for ext in ["m4a", "mp3", "wav", "aac", "aiff", "aif", "caf", "flac", "mp4", "mov", "m4v", "M4A"] {
            #expect(SupportedAudio.isSupported(URL(fileURLWithPath: "/tmp/clase.\(ext)")), "\(ext) should be supported")
        }
    }

    @Test func rejectsUnknownExtensions() {
        for ext in ["opus", "ogg", "pdf", "txt", ""] {
            #expect(!SupportedAudio.isSupported(URL(fileURLWithPath: "/tmp/clase.\(ext)")), "\(ext) should be rejected")
        }
    }

    @Test func opusMessageMentionsWhatsApp() {
        let message = SupportedAudio.rejectionMessage(for: URL(fileURLWithPath: "/tmp/nota.opus"))
        #expect(message.contains("WhatsApp"))
        #expect(message.contains(".opus"))
    }

    @Test func genericMessageListsAcceptedFormats() {
        let message = SupportedAudio.rejectionMessage(for: URL(fileURLWithPath: "/tmp/apuntes.pdf"))
        #expect(message.contains(".pdf"))
        #expect(message.contains("m4a"))
        #expect(message.contains("mp3"))
    }
}
```

- [ ] **Step 5: Run tests to verify failure**

Run: `make test`
Expected: compile error, `cannot find 'SupportedAudio' in scope`.

- [ ] **Step 6: Implement SupportedAudio**

`Sources/TranscriptorCore/SupportedAudio.swift`:
```swift
import Foundation

/// File types the app accepts. AVFoundation decodes all of these natively.
public enum SupportedAudio {
    public static let extensions: Set<String> = [
        "m4a", "mp3", "wav", "aac", "aiff", "aif", "caf", "flac", "mp4", "mov", "m4v",
    ]

    /// Extensions we know people will try and that AVFoundation cannot decode.
    private static let opusLike: Set<String> = ["opus", "ogg", "oga"]

    public static func isSupported(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    public static func rejectionMessage(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        if opusLike.contains(ext) {
            return "\"\(name)\": los audios .\(ext) (notas de voz de WhatsApp en Android) no son compatibles. Conviértelo a .m4a o .mp3 primero."
        }
        let shown = ext.isEmpty ? "(sin extensión)" : ".\(ext)"
        let accepted = "m4a, mp3, wav, aac, aiff, caf, flac, mp4, mov"
        return "\"\(name)\": el formato \(shown) no es compatible. Formatos aceptados: \(accepted)."
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `make test`
Expected: `Test run with 4 tests ... passed`. Also run `make build` and expect `Build complete`.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Makefile Sources Tests
git commit -m "build: swift package scaffold with Makefile and supported-audio check"
```

---

### Task 2: Core data model — Segment, Paragraph, Timestamp, Transcript

**Files:**
- Create: `Sources/TranscriptorCore/Segment.swift`
- Create: `Sources/TranscriptorCore/Timestamp.swift`
- Create: `Sources/TranscriptorCore/Transcript.swift`
- Create: `Sources/TranscriptorCore/ModelChoice.swift`
- Test: `Tests/TranscriptorCoreTests/TimestampTests.swift`
- Test: `Tests/TranscriptorCoreTests/TranscriptTests.swift`

**Interfaces:**
- Produces:
  - `struct Segment: Codable, Hashable, Sendable { start: TimeInterval; end: TimeInterval; text: String; avgLogprob: Float; noSpeechProb: Float; compressionRatio: Float }`
  - `struct Paragraph: Codable, Hashable, Sendable { start: TimeInterval; text: String }`
  - `enum Timestamp { static func bracket(_ s: TimeInterval) -> String /* "[hh:mm:ss]" */; static func duration(_ s: TimeInterval) -> String /* "h:mm:ss" */ }`
  - `enum ModelChoice: String, CaseIterable, Codable, Sendable, Identifiable { case preciso, rapido; whisperVariant; displayName; detailText; concurrentWorkers }`
  - `struct Transcript: Codable, Hashable, Sendable, Identifiable { schemaVersion, id, title, fileStem: String?, sourcePath, audioDuration, createdAt, modelChoice, glossaryPromptUsed: String?, segments, paragraphs; renderMarkdown(); renderPlainText() }`

- [ ] **Step 1: Write failing Timestamp tests**

`Tests/TranscriptorCoreTests/TimestampTests.swift`:
```swift
import Testing
@testable import TranscriptorCore

@Suite struct TimestampTests {
    @Test func bracketAlwaysShowsHours() {
        #expect(Timestamp.bracket(0) == "[00:00:00]")
        #expect(Timestamp.bracket(59.9) == "[00:00:59]")
        #expect(Timestamp.bracket(754) == "[00:12:34]")
        #expect(Timestamp.bracket(3723) == "[01:02:03]")
    }

    @Test func durationDropsLeadingZeroHour() {
        #expect(Timestamp.duration(754) == "12:34")
        #expect(Timestamp.duration(3723) == "1:02:03")
        #expect(Timestamp.duration(5530) == "1:32:10")
    }
}
```

- [ ] **Step 2: Write failing Transcript tests**

`Tests/TranscriptorCoreTests/TranscriptTests.swift`:
```swift
import Foundation
import Testing
@testable import TranscriptorCore

@Suite struct TranscriptTests {
    func sample() -> Transcript {
        Transcript(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Clase 3 Riñón",
            sourcePath: "/tmp/clase3.m4a",
            audioDuration: 5530,
            createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            modelChoice: .preciso,
            glossaryPromptUsed: "Clase de medicina. Términos: hipokalemia.",
            segments: [Segment(start: 0, end: 4, text: "Buenos días.")],
            paragraphs: [
                Paragraph(start: 0, text: "Buenos días. Hoy vemos el túbulo."),
                Paragraph(start: 3723, text: "Sigamos con la cetoacidosis."),
            ]
        )
    }

    @Test func markdownHasTitleMetadataAndTimestampedParagraphs() {
        let md = sample().renderMarkdown()
        let lines = md.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines[0] == "# Clase 3 Riñón")
        #expect(lines[2].contains("Duración: 1:32:10"))
        #expect(lines[2].contains("Modelo: Preciso"))
        #expect(md.contains("[00:00:00] Buenos días. Hoy vemos el túbulo."))
        #expect(md.contains("[01:02:03] Sigamos con la cetoacidosis."))
        #expect(md.hasSuffix("\n"))
    }

    @Test func plainTextHasOnlyParagraphs() {
        let txt = sample().renderPlainText()
        #expect(!txt.contains("# "))
        #expect(!txt.contains("Modelo:"))
        #expect(txt.hasPrefix("[00:00:00] Buenos días."))
        #expect(txt.contains("\n\n[01:02:03] Sigamos"))
    }

    @Test func emptyTranscriptRendersNoSpeechNotice() {
        var t = sample()
        t.paragraphs = []
        #expect(t.renderMarkdown().contains("No se detectó voz en el audio."))
        #expect(t.renderPlainText().contains("No se detectó voz en el audio."))
    }

    @Test func jsonRoundTripKeepsEverythingAndSchemaVersion() throws {
        let original = sample()
        let data = try JSONEncoder().encode(original)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["schemaVersion"] as? Int == 1)
        let decoded = try JSONDecoder().decode(Transcript.self, from: data)
        #expect(decoded == original)
    }

    @Test func modelChoiceExposesVariantNames() {
        #expect(ModelChoice.preciso.whisperVariant == "openai_whisper-large-v3_turbo")
        #expect(ModelChoice.rapido.whisperVariant == "openai_whisper-small")
        #expect(ModelChoice.preciso.displayName == "Preciso")
        #expect(ModelChoice.rapido.displayName == "Rápido")
    }
}
```

- [ ] **Step 3: Run tests to verify failure**

Run: `make test`
Expected: compile errors for `Timestamp`, `Transcript`, `Segment`, `ModelChoice`.

- [ ] **Step 4: Implement Segment and Paragraph**

`Sources/TranscriptorCore/Segment.swift`:
```swift
import Foundation

/// One decoded window of speech as returned by the engine, before glossary corrections.
public struct Segment: Codable, Hashable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var avgLogprob: Float
    public var noSpeechProb: Float
    public var compressionRatio: Float

    public init(
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        avgLogprob: Float = 0,
        noSpeechProb: Float = 0,
        compressionRatio: Float = 1
    ) {
        self.start = start
        self.end = end
        self.text = text
        self.avgLogprob = avgLogprob
        self.noSpeechProb = noSpeechProb
        self.compressionRatio = compressionRatio
    }
}

/// A readable block of text with the time its first word was spoken.
public struct Paragraph: Codable, Hashable, Sendable {
    public var start: TimeInterval
    public var text: String

    public init(start: TimeInterval, text: String) {
        self.start = start
        self.text = text
    }
}
```

- [ ] **Step 5: Implement Timestamp**

`Sources/TranscriptorCore/Timestamp.swift`:
```swift
import Foundation

public enum Timestamp {
    /// "[hh:mm:ss]" with hours always present so columns align.
    public static func bracket(_ seconds: TimeInterval) -> String {
        let (h, m, s) = split(seconds)
        return String(format: "[%02d:%02d:%02d]", h, m, s)
    }

    /// "h:mm:ss" or "mm:ss" when under an hour. Used for durations in metadata.
    public static func duration(_ seconds: TimeInterval) -> String {
        let (h, m, s) = split(seconds)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private static func split(_ seconds: TimeInterval) -> (Int, Int, Int) {
        let total = max(0, Int(seconds.rounded(.down)))
        return (total / 3600, (total % 3600) / 60, total % 60)
    }
}
```

- [ ] **Step 6: Implement ModelChoice**

`Sources/TranscriptorCore/ModelChoice.swift`:
```swift
import Foundation

/// The two speech models the user can pick between.
public enum ModelChoice: String, CaseIterable, Codable, Sendable, Identifiable {
    case preciso
    case rapido

    public var id: String { rawValue }

    /// WhisperKit variant name inside the argmaxinc/whisperkit-coreml repo.
    public var whisperVariant: String {
        switch self {
        case .preciso: "openai_whisper-large-v3_turbo"
        case .rapido: "openai_whisper-small"
        }
    }

    public var displayName: String {
        switch self {
        case .preciso: "Preciso"
        case .rapido: "Rápido"
        }
    }

    /// Size and speed hint shown next to the picker.
    public var detailText: String {
        switch self {
        case .preciso: "Whisper large-v3-turbo · descarga de ~3 GB · unos 11 min por clase de 90 min"
        case .rapido: "Whisper small · descarga de ~0,5 GB · unos 3 min por clase de 90 min"
        }
    }

    /// Parallel decoding windows. Measured best value on an M5 for the turbo model.
    public var concurrentWorkers: Int {
        switch self {
        case .preciso: 8
        case .rapido: 4
        }
    }
}
```

- [ ] **Step 7: Implement Transcript**

`Sources/TranscriptorCore/Transcript.swift`:
```swift
import Foundation

/// A finished transcription plus everything needed to re-render or re-correct it.
public struct Transcript: Codable, Hashable, Sendable, Identifiable {
    public static let currentSchemaVersion = 1
    public static let noSpeechNotice = "(No se detectó voz en el audio.)"

    public var schemaVersion: Int
    public var id: UUID
    public var title: String
    /// Base file name used in the library folder. Assigned by Library.save on first save.
    public var fileStem: String?
    public var sourcePath: String
    public var audioDuration: TimeInterval
    public var createdAt: Date
    public var modelChoice: ModelChoice
    public var glossaryPromptUsed: String?
    /// Raw engine output after hallucination filtering, before glossary corrections.
    public var segments: [Segment]
    public var paragraphs: [Paragraph]

    public init(
        id: UUID = UUID(),
        title: String,
        fileStem: String? = nil,
        sourcePath: String,
        audioDuration: TimeInterval,
        createdAt: Date = Date(),
        modelChoice: ModelChoice,
        glossaryPromptUsed: String?,
        segments: [Segment],
        paragraphs: [Paragraph]
    ) {
        self.schemaVersion = Transcript.currentSchemaVersion
        self.id = id
        self.title = title
        self.fileStem = fileStem
        self.sourcePath = sourcePath
        self.audioDuration = audioDuration
        self.createdAt = createdAt
        self.modelChoice = modelChoice
        self.glossaryPromptUsed = glossaryPromptUsed
        self.segments = segments
        self.paragraphs = paragraphs
    }

    public func renderMarkdown() -> String {
        var lines = ["# \(title)", "", metadataLine, ""]
        lines.append(body)
        return lines.joined(separator: "\n") + "\n"
    }

    public func renderPlainText() -> String {
        body + "\n"
    }

    /// "Fecha: 24-09-2026 · Duración: 1:32:10 · Modelo: Preciso"
    public var metadataLine: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "dd-MM-yyyy"
        return "Fecha: \(formatter.string(from: createdAt)) · Duración: \(Timestamp.duration(audioDuration)) · Modelo: \(modelChoice.displayName)"
    }

    private var body: String {
        guard !paragraphs.isEmpty else { return Transcript.noSpeechNotice }
        return paragraphs
            .map { "\(Timestamp.bracket($0.start)) \($0.text)" }
            .joined(separator: "\n\n")
    }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `make test`
Expected: all tests pass (4 from Task 1 + 7 new).

- [ ] **Step 9: Commit**

```bash
git add Sources/TranscriptorCore Tests/TranscriptorCoreTests
git commit -m "feat(core): transcript data model, timestamps and model choice"
```

---

### Task 3: TranscriptFormatter

**Files:**
- Create: `Sources/TranscriptorCore/TranscriptFormatter.swift`
- Test: `Tests/TranscriptorCoreTests/TranscriptFormatterTests.swift`

**Interfaces:**
- Consumes: `Segment`, `Paragraph` from Task 2.
- Produces: `struct TranscriptFormatter: Sendable { gapThreshold: TimeInterval = 1.5; softWordLimit = 120; hardWordLimit = 220; init(); func paragraphs(from: [Segment]) -> [Paragraph] }`

- [ ] **Step 1: Write failing tests**

`Tests/TranscriptorCoreTests/TranscriptFormatterTests.swift`:
```swift
import Testing
@testable import TranscriptorCore

@Suite struct TranscriptFormatterTests {
    let formatter = TranscriptFormatter()

    func seg(_ start: Double, _ end: Double, _ text: String) -> Segment {
        Segment(start: start, end: end, text: text)
    }

    /// Builds `count` segments of `wordsEach` words, back to back, one second each.
    func run(count: Int, wordsEach: Int, from start: Double = 0, ending: String = "") -> [Segment] {
        (0..<count).map { i in
            let words = Array(repeating: "palabra", count: wordsEach).joined(separator: " ")
            return seg(start + Double(i), start + Double(i) + 1, words + ending)
        }
    }

    @Test func emptyInputGivesNoParagraphs() {
        #expect(formatter.paragraphs(from: []).isEmpty)
        #expect(formatter.paragraphs(from: [seg(0, 1, "   ")]).isEmpty)
    }

    @Test func consecutiveSegmentsJoinIntoOneParagraph() {
        let result = formatter.paragraphs(from: [seg(0, 2, " Buenos días. "), seg(2.3, 4, "Hoy vemos el riñón.")])
        #expect(result == [Paragraph(start: 0, text: "Buenos días. Hoy vemos el riñón.")])
    }

    @Test func gapLongerThanThresholdStartsNewParagraph() {
        let result = formatter.paragraphs(from: [seg(0, 2, "Primera idea."), seg(3.6, 5, "Segunda idea.")])
        #expect(result.count == 2)
        #expect(result[1].start == 3.6)
        #expect(result[1].text == "Segunda idea.")
    }

    @Test func gapExactlyAtThresholdDoesNotSplit() {
        let result = formatter.paragraphs(from: [seg(0, 2, "Una."), seg(3.5, 5, "Dos.")])
        #expect(result.count == 1)
    }

    @Test func softLimitSplitsOnlyAtSentenceEnd() {
        // 13 segments x 10 words = 130 words; none ends a sentence, so no split yet.
        var segments = run(count: 13, wordsEach: 10)
        // The 14th ends a sentence -> paragraph closes after it (140 words).
        segments.append(seg(13, 14, "fin de la idea."))
        segments.append(seg(14, 15, "Nueva idea empieza aquí"))
        let result = formatter.paragraphs(from: segments)
        #expect(result.count == 2)
        #expect(result[0].text.hasSuffix("fin de la idea."))
        #expect(result[1].text == "Nueva idea empieza aquí")
    }

    @Test func hardLimitSplitsEvenWithoutPunctuation() {
        // 25 segments x 10 words = 250 words, no punctuation at all.
        let result = formatter.paragraphs(from: run(count: 25, wordsEach: 10))
        #expect(result.count == 2)
        let firstWords = result[0].text.split(separator: " ").count
        #expect(firstWords > 220 && firstWords <= 230)
    }

    @Test func outOfOrderSegmentsAreSortedFirst() {
        let result = formatter.paragraphs(from: [seg(10, 12, "Segundo."), seg(0, 2, "Primero.")])
        #expect(result.count == 2)
        #expect(result[0].text == "Primero.")
        #expect(result[1].text == "Segundo.")
    }

    @Test func paragraphStartIsFirstSegmentStart() {
        let result = formatter.paragraphs(from: [seg(3723.4, 3725, "Hola."), seg(3725.2, 3727, "Chao.")])
        #expect(result == [Paragraph(start: 3723.4, text: "Hola. Chao.")])
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `make test`
Expected: compile error `cannot find 'TranscriptFormatter'`.

- [ ] **Step 3: Implement TranscriptFormatter**

`Sources/TranscriptorCore/TranscriptFormatter.swift`:
```swift
import Foundation

/// Groups engine segments into readable paragraphs.
public struct TranscriptFormatter: Sendable {
    public var gapThreshold: TimeInterval = 1.5
    public var softWordLimit = 120
    public var hardWordLimit = 220

    public init() {}

    public func paragraphs(from segments: [Segment]) -> [Paragraph] {
        var result: [Paragraph] = []
        var current: (start: TimeInterval, words: [String], lastEnd: TimeInterval)?

        func flush() {
            if let c = current, !c.words.isEmpty {
                result.append(Paragraph(start: c.start, text: c.words.joined(separator: " ")))
            }
            current = nil
        }

        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)

            if let c = current, segment.start - c.lastEnd > gapThreshold {
                flush()
            }

            if current == nil {
                current = (segment.start, [], segment.end)
            }
            current!.words.append(contentsOf: words)
            current!.lastEnd = segment.end

            let count = current!.words.count
            let endsSentence = text.hasSuffix(".") || text.hasSuffix("?") || text.hasSuffix("!")
            if count > hardWordLimit || (count > softWordLimit && endsSentence) {
                flush()
            }
        }
        flush()
        return result
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TranscriptorCore/TranscriptFormatter.swift Tests/TranscriptorCoreTests/TranscriptFormatterTests.swift
git commit -m "feat(core): paragraph formatter with gap, soft and hard limits"
```

---

### Task 4: HallucinationFilter

**Files:**
- Create: `Sources/TranscriptorCore/HallucinationFilter.swift`
- Test: `Tests/TranscriptorCoreTests/HallucinationFilterTests.swift`

**Interfaces:**
- Consumes: `Segment`.
- Produces: `struct HallucinationFilter: Sendable { static let knownPhrases: [String]; static let knownPrefixes: [String]; init(); func filter(_: [Segment]) -> [Segment] }`

- [ ] **Step 1: Write failing tests**

`Tests/TranscriptorCoreTests/HallucinationFilterTests.swift`:
```swift
import Testing
@testable import TranscriptorCore

@Suite struct HallucinationFilterTests {
    let filter = HallucinationFilter()

    @Test func dropsExactRepeatOfPreviousSegment() {
        let s = [
            Segment(start: 0, end: 1, text: "El potasio sérico."),
            Segment(start: 1, end: 2, text: " el potasio sérico "),
            Segment(start: 2, end: 3, text: "Otra cosa."),
        ]
        #expect(filter.filter(s).map(\.text) == ["El potasio sérico.", "Otra cosa."])
    }

    @Test func dropsKnownSpanishHallucinations() {
        let s = [
            Segment(start: 0, end: 1, text: "Subtítulos realizados por la comunidad de Amara.org"),
            Segment(start: 1, end: 2, text: "Gracias por ver el video."),
            Segment(start: 2, end: 3, text: "¡Suscríbete!"),
            Segment(start: 3, end: 4, text: "Gracias por venir a clases."),
        ]
        #expect(filter.filter(s).map(\.text) == ["Gracias por venir a clases."])
    }

    @Test func dropsLowConfidenceSilence() {
        let quiet = Segment(start: 0, end: 1, text: "mmm", avgLogprob: -1.4, noSpeechProb: 0.8)
        let confidentButNoSpeechy = Segment(start: 1, end: 2, text: "Ya.", avgLogprob: -0.2, noSpeechProb: 0.8)
        let unsureButSpeech = Segment(start: 2, end: 3, text: "Eh.", avgLogprob: -1.4, noSpeechProb: 0.1)
        #expect(filter.filter([quiet, confidentButNoSpeechy, unsureButSpeech]).map(\.text) == ["Ya.", "Eh."])
    }

    @Test func keepsNormalSpeechUntouched() {
        let s = [Segment(start: 0, end: 1, text: "Hola."), Segment(start: 1, end: 2, text: "Chao.")]
        #expect(filter.filter(s) == s)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `make test`
Expected: compile error `cannot find 'HallucinationFilter'`.

- [ ] **Step 3: Implement HallucinationFilter**

`Sources/TranscriptorCore/HallucinationFilter.swift`:
```swift
import Foundation

/// Removes segments Whisper is known to invent on silence or noise.
public struct HallucinationFilter: Sendable {
    /// Whole-segment matches after normalization (lowercased, no punctuation, single spaces).
    public static let knownPhrases: [String] = [
        "gracias por ver el video",
        "gracias por ver",
        "gracias por ver este video",
        "suscríbete",
        "suscríbete al canal",
        "no olvides suscribirte",
        "hasta la próxima",
        "nos vemos en el próximo video",
        "www mooji org",
    ]

    /// Prefix matches after normalization.
    public static let knownPrefixes: [String] = [
        "subtítulos realizados por",
        "subtitulado por",
        "subtítulos por",
        "transcripción por",
    ]

    public var noSpeechThreshold: Float = 0.6
    public var logProbThreshold: Float = -1.0

    public init() {}

    public func filter(_ segments: [Segment]) -> [Segment] {
        var kept: [Segment] = []
        var previousNormalized: String?
        for segment in segments {
            let normalized = normalize(segment.text)
            if normalized.isEmpty { continue }
            if normalized == previousNormalized { continue }
            if Self.knownPhrases.contains(normalized) { continue }
            if Self.knownPrefixes.contains(where: { normalized.hasPrefix($0) }) { continue }
            if segment.noSpeechProb > noSpeechThreshold && segment.avgLogprob < logProbThreshold { continue }
            kept.append(segment)
            previousNormalized = normalized
        }
        return kept
    }

    private func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let letters = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        return String(letters)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TranscriptorCore/HallucinationFilter.swift Tests/TranscriptorCoreTests/HallucinationFilterTests.swift
git commit -m "feat(core): filter repeated and known hallucinated segments"
```

---

### Task 5: Glossary

**Files:**
- Create: `Sources/TranscriptorCore/Glossary.swift`
- Test: `Tests/TranscriptorCoreTests/GlossaryTests.swift`

**Interfaces:**
- Produces:
  - `struct Glossary: Sendable, Equatable { struct Correction { wrong; right }; struct ParseError { line: Int; message: String }; terms: [String]; corrections: [Correction]; parseErrors: [ParseError]; static let promptTokenBudget = 200; static let promptPrefix; static let templateText: String; init(text: String); func promptText(tokenCount: (String) async -> Int) async -> (text: String?, truncated: Bool); func applyCorrections(to: String) -> String }`

- [ ] **Step 1: Write failing tests**

`Tests/TranscriptorCoreTests/GlossaryTests.swift`:
```swift
import Testing
@testable import TranscriptorCore

@Suite struct GlossaryTests {
    @Test func parsesTermsCorrectionsCommentsAndBlankLines() {
        let g = Glossary(text: """
        # fármacos
        enalapril

        hipocalemia => hipokalemia
        Espironolactona
        """)
        #expect(g.terms == ["enalapril", "hipokalemia", "Espironolactona"])
        #expect(g.corrections == [Glossary.Correction(wrong: "hipocalemia", right: "hipokalemia")])
        #expect(g.parseErrors.isEmpty)
    }

    @Test func toleratesWindowsLineEndingsTrailingSpacesAndDuplicateCasing() {
        let g = Glossary(text: "enalapril  \r\nENALAPRIL\r\n  hipokalemia \r\n")
        #expect(g.terms == ["enalapril", "hipokalemia"])
    }

    @Test func reportsMalformedCorrectionsWithLineNumbers() {
        let g = Glossary(text: "ok\n => hipokalemia\nhipocalemia => \nbien")
        #expect(g.parseErrors.map(\.line) == [2, 3])
        #expect(g.terms == ["ok", "bien"])
    }

    @Test func promptIsNilWhenNoTerms() async {
        let g = Glossary(text: "# nada\n")
        let result = await g.promptText { $0.split(separator: " ").count }
        #expect(result.text == nil)
        #expect(result.truncated == false)
    }

    @Test func promptIncludesAllTermsWhenTheyFit() async {
        let g = Glossary(text: "hipokalemia\nenalapril")
        let result = await g.promptText { $0.split(separator: " ").count }
        #expect(result.text == "Clase de medicina. Términos: hipokalemia, enalapril.")
        #expect(result.truncated == false)
    }

    @Test func promptTruncatesInFileOrderWhenOverBudget() async {
        let terms = (1...300).map { "termino\($0)" }.joined(separator: "\n")
        let g = Glossary(text: terms)
        // One token per whitespace-separated word: prefix is 4 words, so ~196 terms fit.
        let result = await g.promptText { $0.split(separator: " ").count }
        #expect(result.truncated == true)
        let text = result.text!
        #expect(text.contains("termino1,"))
        #expect(!text.contains("termino300"))
        #expect(text.split(separator: " ").count <= Glossary.promptTokenBudget)
    }

    @Test func correctionsAreCaseInsensitiveWholeWordAndKeepCapitalization() {
        let g = Glossary(text: "hipocalemia => hipokalemia")
        let out = g.applyCorrections(to: "Hipocalemia severa. La hipocalemia y la pseudohipocalemia.")
        #expect(out == "Hipokalemia severa. La hipokalemia y la pseudohipocalemia.")
    }

    @Test func correctionsEscapeRegexMetacharactersAndHandleMultiWordSources() {
        let g = Glossary(text: "v.o. => vía oral\nen alaprilo => enalapril o")
        let out = g.applyCorrections(to: "Dar v.o. cada 8 horas con en alaprilo espironolactona. Sin vxox aquí.")
        #expect(out == "Dar vía oral cada 8 horas con enalapril o espironolactona. Sin vxox aquí.")
    }

    @Test func correctionsApplyInFileOrder() {
        let g = Glossary(text: "a1 => b1\nb1 => c1")
        #expect(g.applyCorrections(to: "a1 y b1") == "c1 y c1")
    }

    @Test func templateParsesCleanly() {
        let g = Glossary(text: Glossary.templateText)
        #expect(g.parseErrors.isEmpty)
        #expect(!g.terms.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `make test`
Expected: compile error `cannot find 'Glossary'`.

- [ ] **Step 3: Implement Glossary**

`Sources/TranscriptorCore/Glossary.swift`:
```swift
import Foundation

/// User-maintained vocabulary: terms that bias decoding and corrections applied afterwards.
public struct Glossary: Sendable, Equatable {
    public struct Correction: Sendable, Equatable {
        public var wrong: String
        public var right: String
        public init(wrong: String, right: String) {
            self.wrong = wrong
            self.right = right
        }
    }

    public struct ParseError: Sendable, Equatable {
        public var line: Int
        public var message: String
    }

    public static let promptTokenBudget = 200
    public static let promptPrefix = "Clase de medicina. Términos: "

    public static let templateText = """
    # Glosario de Transcriptor
    # Una entrada por línea. Las líneas que empiezan con # son comentarios.
    #
    # 1) Un término por línea ayuda al modelo a escribirlo bien:
    hipokalemia
    hiperkalemia
    enalapril
    espironolactona
    cetoacidosis diabética
    #
    # 2) Una corrección reemplaza lo que el modelo escribe mal por lo correcto:
    hipocalemia => hipokalemia
    hipercalemia => hiperkalemia
    """

    public private(set) var terms: [String] = []
    public private(set) var corrections: [Correction] = []
    public private(set) var parseErrors: [ParseError] = []

    public init(text: String) {
        var seen = Set<String>()
        func addTerm(_ term: String) {
            let key = term.lowercased()
            if seen.insert(key).inserted { terms.append(term) }
        }

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if let range = line.range(of: "=>") {
                let wrong = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let right = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if wrong.isEmpty || right.isEmpty {
                    parseErrors.append(ParseError(line: index + 1, message: "Falta un lado de la corrección (formato: incorrecto => correcto)."))
                    continue
                }
                corrections.append(Correction(wrong: wrong, right: right))
                addTerm(right)
            } else {
                addTerm(line)
            }
        }
    }

    /// Builds the decoding prompt from terms in file order, stopping at the token budget.
    public func promptText(tokenCount: (String) async -> Int) async -> (text: String?, truncated: Bool) {
        guard !terms.isEmpty else { return (nil, false) }
        var included: [String] = []
        for term in terms {
            let candidate = Self.promptPrefix + (included + [term]).joined(separator: ", ") + "."
            if await tokenCount(candidate) > Self.promptTokenBudget { break }
            included.append(term)
        }
        guard !included.isEmpty else { return (nil, true) }
        return (Self.promptPrefix + included.joined(separator: ", ") + ".", included.count < terms.count)
    }

    /// Applies corrections in file order: case-insensitive, whole-word, keeping a leading capital.
    public func applyCorrections(to text: String) -> String {
        var result = text
        for correction in corrections {
            // Lookarounds instead of \b so sources ending in punctuation ("v.o.") still match before a space.
            let escaped = NSRegularExpression.escapedPattern(for: correction.wrong)
            let pattern = "(?<![\\p{L}\\p{N}])" + escaped + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let nsResult = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsResult.length))
            var mutable = result
            for match in matches.reversed() {
                let original = nsResult.substring(with: match.range)
                var replacement = correction.right
                if let first = original.first, first.isUppercase {
                    replacement = replacement.prefix(1).uppercased() + replacement.dropFirst()
                }
                mutable = (mutable as NSString).replacingCharacters(in: match.range, with: replacement)
            }
            result = mutable
        }
        return result
    }
}
```

Note on the pattern: `\p{L}` and `\p{N}` are Unicode letters and digits, so `hipokalemia` does not match inside `pseudohipokalemia`, accented letters count as word characters, and `v.o.` matches when followed by a space.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TranscriptorCore/Glossary.swift Tests/TranscriptorCoreTests/GlossaryTests.swift
git commit -m "feat(core): glossary parsing, prompt building and corrections"
```

---

### Task 6: Settings, TranscriptionError, engine protocol, pipeline

**Files:**
- Create: `Sources/TranscriptorCore/Settings.swift`
- Create: `Sources/TranscriptorCore/TranscriptionError.swift`
- Create: `Sources/TranscriptorCore/TranscriptionEngine.swift`
- Create: `Sources/TranscriptorCore/TranscriptPipeline.swift`
- Test: `Tests/TranscriptorCoreTests/SettingsTests.swift`
- Test: `Tests/TranscriptorCoreTests/TranscriptPipelineTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor @Observable final class Settings { var modelChoice: ModelChoice; var libraryFolder: URL; init(defaults: UserDefaults = .standard) }`
  - `enum TranscriptionError: Error, LocalizedError, Sendable { unsupportedFormat(String), fileUnreadable(String), modelDownloadFailed(String), modelLoadFailed(String), cancelled, engineFailure(String) }` with Spanish `errorDescription`.
  - `struct TranscriptionOutput: Sendable { segments: [Segment]; audioDuration: TimeInterval }`
  - `protocol TranscriptionEngine: Sendable { prepare(model:progress:) async throws; transcribe(fileURL:prompt:progress:) async throws -> TranscriptionOutput; tokenCount(_:) async -> Int; cancel() async }`
  - `enum TranscriptPipeline { static func build(output:, sourceURL:, model:, glossary:, prompt: String?, now: Date = Date()) -> Transcript; static func reapply(glossary:, to:) -> Transcript }`

- [ ] **Step 1: Write failing Settings test**

`Tests/TranscriptorCoreTests/SettingsTests.swift`:
```swift
import Foundation
import Testing
@testable import TranscriptorCore

@Suite struct SettingsTests {
    func freshDefaults() -> UserDefaults {
        let name = "SettingsTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @MainActor @Test func defaultsArePrecisoAndDocumentsFolder() {
        let s = Settings(defaults: freshDefaults())
        #expect(s.modelChoice == .preciso)
        #expect(s.libraryFolder.lastPathComponent == "Transcripciones")
        #expect(s.libraryFolder.deletingLastPathComponent().lastPathComponent == "Documents")
    }

    @MainActor @Test func changesPersistAcrossInstances() {
        let d = freshDefaults()
        let s1 = Settings(defaults: d)
        s1.modelChoice = .rapido
        s1.libraryFolder = URL(fileURLWithPath: "/tmp/otra")
        let s2 = Settings(defaults: d)
        #expect(s2.modelChoice == .rapido)
        #expect(s2.libraryFolder.path == "/tmp/otra")
    }
}
```

- [ ] **Step 2: Write failing pipeline tests**

`Tests/TranscriptorCoreTests/TranscriptPipelineTests.swift`:
```swift
import Foundation
import Testing
@testable import TranscriptorCore

@Suite struct TranscriptPipelineTests {
    let output = TranscriptionOutput(
        segments: [
            Segment(start: 0, end: 2, text: "La hipocalemia severa."),
            Segment(start: 2.2, end: 4, text: "La hipocalemia severa."),  // repeat -> filtered
            Segment(start: 10, end: 12, text: "Dar en alaprilo."),
        ],
        audioDuration: 12
    )
    let glossary = Glossary(text: "hipocalemia => hipokalemia\nen alaprilo => enalapril")

    @Test func buildFiltersCorrectsAndFormats() {
        let t = TranscriptPipeline.build(
            output: output,
            sourceURL: URL(fileURLWithPath: "/tmp/Clase 3.m4a"),
            model: .rapido,
            glossary: glossary,
            prompt: "Clase de medicina. Términos: hipokalemia, enalapril."
        )
        #expect(t.title == "Clase 3")
        #expect(t.sourcePath == "/tmp/Clase 3.m4a")
        #expect(t.audioDuration == 12)
        #expect(t.modelChoice == .rapido)
        #expect(t.glossaryPromptUsed == "Clase de medicina. Términos: hipokalemia, enalapril.")
        #expect(t.segments.map(\.text) == ["La hipocalemia severa.", "Dar en alaprilo."])  // raw, filtered
        #expect(t.paragraphs.map(\.text) == ["La hipokalemia severa.", "Dar enalapril."])
    }

    @Test func reapplyUsesStoredSegmentsAndNewGlossary() {
        let t = TranscriptPipeline.build(output: output, sourceURL: URL(fileURLWithPath: "/tmp/a.m4a"), model: .preciso, glossary: Glossary(text: ""), prompt: nil)
        #expect(t.paragraphs.map(\.text) == ["La hipocalemia severa.", "Dar en alaprilo."])
        let fixed = TranscriptPipeline.reapply(glossary: glossary, to: t)
        #expect(fixed.paragraphs.map(\.text) == ["La hipokalemia severa.", "Dar enalapril."])
        #expect(fixed.id == t.id)
        #expect(fixed.segments == t.segments)
    }

    @Test func errorsHaveSpanishDescriptions() {
        #expect(TranscriptionError.cancelled.errorDescription == "Cancelado.")
        #expect(TranscriptionError.fileUnreadable("x.m4a").errorDescription?.contains("x.m4a") == true)
        #expect(TranscriptionError.modelDownloadFailed("sin red").errorDescription?.contains("descargar") == true)
    }
}
```

- [ ] **Step 3: Run tests to verify failure**

Run: `make test`
Expected: compile errors for `Settings`, `TranscriptionOutput`, `TranscriptPipeline`, `TranscriptionError`.

- [ ] **Step 4: Implement Settings**

`Sources/TranscriptorCore/Settings.swift`:
```swift
import Foundation
import Observation

/// User preferences backed by UserDefaults.
@MainActor @Observable
public final class Settings {
    private enum Key {
        static let modelChoice = "modelChoice"
        static let libraryFolder = "libraryFolder"
    }

    private let defaults: UserDefaults

    public var modelChoice: ModelChoice {
        didSet { defaults.set(modelChoice.rawValue, forKey: Key.modelChoice) }
    }

    public var libraryFolder: URL {
        didSet { defaults.set(libraryFolder.path, forKey: Key.libraryFolder) }
    }

    public static var defaultLibraryFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Transcripciones", isDirectory: true)
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.modelChoice = defaults.string(forKey: Key.modelChoice).flatMap(ModelChoice.init(rawValue:)) ?? .preciso
        if let path = defaults.string(forKey: Key.libraryFolder) {
            self.libraryFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            self.libraryFolder = Settings.defaultLibraryFolder
        }
    }
}
```

- [ ] **Step 5: Implement TranscriptionError**

`Sources/TranscriptorCore/TranscriptionError.swift`:
```swift
import Foundation

/// Every failure the UI can show. Descriptions are plain Spanish, one sentence.
public enum TranscriptionError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedFormat(String)
    case fileUnreadable(String)
    case modelDownloadFailed(String)
    case modelLoadFailed(String)
    case cancelled
    case engineFailure(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let message):
            return message
        case .fileUnreadable(let name):
            return "No se pudo leer el archivo \"\(name)\". ¿Se movió o borró?"
        case .modelDownloadFailed(let detail):
            return "No se pudo descargar el modelo. Revisa la conexión a internet e inténtalo de nuevo. (\(detail))"
        case .modelLoadFailed(let detail):
            return "No se pudo cargar el modelo de transcripción. (\(detail))"
        case .cancelled:
            return "Cancelado."
        case .engineFailure(let detail):
            return "La transcripción falló. (\(detail))"
        }
    }

    /// Message for any thrown error, in Spanish.
    public static func message(for error: Error) -> String {
        if let known = error as? TranscriptionError { return known.errorDescription ?? "Error." }
        if error is CancellationError { return TranscriptionError.cancelled.errorDescription! }
        return "Error inesperado: \(String(describing: error))"
    }
}
```

- [ ] **Step 6: Implement the engine protocol**

`Sources/TranscriptorCore/TranscriptionEngine.swift`:
```swift
import Foundation

public struct TranscriptionOutput: Sendable, Equatable {
    public var segments: [Segment]
    public var audioDuration: TimeInterval

    public init(segments: [Segment], audioDuration: TimeInterval) {
        self.segments = segments
        self.audioDuration = audioDuration
    }
}

/// What the app needs from a speech engine. Implemented by WhisperKitEngine and by test fakes.
public protocol TranscriptionEngine: Sendable {
    /// Downloads (if needed) and loads the model. Idempotent when the same model is already loaded.
    /// `progress` is 0...1 across download and load.
    func prepare(model: ModelChoice, progress: @escaping @Sendable (Double) -> Void) async throws

    /// Transcribes one file. `progress` is 0...1. Throws TranscriptionError.
    func transcribe(fileURL: URL, prompt: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> TranscriptionOutput

    /// Token count for prompt budgeting with the loaded model's tokenizer.
    func tokenCount(_ text: String) async -> Int

    /// Asks the current transcription to stop as soon as possible.
    func cancel() async
}
```

- [ ] **Step 7: Implement TranscriptPipeline**

`Sources/TranscriptorCore/TranscriptPipeline.swift`:
```swift
import Foundation

/// The steps between raw engine output and a saved transcript.
public enum TranscriptPipeline {
    public static func build(
        output: TranscriptionOutput,
        sourceURL: URL,
        model: ModelChoice,
        glossary: Glossary,
        prompt: String?,
        now: Date = Date()
    ) -> Transcript {
        let filtered = HallucinationFilter().filter(output.segments)
        return Transcript(
            title: sourceURL.deletingPathExtension().lastPathComponent,
            sourcePath: sourceURL.path,
            audioDuration: output.audioDuration,
            createdAt: now,
            modelChoice: model,
            glossaryPromptUsed: prompt,
            segments: filtered,
            paragraphs: paragraphs(from: filtered, glossary: glossary)
        )
    }

    /// Re-runs corrections and formatting on the stored segments. Nothing else changes.
    public static func reapply(glossary: Glossary, to transcript: Transcript) -> Transcript {
        var updated = transcript
        updated.paragraphs = paragraphs(from: transcript.segments, glossary: glossary)
        return updated
    }

    private static func paragraphs(from segments: [Segment], glossary: Glossary) -> [Paragraph] {
        let corrected = segments.map { segment in
            var s = segment
            s.text = glossary.applyCorrections(to: segment.text)
            return s
        }
        return TranscriptFormatter().paragraphs(from: corrected)
    }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `make test`
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add Sources/TranscriptorCore Tests/TranscriptorCoreTests
git commit -m "feat(core): settings, engine protocol, errors and transcript pipeline"
```

---

### Task 7: Library (transcripts and glossary on disk)

**Files:**
- Create: `Sources/TranscriptorCore/Library.swift`
- Test: `Tests/TranscriptorCoreTests/LibraryTests.swift`

**Interfaces:**
- Consumes: `Transcript`, `Glossary.templateText`.
- Produces: `struct Library: Sendable { let folder: URL; init(folder:); func ensureExists() throws; var glossaryURL: URL; func loadGlossaryText() -> String; func saveGlossaryText(_:) throws; func save(_ transcript: Transcript) throws -> Transcript; func list() -> [Transcript]; func markdownURL(for:) -> URL?; static func sanitizedStem(_:) -> String }`

- [ ] **Step 1: Write failing tests**

`Tests/TranscriptorCoreTests/LibraryTests.swift`:
```swift
import Foundation
import Testing
@testable import TranscriptorCore

@Suite struct LibraryTests {
    func tempLibrary() throws -> Library {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryTests-\(UUID().uuidString)")
        let lib = Library(folder: dir)
        try lib.ensureExists()
        return lib
    }

    func transcript(title: String) -> Transcript {
        Transcript(
            title: title, sourcePath: "/tmp/\(title).m4a", audioDuration: 60,
            createdAt: Date(), modelChoice: .rapido, glossaryPromptUsed: nil,
            segments: [Segment(start: 0, end: 1, text: "Hola.")],
            paragraphs: [Paragraph(start: 0, text: "Hola.")]
        )
    }

    @Test func saveWritesMarkdownAndSidecarAndAssignsStem() throws {
        let lib = try tempLibrary()
        let saved = try lib.save(transcript(title: "Clase 1"))
        #expect(saved.fileStem == "Clase 1")
        let md = lib.folder.appendingPathComponent("Clase 1.md")
        let json = lib.folder.appendingPathComponent("Clase 1.transcriptor.json")
        #expect(FileManager.default.fileExists(atPath: md.path))
        #expect(FileManager.default.fileExists(atPath: json.path))
        #expect(try String(contentsOf: md, encoding: .utf8).hasPrefix("# Clase 1"))
    }

    @Test func collisionsGetNumericSuffixes() throws {
        let lib = try tempLibrary()
        let a = try lib.save(transcript(title: "Clase"))
        let b = try lib.save(transcript(title: "Clase"))
        let c = try lib.save(transcript(title: "Clase"))
        #expect([a.fileStem, b.fileStem, c.fileStem] == ["Clase", "Clase (2)", "Clase (3)"])
    }

    @Test func resavingAnAssignedStemOverwritesInPlace() throws {
        let lib = try tempLibrary()
        var saved = try lib.save(transcript(title: "Clase"))
        saved.paragraphs = [Paragraph(start: 0, text: "Cambiado.")]
        let again = try lib.save(saved)
        #expect(again.fileStem == "Clase")
        #expect(lib.list().count == 1)
        #expect(lib.list()[0].paragraphs[0].text == "Cambiado.")
    }

    @Test func invalidFileNameCharactersAreReplaced() throws {
        let lib = try tempLibrary()
        let saved = try lib.save(transcript(title: "Clase 3: Riñón / Túbulo"))
        #expect(saved.fileStem == "Clase 3- Riñón - Túbulo")
        #expect(saved.title == "Clase 3: Riñón / Túbulo")
        #expect(Library.sanitizedStem("   ") == "Transcripción")
    }

    @Test func listReturnsNewestFirstAndSkipsCorruptSidecars() throws {
        let lib = try tempLibrary()
        var old = transcript(title: "Vieja"); old.createdAt = Date(timeIntervalSince1970: 1_000)
        var new = transcript(title: "Nueva"); new.createdAt = Date(timeIntervalSince1970: 2_000)
        _ = try lib.save(old)
        _ = try lib.save(new)
        try "no es json".write(to: lib.folder.appendingPathComponent("rota.transcriptor.json"), atomically: true, encoding: .utf8)
        try "# otro".write(to: lib.folder.appendingPathComponent("otro.md"), atomically: true, encoding: .utf8)
        #expect(lib.list().map(\.title) == ["Nueva", "Vieja"])
    }

    @Test func glossaryDefaultsToTemplateThenPersists() throws {
        let lib = try tempLibrary()
        #expect(lib.loadGlossaryText() == Glossary.templateText)
        try lib.saveGlossaryText("enalapril\n")
        #expect(lib.loadGlossaryText() == "enalapril\n")
        #expect(FileManager.default.fileExists(atPath: lib.glossaryURL.path))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `make test`
Expected: compile error `cannot find 'Library'`.

- [ ] **Step 3: Implement Library**

`Sources/TranscriptorCore/Library.swift`:
```swift
import Foundation

/// The folder where transcripts and the glossary live. Plain files the user can browse.
public struct Library: Sendable {
    public static let sidecarSuffix = ".transcriptor.json"
    public static let glossaryFileName = "glosario.txt"

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func ensureExists() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    // MARK: Glossary

    public var glossaryURL: URL { folder.appendingPathComponent(Library.glossaryFileName) }

    public func loadGlossaryText() -> String {
        (try? String(contentsOf: glossaryURL, encoding: .utf8)) ?? Glossary.templateText
    }

    public func saveGlossaryText(_ text: String) throws {
        try ensureExists()
        try text.write(to: glossaryURL, atomically: true, encoding: .utf8)
    }

    // MARK: Transcripts

    /// Writes `<stem>.md` and `<stem>.transcriptor.json`. Assigns a unique stem on first save.
    public func save(_ transcript: Transcript) throws -> Transcript {
        try ensureExists()
        var saved = transcript
        if saved.fileStem == nil {
            saved.fileStem = uniqueStem(for: Library.sanitizedStem(transcript.title))
        }
        let stem = saved.fileStem!
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(saved).write(to: sidecarURL(stem: stem), options: .atomic)
        try saved.renderMarkdown().write(to: markdownURL(stem: stem), atomically: true, encoding: .utf8)
        return saved
    }

    /// All transcripts, newest first. Unreadable sidecars are skipped.
    public func list() -> [Transcript] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return names
            .filter { $0.hasSuffix(Library.sidecarSuffix) }
            .compactMap { name -> Transcript? in
                guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
                return try? decoder.decode(Transcript.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func markdownURL(for transcript: Transcript) -> URL? {
        transcript.fileStem.map(markdownURL(stem:))
    }

    /// Replaces characters macOS or Finder treat specially. Empty titles become "Transcripción".
    public static func sanitizedStem(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Transcripción" : cleaned
    }

    private func uniqueStem(for base: String) -> String {
        var candidate = base
        var n = 2
        while FileManager.default.fileExists(atPath: sidecarURL(stem: candidate).path)
            || FileManager.default.fileExists(atPath: markdownURL(stem: candidate).path) {
            candidate = "\(base) (\(n))"
            n += 1
        }
        return candidate
    }

    private func markdownURL(stem: String) -> URL { folder.appendingPathComponent(stem + ".md") }
    private func sidecarURL(stem: String) -> URL { folder.appendingPathComponent(stem + Library.sidecarSuffix) }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: all pass. (`Date` round-trips through ISO-8601 at second precision; the tests compare titles and ordering, not exact dates.)

- [ ] **Step 5: Commit**

```bash
git add Sources/TranscriptorCore/Library.swift Tests/TranscriptorCoreTests/LibraryTests.swift
git commit -m "feat(core): on-disk library for transcripts and glossary"
```

---

### Task 8: JobQueue

**Files:**
- Create: `Sources/TranscriptorCore/JobQueue.swift`
- Create: `Tests/TranscriptorCoreTests/FakeEngine.swift`
- Test: `Tests/TranscriptorCoreTests/JobQueueTests.swift`

**Interfaces:**
- Consumes: `TranscriptionEngine`, `Library`, `Settings`, `Glossary`, `TranscriptPipeline`, `SupportedAudio`, `TranscriptionError`.
- Produces:
  - `struct Job: Identifiable, Sendable, Equatable { enum State { waiting, loadingModel(Double), transcribing(Double), applyingGlossary, done(Transcript), failed(String) }; id: UUID; fileURL: URL; state: State; var isFinished: Bool }`
  - `@MainActor @Observable final class JobQueue { private(set) var jobs: [Job]; var library: Library; var onTranscriptSaved: (@MainActor (Transcript) -> Void)?; var onJobFailed: (@MainActor (Job, String) -> Void)?; var lastPromptTruncated: Bool; init(engine:library:settings:); @discardableResult func add(_ urls: [URL]) -> [String]; func cancelAll() async; func clearFinished(); func waitUntilIdle() async }`

- [ ] **Step 1: Write the fake engine**

`Tests/TranscriptorCoreTests/FakeEngine.swift`:
```swift
import Foundation
@testable import TranscriptorCore

/// Scripted engine: returns canned segments per file name, or throws.
actor FakeEngine: TranscriptionEngine {
    var results: [String: Result<TranscriptionOutput, TranscriptionError>] = [:]
    private(set) var prepareCalls: [ModelChoice] = []
    private(set) var prompts: [String?] = []
    private(set) var cancelCalls = 0
    var delayNanoseconds: UInt64 = 0

    func set(_ fileName: String, _ result: Result<TranscriptionOutput, TranscriptionError>) {
        results[fileName] = result
    }

    func prepare(model: ModelChoice, progress: @escaping @Sendable (Double) -> Void) async throws {
        prepareCalls.append(model)
        progress(1)
    }

    func transcribe(fileURL: URL, prompt: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> TranscriptionOutput {
        prompts.append(prompt)
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        progress(0.5)
        guard let result = results[fileURL.lastPathComponent] else {
            throw TranscriptionError.fileUnreadable(fileURL.lastPathComponent)
        }
        progress(1)
        return try result.get()
    }

    func tokenCount(_ text: String) async -> Int {
        text.split(separator: " ").count
    }

    func cancel() async {
        cancelCalls += 1
    }
}
```

- [ ] **Step 2: Write failing JobQueue tests**

`Tests/TranscriptorCoreTests/JobQueueTests.swift`:
```swift
import Foundation
import Testing
@testable import TranscriptorCore

@MainActor
@Suite struct JobQueueTests {
    func makeQueue(engine: FakeEngine) throws -> (JobQueue, Library) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("JobQueueTests-\(UUID().uuidString)")
        let library = Library(folder: dir)
        try library.ensureExists()
        let defaults = UserDefaults(suiteName: "JobQueueTests-\(UUID().uuidString)")!
        let settings = Settings(defaults: defaults)
        settings.modelChoice = .rapido
        return (JobQueue(engine: engine, library: library, settings: settings), library)
    }

    /// Creates a real empty file so the queue's existence check passes.
    func touch(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("JobQueueTests-\(UUID().uuidString)-\(name)")
        try Data().write(to: url)
        return url
    }

    let output = TranscriptionOutput(segments: [Segment(start: 0, end: 1, text: "Hola hipocalemia.")], audioDuration: 1)

    @Test func processesFilesInOrderAndSavesTranscripts() async throws {
        let engine = FakeEngine()
        let (queue, library) = try makeQueue(engine: engine)
        let a = try touch("a.m4a"), b = try touch("b.mp3")
        await engine.set(a.lastPathComponent, .success(output))
        await engine.set(b.lastPathComponent, .success(output))

        var saved: [String] = []
        queue.onTranscriptSaved = { saved.append($0.title) }
        queue.add([a, b])
        await queue.waitUntilIdle()

        #expect(queue.jobs.count == 2)
        for job in queue.jobs {
            guard case .done = job.state else { Issue.record("expected done, got \(job.state)"); continue }
        }
        #expect(saved.count == 2)
        #expect(library.list().count == 2)
        #expect(await engine.prepareCalls == [.rapido, .rapido])
    }

    @Test func rejectsUnsupportedFilesWithMessages() throws {
        let engine = FakeEngine()
        let (queue, _) = try makeQueue(engine: engine)
        let messages = queue.add([URL(fileURLWithPath: "/tmp/nota.opus"), URL(fileURLWithPath: "/tmp/x.pdf")])
        #expect(messages.count == 2)
        #expect(messages[0].contains("WhatsApp"))
        #expect(queue.jobs.isEmpty)
    }

    @Test func missingFileFailsOnlyThatJobAndQueueContinues() async throws {
        let engine = FakeEngine()
        let (queue, _) = try makeQueue(engine: engine)
        let gone = URL(fileURLWithPath: "/tmp/no-existe-\(UUID().uuidString).m4a")
        let ok = try touch("ok.m4a")
        await engine.set(ok.lastPathComponent, .success(output))

        queue.add([gone, ok])
        await queue.waitUntilIdle()

        guard case .failed(let message) = queue.jobs[0].state else { Issue.record("expected failed"); return }
        #expect(message.contains("No se pudo leer"))
        guard case .done = queue.jobs[1].state else { Issue.record("expected done"); return }
    }

    @Test func engineErrorsBecomeSpanishMessagesAndFireCallback() async throws {
        let engine = FakeEngine()
        let (queue, _) = try makeQueue(engine: engine)
        let bad = try touch("bad.m4a")
        await engine.set(bad.lastPathComponent, .failure(.engineFailure("boom")))
        var reported: [String] = []
        queue.onJobFailed = { _, message in reported.append(message) }
        queue.add([bad])
        await queue.waitUntilIdle()
        guard case .failed(let message) = queue.jobs[0].state else { Issue.record("expected failed"); return }
        #expect(message == "La transcripción falló. (boom)")
        #expect(reported == [message])
    }

    @Test func glossaryPromptAndCorrectionsAreApplied() async throws {
        let engine = FakeEngine()
        let (queue, library) = try makeQueue(engine: engine)
        try library.saveGlossaryText("hipocalemia => hipokalemia\n")
        let a = try touch("a.m4a")
        await engine.set(a.lastPathComponent, .success(output))
        queue.add([a])
        await queue.waitUntilIdle()

        #expect(await engine.prompts == ["Clase de medicina. Términos: hipokalemia."])
        guard case .done(let t) = queue.jobs[0].state else { Issue.record("expected done"); return }
        #expect(t.paragraphs[0].text == "Hola hipokalemia.")
        #expect(queue.lastPromptTruncated == false)
    }

    @Test func duplicateOfAnUnfinishedJobIsIgnored() async throws {
        let engine = FakeEngine()
        await engine.setDelay(200_000_000)
        let (queue, _) = try makeQueue(engine: engine)
        let a = try touch("a.m4a")
        await engine.set(a.lastPathComponent, .success(output))
        queue.add([a])
        let messages = queue.add([a])
        #expect(queue.jobs.count == 1)
        #expect(messages.count == 1 && messages[0].contains("ya está en la lista"))
        await queue.waitUntilIdle()
    }

    @Test func cancelAllRemovesWaitingJobsAndAsksEngineToStop() async throws {
        let engine = FakeEngine()
        await engine.setDelay(300_000_000)
        let (queue, _) = try makeQueue(engine: engine)
        let a = try touch("a.m4a"), b = try touch("b.m4a")
        await engine.set(a.lastPathComponent, .success(output))
        await engine.set(b.lastPathComponent, .success(output))
        queue.add([a, b])
        try await Task.sleep(nanoseconds: 50_000_000)
        await queue.cancelAll()
        await queue.waitUntilIdle()

        #expect(await engine.cancelCalls == 1)
        #expect(queue.jobs.count == 1)  // b was removed while waiting
        #expect(queue.jobs[0].fileURL == a)
    }

    @Test func clearFinishedKeepsActiveJobs() async throws {
        let engine = FakeEngine()
        let (queue, _) = try makeQueue(engine: engine)
        let a = try touch("a.m4a")
        await engine.set(a.lastPathComponent, .success(output))
        queue.add([a])
        await queue.waitUntilIdle()
        queue.clearFinished()
        #expect(queue.jobs.isEmpty)
    }
}
```

Add to `FakeEngine`:
```swift
    func setDelay(_ nanoseconds: UInt64) { delayNanoseconds = nanoseconds }
```

- [ ] **Step 3: Run tests to verify failure**

Run: `make test`
Expected: compile error `cannot find 'JobQueue'`.

- [ ] **Step 4: Implement JobQueue**

`Sources/TranscriptorCore/JobQueue.swift`:
```swift
import Foundation
import Observation

public struct Job: Identifiable, Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case waiting
        case loadingModel(Double)
        case transcribing(Double)
        case applyingGlossary
        case done(Transcript)
        case failed(String)
    }

    public let id: UUID
    public let fileURL: URL
    public var state: State

    public var isFinished: Bool {
        switch state {
        case .done, .failed: true
        default: false
        }
    }

    /// Spanish label for the sidebar.
    public var stateText: String {
        switch state {
        case .waiting: "En espera"
        case .loadingModel: "Cargando modelo…"
        case .transcribing(let p): "Transcribiendo… \(Int(p * 100))%"
        case .applyingGlossary: "Aplicando glosario…"
        case .done: "Listo"
        case .failed(let message): "Error: \(message)"
        }
    }
}

/// Sequential processor: one file at a time, failures never stop the line.
@MainActor @Observable
public final class JobQueue {
    public private(set) var jobs: [Job] = []
    /// Called after each transcript is written to the library.
    public var onTranscriptSaved: (@MainActor (Transcript) -> Void)?
    /// Called when a job fails, with the Spanish message shown to the user.
    public var onJobFailed: (@MainActor (Job, String) -> Void)?
    /// True when the last built prompt had to drop glossary terms.
    public private(set) var lastPromptTruncated = false

    private let engine: any TranscriptionEngine
    /// Where finished transcripts are saved. Replaced when the user changes the folder in settings.
    public var library: Library
    private let settings: Settings
    private var worker: Task<Void, Never>?

    public init(engine: any TranscriptionEngine, library: Library, settings: Settings) {
        self.engine = engine
        self.library = library
        self.settings = settings
    }

    /// Queues supported files. Returns one Spanish message per rejected URL.
    @discardableResult
    public func add(_ urls: [URL]) -> [String] {
        var rejections: [String] = []
        for url in urls {
            guard SupportedAudio.isSupported(url) else {
                rejections.append(SupportedAudio.rejectionMessage(for: url))
                continue
            }
            if jobs.contains(where: { $0.fileURL == url && !$0.isFinished }) {
                rejections.append("\"\(url.lastPathComponent)\" ya está en la lista.")
                continue
            }
            jobs.append(Job(id: UUID(), fileURL: url, state: .waiting))
        }
        startIfNeeded()
        return rejections
    }

    /// Drops waiting jobs and asks the engine to stop the current one.
    public func cancelAll() async {
        jobs.removeAll { if case .waiting = $0.state { return true } else { return false } }
        await engine.cancel()
    }

    public func clearFinished() {
        jobs.removeAll(where: \.isFinished)
    }

    /// Resolves when no job is running. For tests and for quitting cleanly.
    public func waitUntilIdle() async {
        await worker?.value
    }

    // MARK: Processing

    private func startIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, let next = self.jobs.first(where: { if case .waiting = $0.state { return true } else { return false } }) {
                await self.process(next.id)
            }
            self?.worker = nil
        }
    }

    private func process(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        do {
            guard FileManager.default.isReadableFile(atPath: job.fileURL.path) else {
                throw TranscriptionError.fileUnreadable(job.fileURL.lastPathComponent)
            }

            update(id, .loadingModel(0))
            let model = settings.modelChoice
            try await engine.prepare(model: model) { [weak self] p in
                Task { @MainActor in self?.update(id, .loadingModel(p)) }
            }

            let glossary = Glossary(text: library.loadGlossaryText())
            let prompt = await glossary.promptText { [engine] text in await engine.tokenCount(text) }
            lastPromptTruncated = prompt.truncated

            update(id, .transcribing(0))
            let output = try await engine.transcribe(fileURL: job.fileURL, prompt: prompt.text) { [weak self] p in
                Task { @MainActor in self?.update(id, .transcribing(p)) }
            }

            update(id, .applyingGlossary)
            let transcript = TranscriptPipeline.build(
                output: output, sourceURL: job.fileURL, model: model, glossary: glossary, prompt: prompt.text
            )
            let saved = try library.save(transcript)
            update(id, .done(saved))
            onTranscriptSaved?(saved)
        } catch {
            let message = TranscriptionError.message(for: error)
            update(id, .failed(message))
            if let failed = jobs.first(where: { $0.id == id }) { onJobFailed?(failed, message) }
        }
    }

    private func update(_ id: UUID, _ state: Job.State) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        // Ignore late progress callbacks after a job finished.
        if jobs[index].isFinished { return }
        jobs[index].state = state
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: all pass. If `cancelAllRemovesWaitingJobs...` is flaky because the fake finishes before `cancelAll`, raise the fake's delay to 500 ms in that test.

- [ ] **Step 6: Commit**

```bash
git add Sources/TranscriptorCore/JobQueue.swift Tests/TranscriptorCoreTests
git commit -m "feat(core): sequential job queue with per-item failure handling"
```

---

### Task 9: WhisperKit engine and model manager, with a gated integration test

**Files:**
- Modify: `Package.swift` (add WhisperKit dependency)
- Delete: `Sources/TranscriptorEngine/Placeholder.swift`
- Create: `Sources/TranscriptorEngine/ModelManager.swift`
- Create: `Sources/TranscriptorEngine/WhisperKitEngine.swift`
- Delete: `Tests/TranscriptorEngineTests/EngineSmokeTests.swift`
- Create: `Tests/TranscriptorEngineTests/ModelManagerTests.swift`
- Create: `Tests/TranscriptorEngineTests/WhisperKitEngineIntegrationTests.swift`

**Interfaces:**
- Consumes: `TranscriptionEngine`, `TranscriptionOutput`, `Segment`, `ModelChoice`, `TranscriptionError` from Core.
- Produces:
  - `struct ModelManager: Sendable { let downloadBase: URL; static func defaultBase() -> URL; init(downloadBase:); func folder(for: ModelChoice) -> URL; func isDownloaded(_:) -> Bool; func download(_:progress:) async throws -> URL }`
  - `final class WhisperKitEngine: TranscriptionEngine, @unchecked Sendable { init(modelManager:) }`

- [ ] **Step 1: Add the WhisperKit dependency**

In `Package.swift` replace `dependencies: [],` with:
```swift
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.0"),
    ],
```
and the engine target with:
```swift
        .target(
            name: "TranscriptorEngine",
            dependencies: [
                "TranscriptorCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
```

Run: `swift package resolve`
Expected: `Package.resolved` created, WhisperKit 1.1.0 fetched (it also pulls swift-argument-parser, vapor and openapi packages for its CLI; those targets are never built by us). Commit `Package.resolved`.

- [ ] **Step 2: Write the ModelManager test (fast, no network)**

Delete `Tests/TranscriptorEngineTests/EngineSmokeTests.swift` and `Sources/TranscriptorEngine/Placeholder.swift`.

`Tests/TranscriptorEngineTests/ModelManagerTests.swift`:
```swift
import Foundation
import Testing
import TranscriptorCore
@testable import TranscriptorEngine

@Suite struct ModelManagerTests {
    @Test func folderFollowsHuggingFaceLayout() {
        let base = URL(fileURLWithPath: "/tmp/base")
        let m = ModelManager(downloadBase: base)
        #expect(m.folder(for: .rapido).path == "/tmp/base/models/argmaxinc/whisperkit-coreml/openai_whisper-small")
        #expect(m.folder(for: .preciso).path == "/tmp/base/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3_turbo")
    }

    @Test func isDownloadedRequiresDecoderAndConfig() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ModelManagerTests-\(UUID().uuidString)")
        let m = ModelManager(downloadBase: base)
        #expect(!m.isDownloaded(.rapido))
        let folder = m.folder(for: .rapido)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("TextDecoder.mlmodelc"), withIntermediateDirectories: true)
        #expect(!m.isDownloaded(.rapido))
        try "{}".write(to: folder.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        #expect(m.isDownloaded(.rapido))
    }

    @Test func defaultBaseIsApplicationSupport() {
        let base = ModelManager.defaultBase()
        #expect(base.path.hasSuffix("/Library/Application Support/Transcriptor"))
    }
}
```

- [ ] **Step 3: Write the gated integration test**

`Tests/TranscriptorEngineTests/WhisperKitEngineIntegrationTests.swift`:
```swift
import Foundation
import Testing
import TranscriptorCore
@testable import TranscriptorEngine

/// Runs only with TRANSCRIPTOR_INTEGRATION=1 (make test-integration). Downloads the small model once
/// into the real Application Support folder and synthesizes a Spanish clip with macOS `say`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TRANSCRIPTOR_INTEGRATION"] == "1"))
struct WhisperKitEngineIntegrationTests {
    static let sentence = "Hoy vamos a revisar el manejo de la hipokalemia en el paciente con enalapril y espironolactona."

    func makeClip() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Paulina", "-r", "185", "-o", url.path, Self.sentence]
        try say.run()
        say.waitUntilExit()
        #expect(say.terminationStatus == 0)
        return url
    }

    @Test func transcribesSpanishAndHonorsGlossaryPrompt() async throws {
        let engine = WhisperKitEngine(modelManager: ModelManager())
        try await engine.prepare(model: .rapido) { _ in }
        let clip = try makeClip()

        let plain = try await engine.transcribe(fileURL: clip, prompt: nil) { _ in }
        #expect(plain.audioDuration > 4 && plain.audioDuration < 12)
        let plainText = plain.segments.map(\.text).joined(separator: " ").lowercased()
        #expect(plainText.contains("potasio") || plainText.contains("kalemia") || plainText.contains("calemia"))
        #expect(plainText.contains("espironolactona"))

        let prompted = try await engine.transcribe(
            fileURL: clip,
            prompt: "Clase de medicina. Términos: hipokalemia, enalapril, espironolactona.",
            progress: { _ in }
        )
        let promptedText = prompted.segments.map(\.text).joined(separator: " ").lowercased()
        #expect(promptedText.contains("hipokalemia"))
        #expect(promptedText.contains("enalapril"))
        #expect(prompted.segments.allSatisfy { !$0.text.contains("<|") })
    }

    @Test func tokenCountIsPositiveForText() async throws {
        let engine = WhisperKitEngine(modelManager: ModelManager())
        try await engine.prepare(model: .rapido) { _ in }
        let n = await engine.tokenCount("Clase de medicina. Términos: hipokalemia.")
        #expect(n > 5 && n < 40)
    }

    @Test func cancelStopsAndThrowsCancelled() async throws {
        let engine = WhisperKitEngine(modelManager: ModelManager())
        try await engine.prepare(model: .rapido) { _ in }
        let clip = try makeClip()
        let task = Task { try await engine.transcribe(fileURL: clip, prompt: nil) { _ in } }
        try await Task.sleep(nanoseconds: 100_000_000)
        await engine.cancel()
        do {
            _ = try await task.value
            // A clip this short may finish before the cancel lands; that is acceptable.
        } catch let error as TranscriptionError {
            #expect(error == .cancelled)
        }
    }
}
```

- [ ] **Step 4: Run the fast tests to verify the model manager test fails**

Run: `make test`
Expected: compile error `cannot find 'ModelManager'`. (The `--skip TranscriptorEngineTests` only skips running; it still compiles.)

- [ ] **Step 5: Implement ModelManager**

`Sources/TranscriptorEngine/ModelManager.swift`:
```swift
import Foundation
import TranscriptorCore
import WhisperKit

/// Knows where models live on disk and downloads them from Hugging Face.
public struct ModelManager: Sendable {
    public static let repo = "argmaxinc/whisperkit-coreml"

    public let downloadBase: URL

    public static func defaultBase() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Transcriptor", isDirectory: true)
    }

    public init(downloadBase: URL = ModelManager.defaultBase()) {
        self.downloadBase = downloadBase
    }

    /// Matches WhisperKit's Hub cache layout: <base>/models/<repo>/<variant>.
    public func folder(for model: ModelChoice) -> URL {
        downloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(ModelManager.repo, isDirectory: true)
            .appendingPathComponent(model.whisperVariant, isDirectory: true)
    }

    public func isDownloaded(_ model: ModelChoice) -> Bool {
        let folder = folder(for: model)
        let fm = FileManager.default
        return fm.fileExists(atPath: folder.appendingPathComponent("TextDecoder.mlmodelc").path)
            && fm.fileExists(atPath: folder.appendingPathComponent("config.json").path)
    }

    /// Downloads the model files. `progress` is 0...1. Resumable by the underlying Hub client.
    public func download(_ model: ModelChoice, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        do {
            try FileManager.default.createDirectory(at: downloadBase, withIntermediateDirectories: true)
            return try await WhisperKit.download(
                variant: model.whisperVariant,
                downloadBase: downloadBase,
                from: ModelManager.repo,
                progressCallback: { p in progress(p.fractionCompleted) }
            )
        } catch {
            throw TranscriptionError.modelDownloadFailed(String(describing: error))
        }
    }
}
```

- [ ] **Step 6: Implement WhisperKitEngine**

`Sources/TranscriptorEngine/WhisperKitEngine.swift`:
```swift
import AVFoundation
import Foundation
import os
import TranscriptorCore
import WhisperKit

/// WhisperKit adapter. JobQueue calls it strictly sequentially, so a single loaded model
/// guarded by `stateLock` is enough; `@unchecked Sendable` because WhisperKit's class is not Sendable.
public final class WhisperKitEngine: TranscriptionEngine, @unchecked Sendable {
    private let modelManager: ModelManager
    private let cancelFlag = OSAllocatedUnfairLock(initialState: false)
    // withLockUnchecked because LoadedState holds a non-Sendable WhisperKit instance.
    private let stateLock = OSAllocatedUnfairLock(initialState: LoadedState())

    private struct LoadedState {
        var whisperKit: WhisperKit?
        var model: ModelChoice?
    }

    public init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    // MARK: TranscriptionEngine

    public func prepare(model: ModelChoice, progress: @escaping @Sendable (Double) -> Void) async throws {
        let current = stateLock.withLockUnchecked { $0 }
        if current.model == model, current.whisperKit != nil {
            progress(1)
            return
        }

        let folder: URL
        if modelManager.isDownloaded(model) {
            folder = modelManager.folder(for: model)
        } else {
            folder = try await modelManager.download(model) { progress($0 * 0.9) }
        }

        if let old = current.whisperKit {
            await old.unloadModels()
            stateLock.withLockUnchecked { $0 = LoadedState() }
        }

        let config = WhisperKitConfig(
            model: model.whisperVariant,
            downloadBase: modelManager.downloadBase,
            modelFolder: folder.path,
            tokenizerFolder: modelManager.downloadBase,
            computeOptions: computeOptions(for: model),
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        progress(0.9)
        let loaded: WhisperKit
        do {
            loaded = try await WhisperKit(config)
        } catch {
            throw TranscriptionError.modelLoadFailed(String(describing: error))
        }
        stateLock.withLockUnchecked { $0 = LoadedState(whisperKit: loaded, model: model) }
        progress(1)
    }

    public func transcribe(fileURL: URL, prompt: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> TranscriptionOutput {
        let state = stateLock.withLockUnchecked { $0 }
        guard let whisperKit = state.whisperKit, let model = state.model else {
            throw TranscriptionError.modelLoadFailed("El modelo no está cargado.")
        }
        cancelFlag.withLock { $0 = false }

        let duration = try await audioDuration(of: fileURL)

        var options = DecodingOptions()
        options.task = .transcribe
        options.language = "es"
        options.detectLanguage = false
        options.usePrefillPrompt = true
        options.skipSpecialTokens = true
        options.withoutTimestamps = false
        options.wordTimestamps = false
        options.chunkingStrategy = .vad
        options.concurrentWorkerCount = model.concurrentWorkers
        options.compressionRatioThreshold = 2.4
        options.logProbThreshold = -1.0
        options.noSpeechThreshold = 0.6
        if let prompt, let tokenizer = whisperKit.tokenizer {
            let trimmed = prompt.trimmingCharacters(in: .whitespaces)
            options.promptTokens = tokenizer.encode(text: " " + trimmed)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }

        let cancelFlag = self.cancelFlag
        nonisolated(unsafe) let overall = whisperKit.progress
        let results: [TranscriptionResult]
        do {
            results = try await whisperKit.transcribe(audioPath: fileURL.path, decodeOptions: options) { _ in
                progress(min(0.99, overall.fractionCompleted))
                return cancelFlag.withLock { $0 } ? false : nil
            }
        } catch {
            if cancelFlag.withLock({ $0 }) { throw TranscriptionError.cancelled }
            throw TranscriptionError.engineFailure(String(describing: error))
        }
        if cancelFlag.withLock({ $0 }) { throw TranscriptionError.cancelled }

        let segments = results
            .flatMap(\.segments)
            .sorted { $0.start < $1.start }
            .map { s in
                Segment(
                    start: TimeInterval(s.start),
                    end: TimeInterval(s.end),
                    text: Self.stripSpecialTokens(s.text),
                    avgLogprob: s.avgLogprob,
                    noSpeechProb: s.noSpeechProb,
                    compressionRatio: s.compressionRatio
                )
            }
        progress(1)
        return TranscriptionOutput(segments: segments, audioDuration: duration)
    }

    public func tokenCount(_ text: String) async -> Int {
        guard let tokenizer = stateLock.withLockUnchecked({ $0.whisperKit })?.tokenizer else {
            // Rough fallback before a model is loaded: Whisper averages ~1.3 tokens per Spanish word.
            return Int(Double(text.split(separator: " ").count) * 1.3) + 1
        }
        return tokenizer.encode(text: " " + text).count
    }

    public func cancel() async {
        cancelFlag.withLock { $0 = true }
    }

    // MARK: Helpers

    private func computeOptions(for model: ModelChoice) -> ModelComputeOptions {
        switch model {
        case .preciso:
            ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine, textDecoderCompute: .cpuAndGPU)
        case .rapido:
            ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine, textDecoderCompute: .cpuAndNeuralEngine)
        }
    }

    private func audioDuration(of url: URL) async throws -> TimeInterval {
        do {
            let asset = AVURLAsset(url: url)
            let time = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite, seconds > 0 else { throw TranscriptionError.fileUnreadable(url.lastPathComponent) }
            return seconds
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.fileUnreadable(url.lastPathComponent)
        }
    }

    /// Removes any leftover "<|...|>" markers from segment text.
    static func stripSpecialTokens(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
```

If the compiler rejects `nonisolated(unsafe) let overall`, replace that line with `let overall = whisperKit.progress` (Foundation.Progress is thread-safe; the annotation only silences the Sendable check).

- [ ] **Step 7: Run the fast tests**

Run: `make test`
Expected: first run compiles WhisperKit (about 2 minutes), then all Core tests plus the 3 ModelManager tests pass. Engine integration tests are reported as skipped.

- [ ] **Step 8: Run the integration test**

Run: `make test-integration`
Expected: first run downloads the small model (~0.5 GB) and compiles it (~1 minute); all 3 integration tests pass. Second run should finish in under a minute. If `transcribesSpanishAndHonorsGlossaryPrompt` fails only on the `hipokalemia` expectation, print `promptedText` and check whether the term appears with a different spelling; if the prompt is not being honored at all, check `options.usePrefillPrompt = true` is set and that `promptTokens` is non-empty.

- [ ] **Step 9: Commit**

```bash
git add Package.swift Package.resolved Sources/TranscriptorEngine Tests/TranscriptorEngineTests
git rm -q Sources/TranscriptorEngine/Placeholder.swift Tests/TranscriptorEngineTests/EngineSmokeTests.swift 2>/dev/null || true
git commit -m "feat(engine): WhisperKit adapter and model manager with gated integration test"
```

---

### Task 10: App shell — AppState, main window, adding files

**Files:**
- Delete: `Sources/Transcriptor/main.swift`
- Create: `Sources/Transcriptor/TranscriptorApp.swift`
- Create: `Sources/Transcriptor/AppDelegate.swift`
- Create: `Sources/Transcriptor/AppState.swift`
- Create: `Sources/Transcriptor/AppLog.swift`
- Create: `Sources/Transcriptor/Views/ContentView.swift`
- Create: `Sources/Transcriptor/Views/SidebarView.swift`
- Create: `Sources/Transcriptor/Views/JobRowView.swift`
- Create: `Sources/Transcriptor/Views/TranscriptDetailView.swift`
- Create: `Sources/Transcriptor/Views/EmptyStateView.swift`
- Create: `Sources/Transcriptor/FilePanels.swift`

**Interfaces:**
- Consumes: `JobQueue`, `Job`, `Library`, `Settings`, `Transcript`, `WhisperKitEngine`, `ModelManager`.
- Produces: `@MainActor @Observable final class AppState { settings, library, queue, transcripts, selection: SidebarItem?, pendingAlert: String?, needsModelDownload: Bool; addFiles(_:); refreshLibrary(); openFilesPanel() }`, `enum SidebarItem: Hashable { case job(UUID), transcript(UUID) }`.

- [ ] **Step 1: App entry, delegate and logging**

Delete `Sources/Transcriptor/main.swift`.

`Sources/Transcriptor/TranscriptorApp.swift`:
```swift
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
```

`Sources/Transcriptor/AppDelegate.swift`:
```swift
import AppKit

/// Receives files opened from Finder ("Abrir con Transcriptor") and forwards them to the queue.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var state: AppState?

    func application(_ application: NSApplication, open urls: [URL]) {
        state?.addFiles(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
```

`Sources/Transcriptor/AppLog.swift`:
```swift
import Foundation
import os

/// os.Logger plus an append-only file at ~/Library/Logs/Transcriptor/transcriptor.log (rotated at 5 MB).
enum AppLog {
    static let logger = Logger(subsystem: "com.jac.transcriptor", category: "app")
    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Transcriptor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("transcriptor.log")
    }()
    private static let queue = DispatchQueue(label: "com.jac.transcriptor.log")

    static func info(_ message: String) { write("INFO", message); logger.info("\(message, privacy: .public)") }
    static func error(_ message: String) { write("ERROR", message); logger.error("\(message, privacy: .public)") }

    private static func write(_ level: String, _ message: String) {
        queue.async {
            rotateIfNeeded()
            let line = "\(ISO8601DateFormatter().string(from: Date())) \(level) \(message)\n"
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func rotateIfNeeded() {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        guard size > 5_000_000 else { return }
        let old = fileURL.deletingPathExtension().appendingPathExtension("old.log")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: fileURL, to: old)
    }
}
```

- [ ] **Step 2: AppState**

`Sources/Transcriptor/AppState.swift`:
```swift
import Foundation
import Observation
import TranscriptorCore
import TranscriptorEngine

enum SidebarItem: Hashable {
    case job(UUID)
    case transcript(UUID)
}

@MainActor @Observable
final class AppState {
    let settings: Settings
    let modelManager: ModelManager
    let engine: WhisperKitEngine
    private(set) var library: Library
    let queue: JobQueue

    var transcripts: [Transcript] = []
    var selection: SidebarItem?
    /// One-line Spanish message shown in an alert, then cleared.
    var pendingAlert: String?
    var needsModelDownload = false

    init() {
        let settings = Settings()
        let modelManager = ModelManager()
        let engine = WhisperKitEngine(modelManager: modelManager)
        let library = Library(folder: settings.libraryFolder)
        self.settings = settings
        self.modelManager = modelManager
        self.engine = engine
        self.library = library
        self.queue = JobQueue(engine: engine, library: library, settings: settings)
        try? library.ensureExists()
        queue.onTranscriptSaved = { [weak self] transcript in
            self?.refreshLibrary()
            self?.selection = .transcript(transcript.id)
            AppLog.info("Transcripción guardada: \(transcript.title)")
        }
        queue.onJobFailed = { job, message in
            AppLog.error("Falló \(job.fileURL.lastPathComponent): \(message)")
        }
        refreshLibrary()
        needsModelDownload = !modelManager.isDownloaded(settings.modelChoice)
        AppLog.info("Inicio. Modelo: \(settings.modelChoice.rawValue). Carpeta: \(library.folder.path)")
    }

    func refreshLibrary() {
        transcripts = library.list()
    }

    func addFiles(_ urls: [URL]) {
        let rejections = queue.add(urls)
        if let first = queue.jobs.last(where: { !$0.isFinished }), selection == nil {
            selection = .job(first.id)
        }
        if !rejections.isEmpty {
            pendingAlert = rejections.joined(separator: "\n\n")
            AppLog.info("Archivos rechazados: \(rejections.count)")
        }
    }

    func openFilesPanel() {
        addFiles(FilePanels.chooseAudioFiles())
    }

    func transcript(for item: SidebarItem?) -> Transcript? {
        switch item {
        case .transcript(let id):
            return transcripts.first { $0.id == id }
        case .job(let id):
            if case .done(let t) = queue.jobs.first(where: { $0.id == id })?.state { return t }
            return nil
        case nil:
            return nil
        }
    }
}
```

- [ ] **Step 3: File panels**

`Sources/Transcriptor/FilePanels.swift`:
```swift
import AppKit
import TranscriptorCore
import UniformTypeIdentifiers

@MainActor
enum FilePanels {
    static func chooseAudioFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Agregar audios"
        panel.prompt = "Agregar"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = SupportedAudio.extensions.compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.urls : []
    }

    /// Returns the chosen destination or nil if cancelled.
    static func chooseExportDestination(suggestedName: String, format: ExportFormat) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Exportar transcripción"
        panel.nameFieldStringValue = suggestedName + "." + format.fileExtension
        panel.allowedContentTypes = [format.contentType]
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFolder(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown, plainText
    var id: String { rawValue }
    var label: String {
        switch self {
        case .markdown: "Markdown (.md)"
        case .plainText: "Texto plano (.txt)"
        }
    }
    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .plainText: "txt"
        }
    }
    var contentType: UTType {
        switch self {
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        case .plainText: .plainText
        }
    }
}
```

- [ ] **Step 4: Views**

`Sources/Transcriptor/Views/ContentView.swift`:
```swift
import SwiftUI
import TranscriptorCore

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            SidebarView(selection: $state.selection)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            if let transcript = state.transcript(for: state.selection) {
                TranscriptDetailView(transcript: transcript)
            } else if case .job(let id) = state.selection, let job = state.queue.jobs.first(where: { $0.id == id }) {
                EmptyStateView(
                    systemImage: "waveform",
                    title: job.fileURL.lastPathComponent,
                    message: job.stateText
                )
            } else if state.transcripts.isEmpty && state.queue.jobs.isEmpty {
                EmptyStateView(
                    systemImage: "square.and.arrow.down.on.square",
                    title: "Arrastra aquí los audios de tus clases",
                    message: "O usa el botón Agregar audios. Formatos: m4a, mp3, wav, mp4 y otros."
                )
            } else {
                EmptyStateView(systemImage: "doc.text", title: "Selecciona una transcripción", message: "")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { state.openFilesPanel() } label: { Label("Agregar audios", systemImage: "plus") }
                    .help("Agregar archivos de audio a la cola")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            state.addFiles(urls)
            return true
        }
        .alert("Atención", isPresented: Binding(get: { state.pendingAlert != nil }, set: { if !$0 { state.pendingAlert = nil } })) {
            Button("Entendido") { state.pendingAlert = nil }
        } message: {
            Text(state.pendingAlert ?? "")
        }
    }
}
```

`Sources/Transcriptor/Views/SidebarView.swift`:
```swift
import SwiftUI
import TranscriptorCore

struct SidebarView: View {
    @Environment(AppState.self) private var state
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            if !state.queue.jobs.isEmpty {
                Section("En proceso") {
                    ForEach(state.queue.jobs) { job in
                        JobRowView(job: job).tag(SidebarItem.job(job.id))
                    }
                }
            }
            Section("Transcripciones") {
                if state.transcripts.isEmpty {
                    Text("Todavía no hay transcripciones.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                ForEach(state.transcripts) { transcript in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transcript.title).lineLimit(1)
                        Text("\(transcript.createdAt.formatted(date: .abbreviated, time: .omitted)) · \(Timestamp.duration(transcript.audioDuration))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(SidebarItem.transcript(transcript.id))
                }
            }
        }
        .listStyle(.sidebar)
    }
}
```

`Sources/Transcriptor/Views/JobRowView.swift`:
```swift
import SwiftUI
import TranscriptorCore

struct JobRowView: View {
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.fileURL.lastPathComponent).lineLimit(1)
            switch job.state {
            case .loadingModel(let p), .transcribing(let p):
                ProgressView(value: p).controlSize(.small)
                Text(job.stateText).font(.caption).foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red).lineLimit(3)
            default:
                Text(job.stateText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
```

`Sources/Transcriptor/Views/TranscriptDetailView.swift`:
```swift
import SwiftUI
import TranscriptorCore

struct TranscriptDetailView: View {
    let transcript: Transcript
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transcript.title).font(.title2.bold())
                Text(transcript.metadataLine).font(.callout).foregroundStyle(.secondary)
            }
            .padding()
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if transcript.paragraphs.isEmpty {
                        Text(Transcript.noSpeechNotice).foregroundStyle(.secondary)
                    }
                    ForEach(Array(transcript.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Timestamp.bracket(paragraph.start))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(highlighted(paragraph.text))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding()
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Buscar en la transcripción")
    }

    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return attributed }
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            if let lower = AttributedString.Index(found.lowerBound, within: attributed),
               let upper = AttributedString.Index(found.upperBound, within: attributed) {
                attributed[lower..<upper].backgroundColor = .yellow.opacity(0.6)
            }
            searchRange = found.upperBound..<text.endIndex
        }
        return attributed
    }
}
```

`Sources/Transcriptor/Views/EmptyStateView.swift`:
```swift
import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(title).font(.title3)
            if !message.isEmpty {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: Build and run manually**

Run: `swift build -c release && .build/release/Transcriptor`
Expected: a window titled Transcriptor opens with the empty-state message. Running the bare binary (not yet a bundle) may show no Dock icon and no menu bar; that is fine for this check. Press ⌘Q or Ctrl-C to quit. If the window does not appear, check the process is not crashing on `Settings()` (look for output in the terminal).

Manual check: drag a `.pdf` onto the window → an alert lists the rejected format. Drag an `.m4a` → a job row appears in "En proceso" with "Cargando modelo…" (the model may start downloading; that is expected and verifies the wiring; you can quit).

- [ ] **Step 6: Commit**

```bash
git add Sources/Transcriptor
git rm -q Sources/Transcriptor/main.swift 2>/dev/null || true
git commit -m "feat(app): SwiftUI shell with sidebar, detail view and file intake"
```

---

### Task 11: Model download screen, settings, glossary editor, export, re-apply

**Files:**
- Modify: `Sources/Transcriptor/AppState.swift`
- Modify: `Sources/Transcriptor/Views/ContentView.swift`
- Create: `Sources/Transcriptor/Views/ModelDownloadView.swift`
- Create: `Sources/Transcriptor/Views/SettingsSheet.swift`
- Create: `Sources/Transcriptor/Views/GlossarySheet.swift`

**Interfaces:**
- Consumes: `AppState`, `Glossary`, `TranscriptPipeline.reapply`, `Library.save`, `FilePanels`, `ExportFormat`.
- Produces on `AppState`: `downloadProgress: Double?`, `downloadError: String?`, `showSettings`, `showGlossary`, `func prepareModel() async`, `func export(_:as:)`, `func revealLibraryFolder()`, `func reapplyGlossary(to:)`, `func changeLibraryFolder(_:)`, `func glossaryParseErrors(_:) -> [Glossary.ParseError]`.

- [ ] **Step 1: Extend AppState**

Add these properties and methods to `AppState` (inside the class):
```swift
    var downloadProgress: Double?
    var downloadError: String?
    var showSettings = false
    var showGlossary = false

    /// Downloads and loads the selected model, driving the first-launch screen.
    func prepareModel() async {
        downloadError = nil
        downloadProgress = 0
        do {
            try await engine.prepare(model: settings.modelChoice) { [weak self] p in
                Task { @MainActor in self?.downloadProgress = p }
            }
            needsModelDownload = false
            downloadProgress = nil
            AppLog.info("Modelo listo: \(settings.modelChoice.rawValue)")
        } catch {
            let message = TranscriptionError.message(for: error)
            downloadError = message
            downloadProgress = nil
            AppLog.error("Fallo al preparar modelo: \(message)")
        }
    }

    func modelChoiceChanged() {
        needsModelDownload = !modelManager.isDownloaded(settings.modelChoice)
    }

    func export(_ transcript: Transcript, as format: ExportFormat) {
        guard let destination = FilePanels.chooseExportDestination(suggestedName: Library.sanitizedStem(transcript.title), format: format) else { return }
        let content = format == .markdown ? transcript.renderMarkdown() : transcript.renderPlainText()
        do {
            try content.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            pendingAlert = "No se pudo guardar el archivo: \(error.localizedDescription)"
            AppLog.error("Exportar falló: \(error)")
        }
    }

    func revealLibraryFolder() {
        try? library.ensureExists()
        FilePanels.reveal(library.folder)
    }

    func reapplyGlossary(to transcript: Transcript) {
        let glossary = Glossary(text: library.loadGlossaryText())
        let updated = TranscriptPipeline.reapply(glossary: glossary, to: transcript)
        do {
            _ = try library.save(updated)
            refreshLibrary()
            selection = .transcript(updated.id)
        } catch {
            pendingAlert = "No se pudo guardar la transcripción corregida: \(error.localizedDescription)"
        }
    }

    func changeLibraryFolder(_ url: URL) {
        settings.libraryFolder = url
        library = Library(folder: url)
        queue.library = library
        try? library.ensureExists()
        refreshLibrary()
        AppLog.info("Carpeta cambiada: \(url.path)")
    }

    func loadGlossaryText() -> String { library.loadGlossaryText() }

    func saveGlossaryText(_ text: String) {
        do {
            try library.saveGlossaryText(text)
        } catch {
            pendingAlert = "No se pudo guardar el glosario: \(error.localizedDescription)"
        }
    }
```

`JobQueue.library` is a public var (Task 8) so new jobs save to the new folder after `changeLibraryFolder`. Cover it with a `JobQueueTests` case:
```swift
    @Test func changingLibrarySavesNewJobsThere() async throws {
        let engine = FakeEngine()
        let (queue, _) = try makeQueue(engine: engine)
        let other = Library(folder: FileManager.default.temporaryDirectory.appendingPathComponent("JobQueueTests-other-\(UUID().uuidString)"))
        try other.ensureExists()
        queue.library = other
        let a = try touch("a.m4a")
        await engine.set(a.lastPathComponent, .success(output))
        queue.add([a])
        await queue.waitUntilIdle()
        #expect(other.list().count == 1)
    }
```

- [ ] **Step 2: Model download view**

`Sources/Transcriptor/Views/ModelDownloadView.swift`:
```swift
import SwiftUI
import TranscriptorCore

/// Shown as a sheet when the selected model is not on disk yet.
struct ModelDownloadView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle").font(.system(size: 40)).foregroundStyle(.tint)
            Text("Descargando el modelo de transcripción").font(.title3.bold())
            Text("Esto pasa una sola vez. \(state.settings.modelChoice.detailText). Después de esto la app funciona sin internet.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let p = state.downloadProgress {
                ProgressView(value: p) {
                    Text(p < 0.9 ? "Descargando… \(Int(p * 100))%" : "Preparando el modelo (puede tomar un par de minutos)…")
                }
                .frame(width: 360)
            }
            if let error = state.downloadError {
                Text(error).foregroundStyle(.red).multilineTextAlignment(.center).frame(width: 380)
                Button("Reintentar") { Task { await state.prepareModel() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 460)
        .task { if state.downloadProgress == nil && state.downloadError == nil { await state.prepareModel() } }
        .interactiveDismissDisabled(true)
    }
}
```

- [ ] **Step 3: Settings sheet**

`Sources/Transcriptor/Views/SettingsSheet.swift`:
```swift
import SwiftUI
import TranscriptorCore

struct SettingsSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = state.settings
        VStack(alignment: .leading, spacing: 20) {
            Text("Ajustes").font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("Modelo").font(.headline)
                Picker("Modelo", selection: $settings.modelChoice) {
                    ForEach(ModelChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(settings.modelChoice.detailText).font(.callout).foregroundStyle(.secondary)
                if !state.modelManager.isDownloaded(settings.modelChoice) {
                    Text("Este modelo aún no está descargado. Se descargará al cerrar los ajustes.")
                        .font(.callout).foregroundStyle(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Carpeta de transcripciones").font(.headline)
                HStack {
                    Text(state.library.folder.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cambiar…") {
                        if let url = FilePanels.chooseFolder(title: "Elegir carpeta de transcripciones") {
                            state.changeLibraryFolder(url)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Listo") {
                    state.modelChoiceChanged()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
```

- [ ] **Step 4: Glossary sheet**

`Sources/Transcriptor/Views/GlossarySheet.swift`:
```swift
import SwiftUI
import TranscriptorCore

struct GlossarySheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    /// The transcript to re-correct after saving, if any.
    let currentTranscript: Transcript?

    private var parsed: Glossary { Glossary(text: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Glosario").font(.title2.bold())
            Text("Un término por línea. Para corregir algo que el modelo escribe mal: `incorrecto => correcto`. Las líneas con # son comentarios.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 320)
                .border(.separator)
            HStack {
                Text("\(parsed.terms.count) términos · \(parsed.corrections.count) correcciones")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            if !parsed.parseErrors.isEmpty {
                ForEach(parsed.parseErrors, id: \.line) { error in
                    Text("Línea \(error.line): \(error.message)").font(.caption).foregroundStyle(.red)
                }
            }
            if state.queue.lastPromptTruncated {
                Text("El glosario es largo: solo los primeros términos se usan para guiar al modelo. Las correcciones se aplican siempre.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if let transcript = currentTranscript {
                    Button("Guardar y re-aplicar a \"\(transcript.title)\"") {
                        state.saveGlossaryText(text)
                        state.reapplyGlossary(to: transcript)
                        dismiss()
                    }
                }
                Button("Guardar") {
                    state.saveGlossaryText(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620, height: 560)
        .onAppear { text = state.loadGlossaryText() }
    }
}
```

- [ ] **Step 5: Wire sheets and toolbar into ContentView**

In `ContentView`, replace the `.toolbar { ... }` block with:
```swift
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { state.openFilesPanel() } label: { Label("Agregar audios", systemImage: "plus") }
                    .help("Agregar archivos de audio a la cola")
                if let transcript = state.transcript(for: state.selection) {
                    Menu {
                        ForEach(ExportFormat.allCases) { format in
                            Button(format.label) { state.export(transcript, as: format) }
                        }
                    } label: { Label("Exportar", systemImage: "square.and.arrow.up") }
                    .help("Guardar la transcripción como archivo")
                    Button { state.reapplyGlossary(to: transcript) } label: { Label("Re-aplicar glosario", systemImage: "arrow.triangle.2.circlepath") }
                        .help("Volver a aplicar las correcciones del glosario a esta transcripción")
                }
                Button { state.revealLibraryFolder() } label: { Label("Abrir carpeta", systemImage: "folder") }
                    .help("Mostrar la carpeta de transcripciones en el Finder")
                Button { state.showGlossary = true } label: { Label("Glosario", systemImage: "text.book.closed") }
                Button { state.showSettings = true } label: { Label("Ajustes", systemImage: "gearshape") }
            }
        }
        .sheet(isPresented: $state.needsModelDownload) { ModelDownloadView().environment(state) }
        .sheet(isPresented: $state.showSettings) { SettingsSheet().environment(state) }
        .sheet(isPresented: $state.showGlossary) { GlossarySheet(currentTranscript: state.transcript(for: state.selection)).environment(state) }
```

Also add a "Cancelar todo" button that appears while jobs are active:
```swift
            ToolbarItemGroup(placement: .navigation) {
                if state.queue.jobs.contains(where: { !$0.isFinished }) {
                    Button("Cancelar todo") { Task { await state.queue.cancelAll() } }
                }
                if state.queue.jobs.contains(where: \.isFinished) {
                    Button("Limpiar listos") { state.queue.clearFinished() }
                }
            }
```

- [ ] **Step 6: Run fast tests, then build and run manually**

Run: `make test`
Expected: all pass including the new `changingLibrarySavesNewJobsThere`.

Run: `swift build -c release && .build/release/Transcriptor`
Manual checks, in order:
1. First launch with no model: the download sheet appears and progresses; when done it closes. If the small model was downloaded by the integration test, switch to Rápido in settings first to test the no-download path, then to Preciso to see a real download.
2. Drag two `.m4a` files. Rows show "Cargando modelo…" then "Transcribiendo… NN%", then "Listo". The transcript appears in the sidebar and is selected.
3. Search for a word: matches highlight.
4. Exportar → Markdown: file saved where chosen, opens in a text editor with title, metadata and timestamps.
5. Glosario: add `hipocalemia => hipokalemia`, "Guardar y re-aplicar": the selected transcript updates.
6. Abrir carpeta reveals the folder in Finder with `.md` and `.transcriptor.json` files.
7. Quit and relaunch: the library still lists the transcripts.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat(app): model download, settings, glossary editor, export and re-apply"
```

---

### Task 12: App bundle, icon, signing, zip, Spanish README

**Files:**
- Create: `scripts/Info.plist`
- Create: `scripts/render-icon.swift`
- Create: `scripts/make-icon.sh`
- Create: `scripts/make-app.sh`
- Create: `README.md`
- Modify: `.gitignore` (already ignores `dist/` and `.build/`)

**Interfaces:**
- Consumes: `make build` output at `.build/release/Transcriptor`.
- Produces: `dist/Transcriptor.app`, `dist/Transcriptor-<version>.zip`.

- [ ] **Step 1: Info.plist template**

`scripts/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>es</string>
    <key>CFBundleExecutable</key><string>Transcriptor</string>
    <key>CFBundleIdentifier</key><string>com.jac.transcriptor</string>
    <key>CFBundleName</key><string>Transcriptor</string>
    <key>CFBundleDisplayName</key><string>Transcriptor</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>__VERSION__</string>
    <key>CFBundleVersion</key><string>__VERSION__</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>Uso personal.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Audio</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.audio</string>
                <string>public.movie</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: Icon renderer (Swift script, CoreGraphics only)**

`scripts/render-icon.swift`:
```swift
// Usage: swift scripts/render-icon.swift out.png
// Draws a 1024x1024 rounded square with a gradient and white waveform bars.
import AppKit

let size = 1024.0
let out = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.06, dy: size * 0.06)
let path = CGPath(roundedRect: rect, cornerWidth: size * 0.22, cornerHeight: size * 0.22, transform: nil)
ctx.addPath(path)
ctx.clip()
let colors = [CGColor(red: 0.07, green: 0.42, blue: 0.55, alpha: 1), CGColor(red: 0.10, green: 0.66, blue: 0.62, alpha: 1)] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Waveform bars
let heights: [CGFloat] = [0.18, 0.32, 0.52, 0.72, 0.46, 0.60, 0.30, 0.20]
let barWidth = size * 0.055
let gap = size * 0.035
let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
var x = (size - totalWidth) / 2
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
for h in heights {
    let barHeight = size * h
    let bar = CGRect(x: x, y: (size - barHeight) / 2, width: barWidth, height: barHeight)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    ctx.fillPath()
    x += barWidth + gap
}
image.unlockFocus()

let tiff = image.tiffRepresentation!
let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
```

`scripts/make-icon.sh`:
```bash
#!/bin/zsh
# Usage: scripts/make-icon.sh path/to/AppIcon.icns
set -euo pipefail
OUT="$1"
WORK="$(mktemp -d)"
swift "$(dirname "$0")/render-icon.swift" "$WORK/icon-1024.png"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$WORK/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$WORK"
```

- [ ] **Step 3: Bundle script**

`scripts/make-app.sh`:
```bash
#!/bin/zsh
# Assembles dist/Transcriptor.app from the release binary. No Xcode required.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
BIN=.build/release/Transcriptor
APP=dist/Transcriptor.app

[[ -x "$BIN" ]] || { echo "Falta $BIN. Corre 'make build' primero."; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Transcriptor"

# SwiftPM resource bundles (WhisperKit ships none today; copy any that appear).
for bundle in .build/release/*.bundle(N); do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

scripts/make-icon.sh "$APP/Contents/Resources/AppIcon.icns"
sed "s/__VERSION__/$VERSION/g" scripts/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Refuse to ship if anything outside the OS is dynamically linked.
if otool -L "$APP/Contents/MacOS/Transcriptor" | tail -n +2 | awk '{print $1}' | grep -vE '^(/usr/lib/|/System/Library/)'; then
  echo "ERROR: el binario enlaza librerías dinámicas que no son del sistema (ver arriba)."
  exit 1
fi

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Listo: $APP (versión $VERSION)"
```

Make both scripts executable: `chmod +x scripts/make-icon.sh scripts/make-app.sh`.

- [ ] **Step 4: Build the bundle and verify**

Run: `make app`
Expected: `Listo: dist/Transcriptor.app (versión 0.1.0)`. Then:
```bash
plutil -p dist/Transcriptor.app/Contents/Info.plist | grep -E "Identifier|Minimum|Version"
ls -la dist/Transcriptor.app/Contents/Resources/AppIcon.icns
open dist/Transcriptor.app
```
Expected: the app launches with a Dock icon (teal waveform) and a menu bar; drag-and-drop and all toolbar buttons behave as in Task 11. Quit. If `open` reports the app is damaged, run `xattr -dr com.apple.quarantine dist/Transcriptor.app` locally (this only matters for a downloaded copy; local builds are not quarantined).

Run: `make zip`
Expected: `dist/Transcriptor-0.1.0.zip` exists. Unzip it to a different folder, launch that copy; it must work identically.

- [ ] **Step 5: README in Spanish for the end user**

`README.md`:
```markdown
# Transcriptor

Transcribe clases grabadas (en español) a texto legible con marcas de tiempo, sin internet y sin costo.
Funciona en Macs con chip Apple (M1 o posterior) y macOS 14 o más nuevo.

## Instalar

1. Descomprime `Transcriptor-x.y.z.zip` y arrastra `Transcriptor.app` a la carpeta Aplicaciones.
2. La primera vez, macOS va a decir que no puede verificar la app. Haz esto una sola vez:
   - Clic derecho sobre `Transcriptor.app` → **Abrir**. Si aparece solo "Cancelar/Mover a papelera", ve a
     **Ajustes del Sistema → Privacidad y seguridad**, baja hasta el mensaje sobre Transcriptor y toca **Abrir de todos modos**.
3. Al abrir por primera vez, la app descarga el modelo de transcripción (unos 3 GB, una sola vez). Necesita internet solo para esto.
   Después de descargarlo tarda un par de minutos en prepararlo. Desde ahí funciona sin conexión.

## Usar

- Arrastra los audios a la ventana o usa **Agregar audios** (⌘O). Puedes agregar varios; se procesan uno por uno.
- Formatos aceptados: m4a, mp3, wav, aac, aiff, caf, flac, mp4, mov. Las notas de voz `.opus` de WhatsApp en Android no funcionan; conviértelas primero.
- Una clase de 90 minutos tarda unos 11 minutos en modo **Preciso** o unos 3 en modo **Rápido** (Ajustes).
- Las transcripciones se guardan solas en `Documentos/Transcripciones` como `.md`. **Exportar** guarda una copia en `.md` o `.txt` donde quieras.
- **Buscar** (arriba a la derecha) resalta palabras dentro de la transcripción.

## Glosario

El modelo se equivoca con términos médicos ("hipocalemia" en vez de "hipokalemia"). El botón **Glosario** abre una lista que puedes editar:

```
# Un término por línea ayuda al modelo a escribirlo bien:
hipokalemia
enalapril
# Una corrección reemplaza lo que sale mal por lo correcto:
hipocalemia => hipokalemia
```

**Guardar y re-aplicar** corrige la transcripción seleccionada al instante, sin volver a transcribir.
Con el tiempo el glosario va a tener los términos de sus ramos y las transcripciones saldrán cada vez mejor.

## Si algo falla

Cada archivo muestra su propio error en la lista; los demás siguen. Si algo no funciona, manda el archivo
`~/Library/Logs/Transcriptor/transcriptor.log` (en el Finder: ⇧⌘G y pega la ruta).

## Para desarrollar

Requiere solo las Command Line Tools de Apple (no Xcode).

```
make test               # pruebas rápidas
make test-integration   # descarga el modelo pequeño y transcribe un clip sintético
make app                # arma dist/Transcriptor.app
make zip                # dist/Transcriptor-<versión>.zip para compartir
```
```

- [ ] **Step 6: Commit**

```bash
chmod +x scripts/make-icon.sh scripts/make-app.sh
git add scripts README.md
git commit -m "build: app bundle, icon, ad-hoc signing, zip and Spanish README"
```

---

### Task 13: Acceptance on a real lecture

**Files:**
- Modify: `README.md` (record measured timing)
- Modify: `docs/superpowers/specs/2026-09-24-transcriber-design.md` only if a measured number in section 3 is off by more than 30%.

**Interfaces:** none; this task produces evidence.

- [ ] **Step 1: Get a real recording**

Ask the user for one real lecture recording (ideally 60–90 minutes, the actual phone recording, not re-encoded). Copy it outside the repo. Do not commit audio.

- [ ] **Step 2: Run it through the built app in Preciso mode**

Launch `dist/Transcriptor.app`, drag the file, note wall-clock time from "Transcribiendo… 0%" to "Listo". Open the resulting `.md`.

- [ ] **Step 3: Judge the output against the success criteria**

Check, and write the results as a short list in the final report:
- Time for the lecture, and minutes per 90 minutes extrapolated. Target ≤ 12 min.
- Paragraphs: no paragraph longer than ~220 words; no wall of text; no repeated hallucinated lines at silences.
- Medical terms: list the mis-heard ones; add them to `glosario.txt` as corrections; press Re-aplicar; confirm they are fixed.
- Timestamps: pick three paragraphs, seek the audio to those times, confirm the words match within a few seconds.

- [ ] **Step 4: Record and commit**

Update the "Usar" section of `README.md` with the measured minutes if they differ from 11 by more than 2 minutes. Commit:
```bash
git add README.md
git commit -m "docs: record measured transcription time on a real lecture"
```

- [ ] **Step 5: Hand over**

Run `make zip` with `VERSION=0.1.0`, send `dist/Transcriptor-0.1.0.zip` to the user along with the install steps from the README. Point out the right-click → Abrir step and the one-time download.
