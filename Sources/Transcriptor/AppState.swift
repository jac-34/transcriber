import Foundation
import Observation
import TranscriptorCore
import TranscriptorEngine

enum SidebarItem: Hashable {
    case job(UUID)
    case transcript(UUID)
}

@MainActor @Observable
final class AppState {
    let settings: Settings
    let modelManager: ModelManager
    let engine: WhisperKitEngine
    private(set) var library: Library
    let queue: JobQueue

    var transcripts: [Transcript] = []
    var selection: SidebarItem?
    /// One-line Spanish message shown in an alert, then cleared.
    var pendingAlert: String?
    var needsModelDownload = false

    init() {
        let settings = Settings()
        let modelManager = ModelManager()
        let engine = WhisperKitEngine(modelManager: modelManager)
        let library = Library(folder: settings.libraryFolder)
        self.settings = settings
        self.modelManager = modelManager
        self.engine = engine
        self.library = library
        self.queue = JobQueue(engine: engine, library: library, settings: settings)
        try? library.ensureExists()
        queue.onTranscriptSaved = { [weak self] transcript in
            self?.refreshLibrary()
            self?.selection = .transcript(transcript.id)
            AppLog.info("Transcripción guardada: \(transcript.title)")
        }
        queue.onJobFailed = { job, message in
            AppLog.error("Falló \(job.fileURL.lastPathComponent): \(message)")
        }
        refreshLibrary()
        needsModelDownload = !modelManager.isDownloaded(settings.modelChoice)
        AppLog.info("Inicio. Modelo: \(settings.modelChoice.rawValue). Carpeta: \(library.folder.path)")
    }

    func refreshLibrary() {
        transcripts = library.list()
    }

    func addFiles(_ urls: [URL]) {
        let rejections = queue.add(urls)
        if let first = queue.jobs.last(where: { !$0.isFinished }), selection == nil {
            selection = .job(first.id)
        }
        if !rejections.isEmpty {
            pendingAlert = rejections.joined(separator: "\n\n")
            AppLog.info("Archivos rechazados: \(rejections.count)")
        }
    }

    func openFilesPanel() {
        addFiles(FilePanels.chooseAudioFiles())
    }

    func transcript(for item: SidebarItem?) -> Transcript? {
        switch item {
        case .transcript(let id):
            return transcripts.first { $0.id == id }
        case .job(let id):
            if case .done(let t) = queue.jobs.first(where: { $0.id == id })?.state { return t }
            return nil
        case nil:
            return nil
        }
    }
}
