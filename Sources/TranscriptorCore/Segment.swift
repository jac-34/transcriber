import Foundation

/// One decoded window of speech as returned by the engine, before glossary corrections.
public struct Segment: Codable, Hashable, Sendable {
    /// Seconds from the start of the audio when this segment begins.
    public var start: TimeInterval
    /// Seconds from the start of the audio when this segment ends.
    public var end: TimeInterval
    /// Text Whisper decoded for this segment, before glossary corrections.
    public var text: String
    /// Average log-probability of the decoded tokens; lower means less confident.
    public var avgLogprob: Float
    /// Probability the segment contains no speech, from 0 to 1.
    public var noSpeechProb: Float
    /// Ratio of decoded text length to its compressed length; high values indicate repetitive
    /// or looping output.
    public var compressionRatio: Float

    /// Creates a segment. `avgLogprob`, `noSpeechProb` and `compressionRatio` default to values
    /// that do not signal a decoding problem.
    public init(
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        avgLogprob: Float = 0,
        noSpeechProb: Float = 0,
        compressionRatio: Float = 1
    ) {
        self.start = start
        self.end = end
        self.text = text
        self.avgLogprob = avgLogprob
        self.noSpeechProb = noSpeechProb
        self.compressionRatio = compressionRatio
    }
}

/// A readable block of text with the time its first word was spoken.
public struct Paragraph: Codable, Hashable, Sendable {
    /// Seconds from the start of the audio when the paragraph's first word was spoken.
    public var start: TimeInterval
    /// The paragraph's full text.
    public var text: String

    /// Creates a paragraph starting at `start` with `text`.
    public init(start: TimeInterval, text: String) {
        self.start = start
        self.text = text
    }
}
