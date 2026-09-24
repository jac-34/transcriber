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
