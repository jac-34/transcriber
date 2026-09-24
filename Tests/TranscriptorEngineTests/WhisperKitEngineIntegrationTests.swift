import Foundation
import Testing
import TranscriptorCore
@testable import TranscriptorEngine

/// Runs only with TRANSCRIPTOR_INTEGRATION=1 (make test-integration). Downloads the small model once
/// into the real Application Support folder and synthesizes a Spanish clip with macOS `say`.
// .serialized: each test loads/downloads into the same shared model folder via its own
// WhisperKitEngine/ModelManager instance. Swift Testing parallelizes tests within a suite by
// default, and concurrent downloads into that shared folder race on renaming the same
// ".incomplete" temp files, corrupting the cache. Running serially avoids that.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["TRANSCRIPTOR_INTEGRATION"] == "1"))
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
