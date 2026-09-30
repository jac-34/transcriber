# Transcriptor: local-LLM revision pass

Date: 2026-09-30
Status: proposal, not approved. Nothing in this document is implemented.
Builds on: `docs/superpowers/specs/2026-09-24-transcriber-design.md` (v1 spec).

## 1. Purpose

Whisper mishears medical terms, splits or joins words, and drops punctuation
in ways the glossary cannot anticipate. A second pass reads each paragraph
with its surrounding context and a local language model, and proposes
corrections a reader would make: "hipoqueratosis" to "hiperqueratosis",
"que la tosis" to "queratosis", "vaso celular" to "basocelular". The pass
runs fully offline on her Mac, after the transcription, and never blocks or
fails a transcription.

Precision beats recall. A wrong correction of a medical term is worse than a
missed one, because she will trust the corrected text more than the raw one.

## 2. Scope

### In scope

- Optional pass ("Revisión con IA"), off by default, enabled in Settings.
- Separate one-time model download (about 5 GB), same folder as the Whisper
  models, same download UI.
- Corrections applied paragraph by paragraph after glossary corrections and
  formatting. Timestamps and paragraph boundaries never change.
- Original text kept; the detail view toggles between original and revised.
- Re-run the pass on an existing transcript without re-transcribing.
- Exports use the revised text when a revision exists, and say so in the
  metadata line.

### Out of scope (this proposal)

- Summaries, study notes, restructuring, or any output longer than the input.
- Speaker labels, translation, cloud models, accounts, telemetry.
- Glossary suggestions derived from the revision (see §9, later phase).

## 3. Options considered

### 3.1 Runtime

| Option | Builds with CLT only | Memory | Quality ceiling | Verdict |
|---|---|---|---|---|
| **llama.cpp xcframework** as SwiftPM `binaryTarget` | Yes, prebuilt (the repo removed `Package.swift` in March 2025 and publishes `llama-*-xcframework.zip` per release) | Any GGUF model; 8B at Q4 fits in about 6 GB | Highest: pick any open model | **Recommended** |
| Apple Foundation Models (`import FoundationModels`) | Yes, in the macOS 26 SDK | Zero download, Apple manages it | About 3B parameters, 4,096-token window shared by input and output, Spanish medical quality unknown, requires macOS 26 and Apple Intelligence enabled | Alternative; cheap to try behind the same protocol |
| MLX Swift (`MLXLLM`) | No: shader compilation needs the Metal toolchain that ships with Xcode, not with Command Line Tools | Similar to llama.cpp | Similar | Rejected on this machine |
| Bundled `llama-server` binary spawned as a child process | Yes | Isolated process, a crash does not take the app down | Same as llama.cpp | Fallback if the framework cannot be embedded and signed cleanly |

### 3.2 Model

Candidates at the time of writing, all instruct-tuned, GGUF, one file:

- Qwen3-8B, Q4_K_M, about 5 GB. Best multilingual quality in this size class.
  Thinking mode must be disabled in the chat template.
- Gemma 3 4B, Q4_K_M, about 2.7 GB. Half the time, lower quality.
- Llama 3.1 8B Instruct, Q4_K_M, about 4.9 GB.

The spike (§8) picks one from measured precision on her lecture. Ship exactly
one model; a second "fast" tier is not worth the UI surface.

### 3.3 Output format

| Format | Cost per paragraph | Safety | Verdict |
|---|---|---|---|
| **Edit list**: lines of `mal => bien`, or `SIN CAMBIOS` | About 30 output tokens on average | Every edit is checkable: the left side must appear verbatim in the paragraph, otherwise it is dropped | **Recommended** |
| Full rewrite of the paragraph | About 400 output tokens, every paragraph | Needs edit-distance and length guards; a confident paraphrase can slip through | Alternative if the spike shows the edit list misses too much |

The edit list is the glossary's own format. Accepted edits apply through the
existing `Glossary.applyCorrections` mechanism (whole-word, case-insensitive,
lookaround regex), scoped to one paragraph, and are stored so they can later
feed glossary suggestions.

## 4. Architecture

New target `TranscriptorRevision` wraps llama.cpp behind a Core protocol. All
logic stays in Core and is unit-tested with a fake reviser, mirroring how
`TranscriptorEngine` wraps WhisperKit behind `TranscriptionEngine`.

```
TranscriptorCore
  TextReviser (protocol)          prepare / propose(edits for one window) / unload / cancel
  RevisionPass                    windows, prompt, parse, validate, apply -> Revision
  Revision, RevisionEdit          stored in Transcript (schema v2)
TranscriptorRevision
  LlamaReviser: TextReviser       llama.cpp xcframework, one context, greedy decoding
  RevisionModelManager            GGUF download, integrity check, isDownloaded
Transcriptor (app)
  Settings.revisionEnabled, download sheet, job state .revising, detail toggle
```

### 4.1 Core protocol

```swift
public protocol TextReviser: Sendable {
    /// Loads the model. `progress` is 0...1 across download and load.
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws
    /// Returns the model's raw reply for one prompt. Greedy decoding, no sampling.
    func complete(system: String, user: String, maxTokens: Int) async throws -> String
    /// Releases the model's memory.
    func unload() async
    func cancel() async
}
```

### 4.2 Data model (Transcript schema v2)

```swift
public struct RevisionEdit: Codable, Hashable, Sendable {
    public var paragraphIndex: Int
    public var wrong: String
    public var right: String
}

public struct Revision: Codable, Hashable, Sendable {
    public var modelName: String          // e.g. "Qwen3-8B Q4_K_M"
    public var createdAt: Date
    public var paragraphs: [Paragraph]    // same count and starts as Transcript.paragraphs
    public var edits: [RevisionEdit]      // accepted edits only
    public var rejectedEditCount: Int
    public var skippedParagraphCount: Int // timeouts, unparseable replies
}

// Transcript gains:
public var revision: Revision?
public var displayParagraphs: [Paragraph] { revision?.paragraphs ?? paragraphs }
```

Decoding a v1 file yields `revision == nil`. Re-applying the glossary rebuilds
`paragraphs` from segments and clears `revision`; the detail view then offers
"Revisar de nuevo". Export and rendering use `displayParagraphs`, and the
metadata line gains `· Revisado con IA (Qwen3-8B)` when a revision exists.

### 4.3 Data flow

```
JobQueue: transcribe -> HallucinationFilter -> glossary -> TranscriptFormatter -> save (unchanged)
          -> if Settings.revisionEnabled:
               engine.unload Whisper  (AsyncLock; same rule as today: never while transcribing)
               reviser.prepare
               RevisionPass.run(transcript, glossary, reviser, progress)   state .revising(0...1)
               library.save(transcript with revision)
               reviser.unload
```

The transcript is saved twice: once unrevised, once with the revision. A crash
or cancel during revision leaves a complete unrevised transcript on disk.

### 4.4 Windowing and prompt

One request per paragraph (paragraphs are at most 220 words, about 450
tokens in Spanish). Each request carries:

- System prompt (cached across the whole lecture via llama.cpp prefix reuse):
  role, rules, output format, two or three examples of real errors from her
  lectures, and the glossary terms (up to the same 200-token budget the
  Whisper prompt uses).
- User turn: lecture title, the last 60 words of the previous paragraph
  marked as read-only context, and the paragraph to review.

Rules in the system prompt, in Spanish: only fix speech-recognition errors
(medical terms, split or joined words, homophones, obvious punctuation);
never summarize, reorder, add or remove content; never change numbers, doses,
or units; keep the spoken register; reply with one `mal => bien` per line
copying `mal` exactly as it appears, or `SIN CAMBIOS`.

Decoding: temperature 0, `maxTokens` 160, per-paragraph timeout 60 s.

### 4.5 Validation (the precision guard)

An edit is accepted only if all of the following hold:

1. The line parses as `wrong => right` with both sides non-empty.
2. `wrong` occurs in the paragraph as a whole word, case-insensitive (the
   same lookaround regex as the glossary). No occurrence: dropped.
3. `right` differs from `wrong` ignoring case.
4. `right` has at most twice the characters of `wrong` plus 10, and neither
   side spans more than 6 words. Longer edits are rewrites in disguise.
5. Neither side contains digits (doses, years, percentages stay untouched).
6. `right` does not equal a glossary `wrong` term (would undo a correction the
   user asked for explicitly).

A reply with more than 8 edit lines or any line that is not an edit or
`SIN CAMBIOS` is discarded whole and the paragraph counted as skipped.
Accepted edits apply in order to that paragraph only. `rejectedEditCount` and
`skippedParagraphCount` go to the log and to the detail view's badge tooltip.

### 4.6 Memory and time

- Whisper is unloaded before the reviser loads. The reviser is loaded once per
  lecture and unloaded after. Footprint for an 8B Q4_K_M model with a 4K
  context is about 6 GB; the existing half-of-RAM guard applies unchanged.
  16 GB remains the minimum.
- Estimate for a 90-minute lecture (99 paragraphs) on the M5 Pro: prompt
  processing about 1,000 tokens plus 30 output tokens per paragraph, 3 to
  5 s each, so 5 to 8 minutes on top of Preciso's 22 minutes. The spike
  measures this; if it exceeds 10 minutes the 4B model becomes the default.
- Cancel is honored between paragraphs.

### 4.7 UI

- Settings: toggle "Revisión con IA (experimental)" with a one-line
  explanation and the download size. Turning it on without the model opens
  the download sheet (same component as the Whisper models).
- Sidebar job state: "Revisando… 43%".
- Detail view: badge "Revisado con IA · 27 cambios"; segmented control
  "Revisado / Original"; changed words underlined in the revised view
  (edits carry `wrong` and `right`, so highlighting needs no diff algorithm).
  Button "Revisar con IA" on transcripts without a revision.
- Export: the revised text; the metadata line names the model.

### 4.8 Errors

Revision never fails the job. Model missing, load failure, timeout, memory
guard, or cancel: the unrevised transcript stays saved, the job shows "Listo"
with the note "Guardado sin revisión: <motivo>" in the detail view, and the
log records the reason. Error details in Spanish, mapped in one place like
`UserFacingDetail` does today.

## 5. Distribution

- `Package.swift`: `.binaryTarget(name: "llama", url: <release xcframework zip>, checksum: ...)`
  pinned to one llama.cpp release tag, plus `TranscriptorRevision` depending
  on it.
- `scripts/make-app.sh`: copy `llama.framework` (macOS slice) into
  `Contents/Frameworks`, ad-hoc sign it before the app, keep the rpath.
- Zip grows by about 10 MB. The model is never bundled; it is downloaded from
  Hugging Face like the Whisper models, with a size and SHA-256 check.

## 6. Testing

- Core (fake reviser, no model): prompt assembly and token budget; parser
  accepts `mal => bien` and `SIN CAMBIOS`; each validation rule in §4.5 has a
  rejecting test; edits apply to one paragraph only; timestamps and paragraph
  count unchanged; schema v1 decode gives `revision == nil`; glossary reapply
  clears the revision; cancel between paragraphs returns the partial result.
- Revision target (env-gated, like `make test-integration`): download a tiny
  GGUF (for example Qwen3 0.6B), load, complete one prompt, unload, and check
  the footprint returns to baseline.
- Acceptance: the labelled error set from §8 against her real lecture, run in
  the app. Gate: precision of accepted edits at least 90%; recall reported,
  not gated. Zero edits that touch a number.

## 7. Risks

| Risk | Mitigation |
|---|---|
| The model "corrects" correct Chilean or colloquial speech | Rules forbid style changes; §4.5 caps edit length; examples show untouched colloquialisms; precision gate |
| Recall too low with edit lists | Spike compares against full rewrite on the same labelled set |
| Framework embedding or signing fails without Xcode | Spike step; fallback is a bundled `llama-server` child process |
| Model download (5 GB) on slow connections | Resumable download, same UI and folder as today |
| Time cost frustrates the user | Off by default, honest estimate in the toggle text, cancel between paragraphs |
| Newer models appear | One pinned model per release; changing it is a constant plus a re-run of §8 |

## 8. Spike plan (before any implementation)

1. She marks the errors she found in `50. Lesiones no melanocíticas Dr. Lobos.md`
   (the spot-check already requested). Target: 40 or more labelled errors.
2. A throwaway CLI (scratchpad, not committed) runs the §4.4 prompt with
   llama.cpp against every paragraph for each candidate model, in both output
   formats, and prints: accepted edits, precision against the labels, recall,
   seconds per paragraph, peak footprint.
3. Repeat once with Apple Foundation Models on this Mac for comparison
   (about 100 lines behind the same protocol).
4. Verify the xcframework links and runs from a `swift build` product and
   from the signed `.app`.
5. Decision: model, format, and whether the time cost is acceptable. Then the
   implementation plan.

## 9. Later phases

- Glossary suggestions: edits whose `wrong => right` pair appears in two or
  more paragraphs, or across two lectures, listed in the glossary sheet with
  an "Agregar" button. This turns each revised lecture into a better prompt
  for the next one.
- Sentence-level punctuation cleanup using the rewrite format only on
  paragraphs the edit pass flagged.
