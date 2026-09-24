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
