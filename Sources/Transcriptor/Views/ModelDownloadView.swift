import SwiftUI
import TranscriptorCore

/// Shown as a sheet when the selected model is not on disk yet. Shows download progress and, on
/// failure, forwards the retry action to `AppState`.
struct ModelDownloadView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle").font(.system(size: 40)).foregroundStyle(.tint)
            Text("Descargando el modelo de transcripción").font(.title3.bold())
            Text("Esto pasa una sola vez. \(state.settings.modelChoice.detailText). Después de esto la app funciona sin internet.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let p = state.downloadProgress {
                ProgressView(value: p) {
                    Text(p < 0.9 ? "Descargando… \(Int(p * 100))%" : "Preparando el modelo (puede tomar un par de minutos)…")
                }
                .frame(width: 360)
            }
            if let error = state.downloadError {
                Text(error).foregroundStyle(.red).multilineTextAlignment(.center).frame(width: 380)
                Button("Reintentar") { Task { await state.prepareModel() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 460)
        .task { if state.downloadProgress == nil && state.downloadError == nil { await state.prepareModel() } }
        .interactiveDismissDisabled(true)
    }
}
