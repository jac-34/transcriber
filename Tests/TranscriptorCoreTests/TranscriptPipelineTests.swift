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
