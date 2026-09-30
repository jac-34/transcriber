import Foundation
import Observation
import TranscriptorCore
import TranscriptorEngine

/// Identifies what the sidebar has selected.
enum SidebarItem: Hashable {
    /// Selects the queued or running job with this id.
    case job(UUID)
    /// Selects the saved transcript with this id.
    case transcript(UUID)
}

/// The app's observable state: wires Core's `JobQueue` to the transcription engine and settings,
/// and holds everything the views read and bind to. `TranscriptorApp` creates one instance and
/// injects it into the view hierarchy via `environment(_:)`.
@MainActor @Observable
final class AppState {
    /// User preferences: model choice and library folder.
    let settings: Settings
    /// Downloads and tracks which WhisperKit models are available locally.
    let modelManager: ModelManager
    /// Wraps WhisperKit for model preparation and transcription.
    let engine: WhisperKitEngine
    /// The folder where finished transcripts and the glossary are stored.
    private(set) var library: Library
    /// Processes queued audio files one at a time and reports their progress.
    let queue: JobQueue

    /// Transcripts currently listed in the sidebar, refreshed from `library`.
    var transcripts: [Transcript] = []
    /// The sidebar's current selection, if any.
    var selection: SidebarItem?
    /// One-line Spanish message shown in an alert, then cleared.
    var pendingAlert: String?
    /// True when the selected model must be downloaded before it can be used.
    var needsModelDownload = false
    /// Progress of the current model download, or nil when none is running.
    var downloadProgress: Double?
    /// Spanish error message from the last failed model download, or nil.
    var downloadError: String?
    /// Controls whether the settings sheet is presented.
    var showSettings = false
    /// Controls whether the glossary sheet is presented.
    var showGlossary = false

    /// Creates settings, the model manager, the engine and the library, falling back to the
    /// default library folder and showing `pendingAlert` if the saved folder is unavailable.
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

    /// Reloads `transcripts` from `library`.
    func refreshLibrary() {
        transcripts = library.list()
    }

    /// Queues `urls` for transcription, selects the newest job if nothing is selected, and
    /// surfaces any rejected files as `pendingAlert`.
    func addFiles(_ urls: [URL]) {
        let rejections = queue.add(urls)
        if let newest = queue.jobs.last(where: { !$0.isFinished }), selection == nil {
            selection = .job(newest.id)
        }
        if !rejections.isEmpty {
            pendingAlert = rejections.joined(separator: "\n\n")
            AppLog.info("Archivos rechazados: \(rejections.count)")
        }
    }

    /// Opens a file picker for audio files and queues the ones chosen.
    func openFilesPanel() {
        addFiles(FilePanels.chooseAudioFiles())
    }

    /// Returns the transcript for a sidebar selection: a saved transcript directly, or a finished
    /// job's transcript. Returns nil for a job with no transcript yet, or for a nil selection.
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

    /// True while any job is waiting or running.
    var hasActiveJobs: Bool { queue.jobs.contains { !$0.isFinished } }

    /// Shows the download sheet for a missing model only when the queue is idle; otherwise the
    /// next job downloads it while its row shows "Cargando modelo…".
    func modelChoiceChanged() {
        needsModelDownload = !modelManager.isDownloaded(settings.modelChoice) && !hasActiveJobs
    }

    /// Lets the user pick a destination and writes `transcript` there in `format`; does nothing
    /// if the panel is cancelled, and sets `pendingAlert` if the write fails.
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

    /// Creates the library folder if needed and reveals it in Finder.
    func revealLibraryFolder() {
        try? library.ensureExists()
        FilePanels.reveal(library.folder)
    }

    /// Re-runs the current glossary's corrections on `transcript`, saves the result, refreshes
    /// the transcript list, and selects the updated transcript. Sets `pendingAlert` on failure.
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

    /// Switches the library to `url`, copying an existing glossary file across if the new folder
    /// has none, then refreshes the transcript list.
    func changeLibraryFolder(_ url: URL) {
        let old = library
        let new = Library(folder: url)
        do {
            try new.ensureExists()
        } catch {
            AppLog.error("No se pudo crear la carpeta \(url.path): \(error)")
        }
        if !new.hasGlossaryFile && old.hasGlossaryFile {
            do {
                try FileManager.default.copyItem(at: old.glossaryURL, to: new.glossaryURL)
            } catch {
                AppLog.error("No se pudo copiar el glosario a \(url.path): \(error)")
            }
        }
        settings.libraryFolder = url
        library = new
        queue.library = new
        refreshLibrary()
        AppLog.info("Carpeta cambiada: \(url.path)")
    }

    /// Returns the current glossary file's text, or the template text if none has been saved yet.
    func loadGlossaryText() -> String { library.loadGlossaryText() }

    /// Saves `text` as the glossary file. Sets `pendingAlert` if the write fails.
    func saveGlossaryText(_ text: String) {
        do {
            try library.saveGlossaryText(text)
        } catch {
            pendingAlert = "No se pudo guardar el glosario: \(error.localizedDescription)"
        }
    }
}
