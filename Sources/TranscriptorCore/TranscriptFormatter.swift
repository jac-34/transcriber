import Foundation

/// Groups engine segments into readable paragraphs.
public struct TranscriptFormatter: Sendable {
    /// Silence gap in seconds, between consecutive segments, that starts a new paragraph.
    public var gapThreshold: TimeInterval = 1.5
    /// Word count above which a paragraph ending in sentence punctuation is closed.
    public var softWordLimit = 120
    /// Word count above which a paragraph is closed regardless of punctuation.
    public var hardWordLimit = 220

    /// Creates a formatter using the default thresholds.
    public init() {}

    /// Groups `segments` into paragraphs, sorting them by start time first. A new paragraph
    /// starts after a silence longer than `gapThreshold`, or once the current paragraph reaches
    /// `hardWordLimit` words, or `softWordLimit` words at a sentence ending. Segments with empty
    /// text are skipped.
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
