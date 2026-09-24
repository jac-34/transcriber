import SwiftUI
import TranscriptorCore

struct TranscriptDetailView: View {
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
