import SwiftUI
import TranscriptorCore

/// Shows the sidebar and the selected transcript or job's status, plus a toolbar for adding
/// files, exporting, re-applying the glossary, revealing the library folder, and opening the
/// settings and glossary sheets. Forwards dropped files and alert dismissal to `AppState`.
struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            SidebarView(selection: $state.selection)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            if let transcript = state.transcript(for: state.selection) {
                TranscriptDetailView(transcript: transcript)
            } else if case .job(let id) = state.selection, let job = state.queue.jobs.first(where: { $0.id == id }) {
                EmptyStateView(
                    systemImage: "waveform",
                    title: job.fileURL.lastPathComponent,
                    message: job.stateText
                )
            } else if state.transcripts.isEmpty && state.queue.jobs.isEmpty {
                EmptyStateView(
                    systemImage: "square.and.arrow.down.on.square",
                    title: "Arrastra aquí los audios de tus clases",
                    message: "O usa el botón Agregar audios. Formatos: m4a, mp3, wav, mp4 y otros."
                )
            } else {
                EmptyStateView(systemImage: "doc.text", title: "Selecciona una transcripción", message: "")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { state.openFilesPanel() } label: { Label("Agregar audios", systemImage: "plus") }
                    .help("Agregar archivos de audio a la cola")
                if let transcript = state.transcript(for: state.selection) {
                    Menu {
                        ForEach(ExportFormat.allCases) { format in
                            Button(format.label) { state.export(transcript, as: format) }
                        }
                    } label: { Label("Exportar", systemImage: "square.and.arrow.up") }
                    .help("Guardar la transcripción como archivo")
                    Button { state.reapplyGlossary(to: transcript) } label: { Label("Re-aplicar glosario", systemImage: "arrow.triangle.2.circlepath") }
                        .help("Volver a aplicar las correcciones del glosario a esta transcripción")
                }
                Button { state.revealLibraryFolder() } label: { Label("Abrir carpeta", systemImage: "folder") }
                    .help("Mostrar la carpeta de transcripciones en el Finder")
                Button { state.showGlossary = true } label: { Label("Glosario", systemImage: "text.book.closed") }
                Button { state.showSettings = true } label: { Label("Ajustes", systemImage: "gearshape") }
            }
            ToolbarItemGroup(placement: .navigation) {
                if state.queue.jobs.contains(where: { !$0.isFinished }) {
                    Button("Cancelar todo") { Task { await state.queue.cancelAll() } }
                }
                if state.queue.jobs.contains(where: \.isFinished) {
                    Button("Limpiar listos") { state.queue.clearFinished() }
                }
            }
        }
        .sheet(isPresented: $state.needsModelDownload) { ModelDownloadView().environment(state) }
        .sheet(isPresented: $state.showSettings) { SettingsSheet().environment(state) }
        .sheet(isPresented: $state.showGlossary) { GlossarySheet(currentTranscript: state.transcript(for: state.selection)).environment(state) }
        .dropDestination(for: URL.self) { urls, _ in
            state.addFiles(urls)
            return true
        }
        .alert("Atención", isPresented: Binding(get: { state.pendingAlert != nil }, set: { if !$0 { state.pendingAlert = nil } })) {
            Button("Entendido") { state.pendingAlert = nil }
        } message: {
            Text(state.pendingAlert ?? "")
        }
    }
}
