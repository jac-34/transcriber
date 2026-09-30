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
        // Set once the process footprint passes `memoryLimit`; stops decoding the same way cancel() does.
        let memoryExceeded = OSAllocatedUnfairLock(initialState: false)
        let memoryLimit = Self.memoryLimitBytes
        let callback: TranscriptionCallback = { _ in
            let value = min(0.99, overall.fractionCompleted)
            let shouldReport = lastReported.withLock { last in
                guard last < 0 || value >= last + 0.005 else { return false }
                last = value
                return true
            }
            if shouldReport { progress(value) }
            let overLimit = memoryExceeded.withLock { exceeded in
                if !exceeded, let footprint = Self.physicalFootprintBytes(), footprint > memoryLimit { exceeded = true }
                return exceeded
            }
            return overLimit || cancelFlag.withLock { $0 } ? false : nil
        }
        let started = Date()
        var results: [TranscriptionResult]
        do {
            results = try await whisperKit.transcribe(audioPath: fileURL.path, decodeOptions: options, callback: callback)
        } catch {
            if cancelFlag.withLock({ $0 }) { throw TranscriptionError.cancelled }
            if memoryExceeded.withLock({ $0 }) { throw Self.memoryLimitError(fileURL) }
            EngineLog.error("Transcripción de \(fileURL.lastPathComponent) falló", error)
            throw TranscriptionError.engineFailure(userFacingDetail(error))
        }
        if cancelFlag.withLock({ $0 }) { throw TranscriptionError.cancelled }
        if memoryExceeded.withLock({ $0 }) { throw Self.memoryLimitError(fileURL) }

        // WhisperKit drops VAD chunks whose decode fails (e.g. a Neural Engine timeout) and returns the rest.
        // Find the holes, decode them again one clip at a time, and refuse to save a transcript with holes.
        var covered = results.map(Self.decodedRange)
        let missing = CoverageGaps.uncovered(ranges: covered, duration: duration)
        if !missing.isEmpty {
            let (recovered, ranges) = try await recover(
                missing, of: fileURL, duration: duration, whisperKit: whisperKit, options: options, callback: callback,
                stopReason: { cancelFlag.withLock { $0 } ? .cancelled : memoryExceeded.withLock { $0 } ? Self.memoryLimitError(fileURL) : nil }
            )
            results += recovered
            covered += ranges
        }
        let fraction = CoverageGaps.coverageFraction(ranges: covered, duration: duration)
        let elapsed = Date().timeIntervalSince(started)
        EngineLog.logger.info("Transcripción de \(fileURL.lastPathComponent, privacy: .public): \(duration, format: .fixed(precision: 0)) s de audio en \(elapsed, format: .fixed(precision: 0)) s, cobertura \(fraction * 100, format: .fixed(precision: 1))%")
        guard CoverageGaps.isComplete(fraction: fraction) else {
            EngineLog.logger.error("Transcripción de \(fileURL.lastPathComponent, privacy: .public) incompleta: cobertura \(fraction * 100, format: .fixed(precision: 1))%")
            throw TranscriptionError.engineFailure(CoverageGaps.incompleteDetail(fraction: fraction))
        }

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

    /// The file-relative seconds a WhisperKit result decoded: its VAD chunk, or the whole file when unchunked.
    private static func decodedRange(_ result: TranscriptionResult) -> ClosedRange<Double> {
        let start = Double(result.seekTime ?? 0)
        return start...(start + max(0, result.timings.inputAudioSeconds))
    }

    /// Decodes `gaps` again, one clip per call, sequentially and without VAD chunking, for up to two passes.
    /// Returns the new results and the ranges that decoded. A gap whose retry fails stays uncovered;
    /// `stopReason` (cancel or memory limit) aborts the recovery with that error.
    private func recover(
        _ gaps: [ClosedRange<Double>],
        of fileURL: URL,
        duration: TimeInterval,
        whisperKit: WhisperKit,
        options: DecodingOptions,
        callback: @escaping TranscriptionCallback,
        stopReason: () -> TranscriptionError?
    ) async throws -> (results: [TranscriptionResult], ranges: [ClosedRange<Double>]) {
        let name = fileURL.lastPathComponent
        let missingSeconds = gaps.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        EngineLog.logger.error("Transcripción de \(name, privacy: .public): \(missingSeconds, format: .fixed(precision: 1)) s sin transcribir en \(gaps.count) tramos; se reintentan")

        let audio: [Float]
        do {
            audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: fileURL.path, channelMode: whisperKit.audioInputOptions.channelMode)
        } catch {
            EngineLog.error("Recarga de \(name) para reintentar tramos falló", error)
            return ([], [])
        }
        let audioEnd = Double(audio.count) / Double(WhisperKit.sampleRate)

        var clipOptions = options
        clipOptions.chunkingStrategy = ChunkingStrategy.none
        clipOptions.concurrentWorkerCount = 1

        var results: [TranscriptionResult] = []
        var ranges: [ClosedRange<Double>] = []
        var pending = gaps
        for pass in 1...2 where !pending.isEmpty {
            var failed: [ClosedRange<Double>] = []
            for gap in pending {
                if let reason = stopReason() { throw reason }
                let end = min(gap.upperBound, audioEnd)
                guard end > gap.lowerBound else { continue }
                clipOptions.clipTimestamps = [Float(gap.lowerBound), Float(end)]
                do {
                    results += try await whisperKit.transcribe(audioArray: audio, decodeOptions: clipOptions, callback: callback)
                    if let reason = stopReason() { throw reason }
                    ranges.append(gap.lowerBound...end)
                } catch let error as TranscriptionError {
                    throw error
                } catch {
                    if let reason = stopReason() { throw reason }
                    EngineLog.error("Reintento \(pass) del tramo \(Int(gap.lowerBound))–\(Int(end)) s de \(name) falló", error)
                    failed.append(gap)
                }
            }
            pending = failed
        }
        let recoveredSeconds = CoverageGaps.coveredSeconds(ranges: ranges, duration: duration)
        EngineLog.logger.info("Transcripción de \(name, privacy: .public): \(recoveredSeconds, format: .fixed(precision: 1)) de \(missingSeconds, format: .fixed(precision: 1)) s recuperados; \(pending.count) tramos siguen sin transcribir")
        return (results, ranges)
    }

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

    /// Encoder and decoder both on the Neural Engine. The text decoder must not run on the GPU: on macOS 26
    /// CoreML's GPU path leaks ~0.35 MB per decoder step (MPSTemporaryNDArray/AGX buffers, not autoreleased
    /// objects), which grew a 93-minute lecture past 30 GB. On the Neural Engine the footprint stays flat.
    private func computeOptions(for model: ModelChoice) -> ModelComputeOptions {
        ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine, textDecoderCompute: .cpuAndNeuralEngine)
    }

    /// Footprint above which a transcription is stopped: half of physical memory. A full lecture peaks at ~2.5 GB.
    static var memoryLimitBytes: UInt64 { ProcessInfo.processInfo.physicalMemory / 2 }

    /// This process's physical footprint (the figure Jetsam acts on), or nil if the kernel call fails.
    static func physicalFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    private static func memoryLimitError(_ fileURL: URL) -> TranscriptionError {
        let limitGB = Double(memoryLimitBytes) / 1_073_741_824
        EngineLog.logger.error("Transcripción de \(fileURL.lastPathComponent, privacy: .public) detenida: memoria sobre \(limitGB, format: .fixed(precision: 1)) GB")
        return .engineFailure("se detuvo porque usaba demasiada memoria")
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
