import SwiftUI
import TranscriptorCore

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
            }
        }
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
