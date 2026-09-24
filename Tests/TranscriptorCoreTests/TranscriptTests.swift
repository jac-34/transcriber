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
