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
        #expect(!lib.hasGlossaryFile)
        try lib.saveGlossaryText("enalapril\n")
        #expect(lib.hasGlossaryFile)
        #expect(lib.loadGlossaryText() == "enalapril\n")
        #expect(FileManager.default.fileExists(atPath: lib.glossaryURL.path))
    }
}
