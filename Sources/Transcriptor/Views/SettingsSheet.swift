import SwiftUI
import TranscriptorCore

/// Lets the user change the model choice and the library folder, forwarding both changes to
/// `AppState`.
struct SettingsSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = state.settings
        VStack(alignment: .leading, spacing: 20) {
            Text("Ajustes").font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("Modelo").font(.headline)
                Picker("Modelo", selection: $settings.modelChoice) {
                    ForEach(ModelChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(settings.modelChoice.detailText).font(.callout).foregroundStyle(.secondary)
                if !state.modelManager.isDownloaded(settings.modelChoice) {
                    Text(state.hasActiveJobs
                        ? "Este modelo aún no está descargado. Se descargará cuando termine la cola."
                        : "Este modelo aún no está descargado. Se descargará al cerrar los ajustes.")
                        .font(.callout).foregroundStyle(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Carpeta de transcripciones").font(.headline)
                HStack {
                    Text(state.library.folder.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cambiar…") {
                        if let url = FilePanels.chooseFolder(title: "Elegir carpeta de transcripciones") {
                            state.changeLibraryFolder(url)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Listo") {
                    state.modelChoiceChanged()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
