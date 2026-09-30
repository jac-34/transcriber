import Foundation

/// A finished transcription plus everything needed to re-render or re-correct it.
public struct Transcript: Codable, Hashable, Sendable, Identifiable {
    /// Version written to `schemaVersion` for new transcripts.
    public static let currentSchemaVersion = 1
    /// Body text used when a transcript has no paragraphs.
    public static let noSpeechNotice = "(No se detectó voz en el audio.)"

    /// Format version this transcript was encoded with.
    public var schemaVersion: Int
    /// Stable identity for this transcript.
    public var id: UUID
    /// Display title, initially the source file's name without its extension.
    public var title: String
    /// Base file name used in the library folder. Assigned by Library.save on first save.
    public var fileStem: String?
    /// Path to the audio file this transcript was produced from.
    public var sourcePath: String
    /// Length of the source audio, in seconds.
    public var audioDuration: TimeInterval
    /// When this transcript was produced.
    public var createdAt: Date
    /// Speech model used to produce this transcript.
    public var modelChoice: ModelChoice
    /// Decoding prompt built from the glossary, or `nil` when none was used.
    public var glossaryPromptUsed: String?
    /// Raw engine output after hallucination filtering, before glossary corrections.
    public var segments: [Segment]
    /// Readable paragraphs rendered from `segments` with glossary corrections applied.
    public var paragraphs: [Paragraph]

    /// Creates a transcript. Sets `schemaVersion` to `currentSchemaVersion`.
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

    /// Returns the transcript as Markdown: a title heading, `metadataLine`, and the paragraph body.
    public func renderMarkdown() -> String {
        var lines = ["# \(title)", "", metadataLine, ""]
        lines.append(body)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Returns the paragraph body as plain text, without the title or metadata.
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

    /// Paragraph text joined with timestamp brackets, or `noSpeechNotice` when there are no paragraphs.
    private var body: String {
        guard !paragraphs.isEmpty else { return Transcript.noSpeechNotice }
        return paragraphs
            .map { "\(Timestamp.bracket($0.start)) \($0.text)" }
            .joined(separator: "\n\n")
    }
}
