import Foundation

/// Removes segments Whisper is known to invent on silence or noise.
public struct HallucinationFilter: Sendable {
    /// Whole-segment matches after normalization (lowercased, no punctuation, single spaces).
    public static let knownPhrases: [String] = [
        "gracias por ver el video",
        "gracias por ver",
        "gracias por ver este video",
        "suscríbete",
        "suscríbete al canal",
        "no olvides suscribirte",
        "hasta la próxima",
        "nos vemos en el próximo video",
        "www mooji org",
    ]

    /// Prefix matches after normalization.
    public static let knownPrefixes: [String] = [
        "subtítulos realizados por",
        "subtitulado por",
        "subtítulos por",
        "transcripción por",
    ]

    /// Together with `logProbThreshold`, the no-speech probability above which a segment is
    /// treated as a hallucination.
    public var noSpeechThreshold: Float = 0.6
    /// Together with `noSpeechThreshold`, the average log-probability below which a segment is
    /// treated as a hallucination.
    public var logProbThreshold: Float = -1.0

    /// Creates a filter using the default thresholds.
    public init() {}

    /// Returns `segments` with empty text, consecutive duplicates, known hallucinated phrases or
    /// prefixes, and low-confidence silence segments removed. Order is preserved.
    public func filter(_ segments: [Segment]) -> [Segment] {
        var kept: [Segment] = []
        var previousNormalized: String?
        for segment in segments {
            let normalized = normalize(segment.text)
            if normalized.isEmpty { continue }
            if normalized == previousNormalized { continue }
            if Self.knownPhrases.contains(normalized) { continue }
            if Self.knownPrefixes.contains(where: { normalized.hasPrefix($0) }) { continue }
            if segment.noSpeechProb > noSpeechThreshold && segment.avgLogprob < logProbThreshold { continue }
            kept.append(segment)
            previousNormalized = normalized
        }
        return kept
    }

    /// Lowercases `text`, replaces non-letter, non-digit characters with spaces, and collapses
    /// whitespace runs to single spaces.
    private func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let letters = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        return String(letters)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
