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
