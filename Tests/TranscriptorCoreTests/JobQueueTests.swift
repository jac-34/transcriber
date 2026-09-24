import Foundation
import Testing
@testable import TranscriptorCore

@MainActor
@Suite struct JobQueueTests {
    func makeQueue(engine: FakeEngine) throws -> (JobQueue, Library) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("JobQueueTests-\(UUID().uuidString)")
        let library = Library(folder: dir)
        try library.ensureExists()
        let defaults = UserDefaults(suiteName: "JobQueueTests-\(UUID().uuidString)")!
        let settings = Settings(defaults: defaults)
        settings.modelChoice = .rapido
        return (JobQueue(engine: engine, library: library, settings: settings), library)
    }

    /// Creates a real empty file so the queue's existence check passes.
    func touch(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("JobQueueTests-\(UUID().uuidString)-\(name)")
        try Data().write(to: url)
        return url
    }

    let output = TranscriptionOutput(segments: [Segment(start: 0, end: 1, text: "Hola hipocalemia.")], audioDuration: 1)

    @Test func processesFilesInOrderAndSavesTranscripts() async throws {
        let engine = FakeEngine()
        let (queue, library) = try makeQueue(engine: engine)
        let a = try touch("a.m4a"), b = try touch("b.mp3")
        await engine.set(a.lastPathComponent, .success(output))
        await engine.set(b.lastPathComponent, .success(output))

        var saved: [String] = []
        var savedJobs: [UUID] = []
        queue.onTranscriptSaved = { job, transcript in
            savedJobs.append(job.id)
            saved.append(transcript.title)
        }
        queue.add([a, b])
        await queue.waitUntilIdle()

        #expect(queue.jobs.count == 2)
        for job in queue.jobs {
            guard case .done = job.state else { Issue.record("expected done, got \(job.state)"); continue }
        }
        #expect(saved.count == 2)
        #expect(savedJobs == queue.jobs.map(\.id))
        #expect(library.list().count == 2)
        #expect(await engine.prepareCalls == [.rapido, .rapido])
    }

    @Test func rejectsUnsupportedFilesWithMessages() throws {
        let engine = FakeEngine()
        let (queue, _) = try makeQueue(engine: engine)
        let messages = queue.add([URL(fileURLWithPath: "/tmp/nota.opus"), URL(fileURLWithPath: "/tmp/x.pdf")])
        #expect(messages.count == 2)
        #expect(messages[0].contains("WhatsApp"))
        #expect(queue.jobs.isEmpty)
    }

    @Test func missingFileFailsOnlyThatJobAndQueueContinues() async throws {
        let engine = FakeEngine()
        let (queue, _) = try makeQueue(engine: engine)
        let gone = URL(fileURLWithPath: "/tmp/no-existe-\(UUID().uuidString).m4a")
        let ok = try touch("ok.m4a")
        await engine.set(ok.lastPathComponent, .success(output))

        queue.add([gone, ok])
        await queue.waitUntilIdle()

        guard case .failed(let message) = queue.jobs[0].state else { Issue.record("expected failed"); return }
        #expect(message.contains("No se pudo leer"))
        guard case .done = queue.jobs[1].state else { Issue.record("expected done"); return }
    }

    @Test func engineErrorsBecomeSpanishMessagesAndFireCallback() async throws {
        let engine = FakeEngine()
        let (queue, _) = try makeQueue(engine: engine)
        let bad = try touch("bad.m4a")
        await engine.set(bad.lastPathComponent, .failure(.engineFailure("boom")))
        var reported: [String] = []
        queue.onJobFailed = { _, message in reported.append(message) }
        queue.add([bad])
        await queue.waitUntilIdle()
        guard case .failed(let message) = queue.jobs[0].state else { Issue.record("expected failed"); return }
        #expect(message == "La transcripción falló. (boom)")
        #expect(reported == [message])
    }

    @Test func glossaryPromptAndCorrectionsAreApplied() async throws {
        let engine = FakeEngine()
        let (queue, library) = try makeQueue(engine: engine)
        try library.saveGlossaryText("hipocalemia => hipokalemia\n")
        let a = try touch("a.m4a")
        await engine.set(a.lastPathComponent, .success(output))
        queue.add([a])
        await queue.waitUntilIdle()

        #expect(await engine.prompts == ["Clase de medicina. Términos: hipokalemia."])
        guard case .done(let t) = queue.jobs[0].state else { Issue.record("expected done"); return }
        #expect(t.paragraphs[0].text == "Hola hipokalemia.")
        #expect(queue.lastPromptTruncated == false)
    }

    @Test func duplicateOfAnUnfinishedJobIsIgnored() async throws {
        let engine = FakeEngine()
        await engine.setDelay(200_000_000)
        let (queue, _) = try makeQueue(engine: engine)
        let a = try touch("a.m4a")
        await engine.set(a.lastPathComponent, .success(output))
        queue.add([a])
        let messages = queue.add([a])
        #expect(queue.jobs.count == 1)
        #expect(messages.count == 1 && messages[0].contains("ya está en la lista"))
        await queue.waitUntilIdle()
    }

    @Test func cancelAllRemovesWaitingJobsAndAsksEngineToStop() async throws {
        let engine = FakeEngine()
        await engine.setDelay(300_000_000)
        let (queue, _) = try makeQueue(engine: engine)
        let a = try touch("a.m4a"), b = try touch("b.m4a")
        await engine.set(a.lastPathComponent, .success(output))
        await engine.set(b.lastPathComponent, .success(output))
        queue.add([a, b])
        try await Task.sleep(nanoseconds: 50_000_000)
        await queue.cancelAll()
        await queue.waitUntilIdle()

        #expect(await engine.cancelCalls == 1)
        #expect(queue.jobs.count == 1)  // b was removed while waiting
        #expect(queue.jobs[0].fileURL == a)
    }

    @Test func cancelAllDuringModelLoadStopsBeforeTranscribing() async throws {
        let engine = FakeEngine()
        await engine.setPrepareDelay(300_000_000)
        let (queue, _) = try makeQueue(engine: engine)
        let a = try touch("a.m4a")
        await engine.set(a.lastPathComponent, .success(output))
        queue.add([a])
        try await Task.sleep(nanoseconds: 50_000_000)
        await queue.cancelAll()
        await queue.waitUntilIdle()

        #expect(queue.jobs.count == 1)
        #expect(queue.jobs[0].state == .failed("Cancelado."))
        #expect(await engine.prompts.isEmpty)
    }

    @Test func saveFailureFallsBackToDefaultLibrary() async throws {
        let engine = FakeEngine()
        let blocker = try touch("archivo-normal")
        let unwritable = Library(folder: blocker.appendingPathComponent("Transcripciones", isDirectory: true))
        let fallback = Library(folder: FileManager.default.temporaryDirectory.appendingPathComponent("JobQueueTests-fallback-\(UUID().uuidString)"))
        let settings = Settings(defaults: UserDefaults(suiteName: "JobQueueTests-\(UUID().uuidString)")!)
        let queue = JobQueue(engine: engine, library: unwritable, settings: settings, fallbackLibrary: fallback)
        var fallbackFolders: [URL] = []
        queue.onLibraryFallback = { fallbackFolders.append($0) }
        let a = try touch("a.m4a")
        await engine.set(a.lastPathComponent, .success(output))
        queue.add([a])
        await queue.waitUntilIdle()

        guard case .done = queue.jobs[0].state else { Issue.record("expected done, got \(queue.jobs[0].state)"); return }
        #expect(fallback.list().count == 1)
        #expect(fallbackFolders == [fallback.folder])
    }

    @Test func saveFailureInBothFoldersFailsTheJob() async throws {
        let engine = FakeEngine()
        let blocker = try touch("archivo-normal")
        let unwritable = Library(folder: blocker.appendingPathComponent("a", isDirectory: true))
        let alsoUnwritable = Library(folder: blocker.appendingPathComponent("b", isDirectory: true))
        let settings = Settings(defaults: UserDefaults(suiteName: "JobQueueTests-\(UUID().uuidString)")!)
        let queue = JobQueue(engine: engine, library: unwritable, settings: settings, fallbackLibrary: alsoUnwritable)
        var fallbackCalls = 0
        queue.onLibraryFallback = { _ in fallbackCalls += 1 }
        let a = try touch("a.m4a")
        await engine.set(a.lastPathComponent, .success(output))
        queue.add([a])
        await queue.waitUntilIdle()

        guard case .failed(let message) = queue.jobs[0].state else { Issue.record("expected failed"); return }
        #expect(message.hasPrefix("No se pudo guardar la transcripción: "))
        #expect(fallbackCalls == 0)
    }

    @Test func clearFinishedKeepsActiveJobs() async throws {
        let engine = FakeEngine()
        let (queue, _) = try makeQueue(engine: engine)
        let a = try touch("a.m4a")
        await engine.set(a.lastPathComponent, .success(output))
        queue.add([a])
        await queue.waitUntilIdle()
        queue.clearFinished()
        #expect(queue.jobs.isEmpty)
    }

    @Test func changingLibrarySavesNewJobsThere() async throws {
        let engine = FakeEngine()
        let (queue, _) = try makeQueue(engine: engine)
        let other = Library(folder: FileManager.default.temporaryDirectory.appendingPathComponent("JobQueueTests-other-\(UUID().uuidString)"))
        try other.ensureExists()
        queue.library = other
        let a = try touch("a.m4a")
        await engine.set(a.lastPathComponent, .success(output))
        queue.add([a])
        await queue.waitUntilIdle()
        #expect(other.list().count == 1)
    }
}
