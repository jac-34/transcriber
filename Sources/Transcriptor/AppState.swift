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
    var downloadProgress: Double?
    var downloadError: String?
    var showSettings = false
    var showGlossary = false

    init() {
        let settings = Settings()
        let modelManager = ModelManager()
        let engine = WhisperKitEngine(modelManager: modelManager)
        var library = Library(folder: settings.libraryFolder)
        var startupAlert: String?
        do {
            try library.ensureExists()
        } catch {
            AppLog.error("Carpeta guardada no disponible (\(library.folder.path)): \(error)")
            settings.libraryFolder = Settings.defaultLibraryFolder
            library = Library(folder: settings.libraryFolder)
            try? library.ensureExists()
            startupAlert = "La carpeta de transcripciones guardada no está disponible. Se usará Documentos/Transcripciones."
        }
        self.settings = settings
        self.modelManager = modelManager
        self.engine = engine
        self.library = library
        self.queue = JobQueue(engine: engine, library: library, settings: settings)
        self.pendingAlert = startupAlert
        queue.onTranscriptSaved = { [weak self] job, transcript in
            guard let self else { return }
            self.refreshLibrary()
            // Follow the finished job only if the user is not looking at something else.
            if self.selection == nil || self.selection == .job(job.id) {
                let isListed = self.transcripts.contains { $0.id == transcript.id }
                self.selection = isListed ? .transcript(transcript.id) : .job(job.id)
            }
            AppLog.info("Transcripción guardada: \(transcript.title)")
        }
        queue.onJobFailed = { job, message in
            AppLog.error("Falló \(job.fileURL.lastPathComponent): \(message)")
        }
        queue.onLibraryFallback = { [weak self] folder in
            self?.pendingAlert = "No se pudo guardar en la carpeta elegida; la transcripción quedó en Documentos/Transcripciones."
            AppLog.error("Guardado en carpeta de respaldo: \(folder.path)")
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

    /// Downloads and loads the selected model, driving the first-launch screen.
    func prepareModel() async {
        downloadError = nil
        downloadProgress = 0
        do {
            try await engine.prepare(model: settings.modelChoice) { [weak self] p in
                Task { @MainActor in self?.downloadProgress = p }
            }
            needsModelDownload = false
            downloadProgress = nil
            AppLog.info("Modelo listo: \(settings.modelChoice.rawValue)")
        } catch {
            let message = TranscriptionError.message(for: error)
            downloadError = message
            downloadProgress = nil
            AppLog.error("Fallo al preparar modelo: \(message)")
        }
    }

    func modelChoiceChanged() {
        needsModelDownload = !modelManager.isDownloaded(settings.modelChoice)
    }

    func export(_ transcript: Transcript, as format: ExportFormat) {
        guard let destination = FilePanels.chooseExportDestination(suggestedName: Library.sanitizedStem(transcript.title), format: format) else { return }
        let content = format == .markdown ? transcript.renderMarkdown() : transcript.renderPlainText()
        do {
            try content.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            pendingAlert = "No se pudo guardar el archivo: \(error.localizedDescription)"
            AppLog.error("Exportar falló: \(error)")
        }
    }

    func revealLibraryFolder() {
        try? library.ensureExists()
        FilePanels.reveal(library.folder)
    }

    func reapplyGlossary(to transcript: Transcript) {
        let glossary = Glossary(text: library.loadGlossaryText())
        let updated = TranscriptPipeline.reapply(glossary: glossary, to: transcript)
        do {
            _ = try library.save(updated)
            refreshLibrary()
            selection = .transcript(updated.id)
        } catch {
            pendingAlert = "No se pudo guardar la transcripción corregida: \(error.localizedDescription)"
        }
    }

    func changeLibraryFolder(_ url: URL) {
        settings.libraryFolder = url
        library = Library(folder: url)
        queue.library = library
        try? library.ensureExists()
        refreshLibrary()
        AppLog.info("Carpeta cambiada: \(url.path)")
    }

    func loadGlossaryText() -> String { library.loadGlossaryText() }

    func saveGlossaryText(_ text: String) {
        do {
            try library.saveGlossaryText(text)
        } catch {
            pendingAlert = "No se pudo guardar el glosario: \(error.localizedDescription)"
        }
    }
}
