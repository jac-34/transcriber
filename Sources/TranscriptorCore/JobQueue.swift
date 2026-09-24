import Foundation
import Observation

public struct Job: Identifiable, Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case waiting
        case loadingModel(Double)
        case transcribing(Double)
        case applyingGlossary
        case done(Transcript)
        case failed(String)
    }

    public let id: UUID
    public let fileURL: URL
    public var state: State

    public var isFinished: Bool {
        switch state {
        case .done, .failed: true
        default: false
        }
    }

    /// Spanish label for the sidebar.
    public var stateText: String {
        switch state {
        case .waiting: "En espera"
        case .loadingModel: "Cargando modelo…"
        case .transcribing(let p): "Transcribiendo… \(Int(p * 100))%"
        case .applyingGlossary: "Aplicando glosario…"
        case .done: "Listo"
        case .failed(let message): "Error: \(message)"
        }
    }
}

/// Sequential processor: one file at a time, failures never stop the line.
@MainActor @Observable
public final class JobQueue {
    public private(set) var jobs: [Job] = []
    /// Called after each transcript is written to the library.
    public var onTranscriptSaved: (@MainActor (Transcript) -> Void)?
    /// Called when a job fails, with the Spanish message shown to the user.
    public var onJobFailed: (@MainActor (Job, String) -> Void)?
    /// True when the last built prompt had to drop glossary terms.
    public private(set) var lastPromptTruncated = false

    private let engine: any TranscriptionEngine
    /// Where finished transcripts are saved. Replaced when the user changes the folder in settings.
    public var library: Library
    private let settings: Settings
    private var worker: Task<Void, Never>?

    public init(engine: any TranscriptionEngine, library: Library, settings: Settings) {
        self.engine = engine
        self.library = library
        self.settings = settings
    }

    /// Queues supported files. Returns one Spanish message per rejected URL.
    @discardableResult
    public func add(_ urls: [URL]) -> [String] {
        var rejections: [String] = []
        for url in urls {
            guard SupportedAudio.isSupported(url) else {
                rejections.append(SupportedAudio.rejectionMessage(for: url))
                continue
            }
            if jobs.contains(where: { $0.fileURL == url && !$0.isFinished }) {
                rejections.append("\"\(url.lastPathComponent)\" ya está en la lista.")
                continue
            }
            jobs.append(Job(id: UUID(), fileURL: url, state: .waiting))
        }
        startIfNeeded()
        return rejections
    }

    /// Drops waiting jobs and asks the engine to stop the current one.
    public func cancelAll() async {
        jobs.removeAll { if case .waiting = $0.state { return true } else { return false } }
        await engine.cancel()
    }

    public func clearFinished() {
        jobs.removeAll(where: \.isFinished)
    }

    /// Resolves when no job is running. For tests and for quitting cleanly.
    public func waitUntilIdle() async {
        await worker?.value
    }

    // MARK: Processing

    private func startIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, let next = self.jobs.first(where: { if case .waiting = $0.state { return true } else { return false } }) {
                await self.process(next.id)
            }
            self?.worker = nil
        }
    }

    private func process(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        do {
            guard FileManager.default.isReadableFile(atPath: job.fileURL.path) else {
                throw TranscriptionError.fileUnreadable(job.fileURL.lastPathComponent)
            }

            update(id, .loadingModel(0))
            let model = settings.modelChoice
            try await engine.prepare(model: model) { [weak self] p in
                Task { @MainActor in self?.update(id, .loadingModel(p)) }
            }

            let glossary = Glossary(text: library.loadGlossaryText())
            let tokenCounter: @Sendable (String) async -> Int = { [engine] text in await engine.tokenCount(text) }
            let prompt = await glossary.promptText(tokenCount: tokenCounter)
            lastPromptTruncated = prompt.truncated

            update(id, .transcribing(0))
            let output = try await engine.transcribe(fileURL: job.fileURL, prompt: prompt.text) { [weak self] p in
                Task { @MainActor in self?.update(id, .transcribing(p)) }
            }

            update(id, .applyingGlossary)
            let transcript = TranscriptPipeline.build(
                output: output, sourceURL: job.fileURL, model: model, glossary: glossary, prompt: prompt.text
            )
            let saved = try library.save(transcript)
            update(id, .done(saved))
            onTranscriptSaved?(saved)
        } catch {
            let message = TranscriptionError.message(for: error)
            update(id, .failed(message))
            if let failed = jobs.first(where: { $0.id == id }) { onJobFailed?(failed, message) }
        }
    }

    private func update(_ id: UUID, _ state: Job.State) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        // Ignore late progress callbacks after a job finished.
        if jobs[index].isFinished { return }
        jobs[index].state = state
    }
}
