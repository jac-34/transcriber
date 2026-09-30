import SwiftUI
import TranscriptorCore

/// Presents the glossary editor as a sheet. Shows live term/correction counts and parse errors,
/// and forwards saving and, optionally, re-applying the glossary to `currentTranscript` to
/// `AppState`.
struct GlossarySheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    /// The transcript to re-correct after saving, if any.
    let currentTranscript: Transcript?

    private var parsed: Glossary { Glossary(text: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Glosario").font(.title2.bold())
            Text("Un término por línea. Para corregir algo que el modelo escribe mal: `incorrecto => correcto`. Las líneas con # son comentarios.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 320)
                .border(.separator)
            HStack {
                Text("\(parsed.terms.count) términos · \(parsed.corrections.count) correcciones")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            if !parsed.parseErrors.isEmpty {
                ForEach(parsed.parseErrors, id: \.line) { error in
                    Text("Línea \(error.line): \(error.message)").font(.caption).foregroundStyle(.red)
                }
            }
            if state.queue.lastPromptTruncated {
                Text("El glosario es largo: solo los primeros términos se usan para guiar al modelo. Las correcciones se aplican siempre.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if let transcript = currentTranscript {
                    Button("Guardar y re-aplicar a \"\(transcript.title)\"") {
                        state.saveGlossaryText(text)
                        state.reapplyGlossary(to: transcript)
                        dismiss()
                    }
                }
                Button("Guardar") {
                    state.saveGlossaryText(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620, height: 560)
        .onAppear { text = state.loadGlossaryText() }
    }
}
