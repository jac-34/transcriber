import SwiftUI
import TranscriptorCore

/// Shows a transcript's paragraphs with timestamps, and lets the user search the text with
/// matches highlighted.
struct TranscriptDetailView: View {
    /// Holds the transcript to display.
    let transcript: Transcript
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transcript.title).font(.title2.bold())
                Text(transcript.metadataLine).font(.callout).foregroundStyle(.secondary)
            }
            .padding()
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if transcript.paragraphs.isEmpty {
                        Text(Transcript.noSpeechNotice).foregroundStyle(.secondary)
                    }
                    ForEach(Array(transcript.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Timestamp.bracket(paragraph.start))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(highlighted(paragraph.text))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding()
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Buscar en la transcripción")
    }

    /// Returns `text` as attributed text with every case- and diacritic-insensitive match of
    /// `query` highlighted in yellow. Returns `text` unchanged when `query` has fewer than 2
    /// non-whitespace characters.
    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return attributed }
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            if let lower = AttributedString.Index(found.lowerBound, within: attributed),
               let upper = AttributedString.Index(found.upperBound, within: attributed) {
                attributed[lower..<upper].backgroundColor = .yellow.opacity(0.6)
            }
            searchRange = found.upperBound..<text.endIndex
        }
        return attributed
    }
}
