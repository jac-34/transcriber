import AVFoundation
import Foundation
import os
import TranscriptorCore
import WhisperKit

/// WhisperKit adapter. JobQueue calls it strictly sequentially, so a single loaded model
/// guarded by `stateLock` is enough; `@unchecked Sendable` because WhisperKit's class is not Sendable.
public final class WhisperKitEngine: TranscriptionEngine, @unchecked Sendable {
    private let modelManager: ModelManager
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
        progress(0.9)
        let loaded: WhisperKit
        do {
            loaded = try await WhisperKit(config)
        } catch {
            throw TranscriptionError.modelLoadFailed(String(describing: error))
        }
        stateLock.withLockUnchecked { $0 = LoadedState(whisperKit: loaded, model: model) }
        progress(1)
    }

    public func transcribe(fileURL: URL, prompt: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> TranscriptionOutput {
        let state = stateLock.withLockUnchecked { $0 }
        guard let whisperKit = state.whisperKit, let model = state.model else {
            throw TranscriptionError.modelLoadFailed("El modelo no está cargado.")
        }
        cancelFlag.withLock { $0 = false }

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
        if let prompt, let tokenizer = whisperKit.tokenizer {
            let trimmed = prompt.trimmingCharacters(in: .whitespaces)
            options.promptTokens = tokenizer.encode(text: " " + trimmed)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }

        let cancelFlag = self.cancelFlag
        let overall = whisperKit.progress
        let results: [TranscriptionResult]
        do {
            results = try await whisperKit.transcribe(audioPath: fileURL.path, decodeOptions: options) { _ in
                progress(min(0.99, overall.fractionCompleted))
                return cancelFlag.withLock { $0 } ? false : nil
            }
        } catch {
            if cancelFlag.withLock({ $0 }) { throw TranscriptionError.cancelled }
            throw TranscriptionError.engineFailure(String(describing: error))
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
