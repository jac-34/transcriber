import AVFoundation
import Foundation
import os
import TranscriptorCore
import WhisperKit

/// WhisperKit adapter. `prepare` and `transcribe` run one at a time under `operationLock`, so a second
/// `prepare` never downloads twice and a model is never unloaded under a running transcription.
/// `@unchecked Sendable` because WhisperKit's class is not Sendable; the loaded instance lives in `stateLock`.
public final class WhisperKitEngine: TranscriptionEngine, @unchecked Sendable {
    private let modelManager: ModelManager
    private let operationLock = AsyncLock()
    private let cancelFlag = OSAllocatedUnfairLock(initialState: false)
    // uncheckedState/withLockUnchecked because LoadedState holds a non-Sendable WhisperKit instance.
    private let stateLock = OSAllocatedUnfairLock(uncheckedState: LoadedState())

    private struct LoadedState {
        var whisperKit: WhisperKit?
        var model: ModelChoice?
    }

    public init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    // MARK: TranscriptionEngine

    public func prepare(model: ModelChoice, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await operationLock.withLock {
            try await self.prepareLocked(model: model, progress: progress)
        }
    }

    public func transcribe(fileURL: URL, prompt: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> TranscriptionOutput {
        // Reset before waiting for the lock so a cancel() that arrives while waiting is still honoured.
        cancelFlag.withLock { $0 = false }
        return try await operationLock.withLock {
            try await self.transcribeLocked(fileURL: fileURL, prompt: prompt, progress: progress)
        }
    }

    private func prepareLocked(model: ModelChoice, progress: @escaping @Sendable (Double) -> Void) async throws {
        let current = stateLock.withLockUnchecked { $0 }
        if current.model == model, current.whisperKit != nil {
            progress(1)
            return
        }

        let folder: URL
        if modelManager.isDownloaded(model) {
            folder = modelManager.folder(for: model)
        } else {
            folder = try await modelManager.download(model) { progress($0 * 0.9) }
        }

        if let old = current.whisperKit {
            await old.unloadModels()
            stateLock.withLockUnchecked { $0 = LoadedState() }
        }

        progress(0.9)
        let loaded: WhisperKit
        do {
            loaded = try await load(model, from: folder)
        } catch {
            // An interrupted download can leave a folder that looks complete but will not load.
            // The Hub client verifies what is on disk and fetches only what is missing.
            EngineLog.error("Carga de \(model.whisperVariant) falló; se repara la carpeta", error)
            let repaired = try await modelManager.download(model) { progress($0 * 0.9) }
            progress(0.9)
            do {
                loaded = try await load(model, from: repaired)
            } catch {
                EngineLog.error("Carga de \(model.whisperVariant) falló tras reparar", error)
                throw TranscriptionError.modelLoadFailed(userFacingDetail(error))
            }
        }
        stateLock.withLockUnchecked { $0 = LoadedState(whisperKit: loaded, model: model) }
        progress(1)
    }

    private func transcribeLocked(fileURL: URL, prompt: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> TranscriptionOutput {
        let state = stateLock.withLockUnchecked { $0 }
        guard let whisperKit = state.whisperKit, let model = state.model else {
            throw TranscriptionError.modelLoadFailed("El modelo no está cargado.")
        }
        if cancelFlag.withLock({ $0 }) { throw TranscriptionError.cancelled }

        let duration = try await audioDuration(of: fileURL)

        var options = DecodingOptions()
        options.task = .transcribe
        options.language = "es"
        options.detectLanguage = false
        options.usePrefillPrompt = true
        options.skipSpecialTokens = true
        options.withoutTimestamps = false
        options.wordTimestamps = false
        options.chunkingStrategy = .vad
        options.concurrentWorkerCount = model.concurrentWorkers
        options.compressionRatioThreshold = 2.4
        options.logProbThreshold = -1.0
        options.noSpeechThreshold = 0.6
        // No first-token fallback (whisperkit-cli's setting). WhisperKit's default of -1.5 sends VAD chunks
        // that start mid-sentence to high-temperature retries, which come back empty or hallucinated.
        options.firstTokenLogProbThreshold = nil
        if let prompt, let tokenizer = whisperKit.tokenizer {
            let trimmed = prompt.trimmingCharacters(in: .whitespaces)
            options.promptTokens = tokenizer.encode(text: " " + trimmed)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }

        let cancelFlag = self.cancelFlag
        let overall = whisperKit.progress
        // Last value passed to `progress`; -1 means nothing reported yet. Skips steps under half a percent.
        let lastReported = OSAllocatedUnfairLock<Double>(initialState: -1)
        let results: [TranscriptionResult]
        do {
            results = try await whisperKit.transcribe(audioPath: fileURL.path, decodeOptions: options) { _ in
                let value = min(0.99, overall.fractionCompleted)
                let shouldReport = lastReported.withLock { last in
                    guard last < 0 || value >= last + 0.005 else { return false }
                    last = value
                    return true
                }
                if shouldReport { progress(value) }
                return cancelFlag.withLock { $0 } ? false : nil
            }
        } catch {
            if cancelFlag.withLock({ $0 }) { throw TranscriptionError.cancelled }
            EngineLog.error("Transcripción de \(fileURL.lastPathComponent) falló", error)
            throw TranscriptionError.engineFailure(userFacingDetail(error))
        }
        if cancelFlag.withLock({ $0 }) { throw TranscriptionError.cancelled }

        let segments = results
            .flatMap(\.segments)
            .sorted { $0.start < $1.start }
            .map { s in
                Segment(
                    start: TimeInterval(s.start),
                    end: TimeInterval(s.end),
                    text: Self.stripSpecialTokens(s.text),
                    avgLogprob: s.avgLogprob,
                    noSpeechProb: s.noSpeechProb,
                    compressionRatio: s.compressionRatio
                )
            }
        progress(1)
        return TranscriptionOutput(segments: segments, audioDuration: duration)
    }

    public func tokenCount(_ text: String) async -> Int {
        guard let tokenizer = stateLock.withLockUnchecked({ $0.whisperKit })?.tokenizer else {
            // Rough fallback before a model is loaded: Whisper averages ~1.3 tokens per Spanish word.
            return Int(Double(text.split(separator: " ").count) * 1.3) + 1
        }
        return tokenizer.encode(text: " " + text).count
    }

    public func cancel() async {
        cancelFlag.withLock { $0 = true }
    }

    // MARK: Helpers

    private func load(_ model: ModelChoice, from folder: URL) async throws -> WhisperKit {
        let config = WhisperKitConfig(
            model: model.whisperVariant,
            downloadBase: modelManager.downloadBase,
            modelFolder: folder.path,
            tokenizerFolder: modelManager.downloadBase,
            computeOptions: computeOptions(for: model),
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        return try await WhisperKit(config)
    }

    private func computeOptions(for model: ModelChoice) -> ModelComputeOptions {
        switch model {
        case .preciso:
            ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine, textDecoderCompute: .cpuAndGPU)
        case .rapido:
            ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine, textDecoderCompute: .cpuAndNeuralEngine)
        }
    }

    private func audioDuration(of url: URL) async throws -> TimeInterval {
        do {
            let asset = AVURLAsset(url: url)
            let time = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite, seconds > 0 else { throw TranscriptionError.fileUnreadable(url.lastPathComponent) }
            return seconds
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.fileUnreadable(url.lastPathComponent)
        }
    }

    /// Removes any leftover "<|...|>" markers from segment text.
    static func stripSpecialTokens(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
