import Foundation

/// One decoded window of speech as returned by the engine, before glossary corrections.
public struct Segment: Codable, Hashable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var avgLogprob: Float
    public var noSpeechProb: Float
    public var compressionRatio: Float

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
    public var start: TimeInterval
    public var text: String

    public init(start: TimeInterval, text: String) {
        self.start = start
        self.text = text
    }
}
