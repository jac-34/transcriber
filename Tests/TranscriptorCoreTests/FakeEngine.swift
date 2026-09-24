import Foundation
@testable import TranscriptorCore

/// Scripted engine: returns canned segments per file name, or throws.
actor FakeEngine: TranscriptionEngine {
    var results: [String: Result<TranscriptionOutput, TranscriptionError>] = [:]
    private(set) var prepareCalls: [ModelChoice] = []
    private(set) var prompts: [String?] = []
    private(set) var cancelCalls = 0
    var delayNanoseconds: UInt64 = 0

    func set(_ fileName: String, _ result: Result<TranscriptionOutput, TranscriptionError>) {
        results[fileName] = result
    }

    func setDelay(_ nanoseconds: UInt64) { delayNanoseconds = nanoseconds }

    func prepare(model: ModelChoice, progress: @escaping @Sendable (Double) -> Void) async throws {
        prepareCalls.append(model)
        progress(1)
    }

    func transcribe(fileURL: URL, prompt: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> TranscriptionOutput {
        prompts.append(prompt)
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        progress(0.5)
        guard let result = results[fileURL.lastPathComponent] else {
            throw TranscriptionError.fileUnreadable(fileURL.lastPathComponent)
        }
        progress(1)
        return try result.get()
    }

    func tokenCount(_ text: String) async -> Int {
        text.split(separator: " ").count
    }

    func cancel() async {
        cancelCalls += 1
    }
}
