import Foundation

/// Groups engine segments into readable paragraphs.
public struct TranscriptFormatter: Sendable {
    public var gapThreshold: TimeInterval = 1.5
    public var softWordLimit = 120
    public var hardWordLimit = 220

    public init() {}

    public func paragraphs(from segments: [Segment]) -> [Paragraph] {
        var result: [Paragraph] = []
        var current: (start: TimeInterval, words: [String], lastEnd: TimeInterval)?

        func flush() {
            if let c = current, !c.words.isEmpty {
                result.append(Paragraph(start: c.start, text: c.words.joined(separator: " ")))
            }
            current = nil
        }

        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)

            if let c = current, segment.start - c.lastEnd > gapThreshold {
                flush()
            }

            if current == nil {
                current = (segment.start, [], segment.end)
            }
            current!.words.append(contentsOf: words)
            current!.lastEnd = segment.end

            let count = current!.words.count
            let endsSentence = text.hasSuffix(".") || text.hasSuffix("?") || text.hasSuffix("!")
            if count > hardWordLimit || (count > softWordLimit && endsSentence) {
                flush()
            }
        }
        flush()
        return result
    }
}
