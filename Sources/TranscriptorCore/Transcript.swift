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
