import Testing
@testable import TranscriptorCore

@Suite struct TranscriptFormatterTests {
    let formatter = TranscriptFormatter()

    func seg(_ start: Double, _ end: Double, _ text: String) -> Segment {
        Segment(start: start, end: end, text: text)
    }

    /// Builds `count` segments of `wordsEach` words, back to back, one second each.
    func run(count: Int, wordsEach: Int, from start: Double = 0, ending: String = "") -> [Segment] {
        (0..<count).map { i in
            let words = Array(repeating: "palabra", count: wordsEach).joined(separator: " ")
            return seg(start + Double(i), start + Double(i) + 1, words + ending)
        }
    }

    @Test func emptyInputGivesNoParagraphs() {
        #expect(formatter.paragraphs(from: []).isEmpty)
        #expect(formatter.paragraphs(from: [seg(0, 1, "   ")]).isEmpty)
    }

    @Test func consecutiveSegmentsJoinIntoOneParagraph() {
        let result = formatter.paragraphs(from: [seg(0, 2, " Buenos días. "), seg(2.3, 4, "Hoy vemos el riñón.")])
        #expect(result == [Paragraph(start: 0, text: "Buenos días. Hoy vemos el riñón.")])
    }

    @Test func gapLongerThanThresholdStartsNewParagraph() {
        let result = formatter.paragraphs(from: [seg(0, 2, "Primera idea."), seg(3.6, 5, "Segunda idea.")])
        #expect(result.count == 2)
        #expect(result[1].start == 3.6)
        #expect(result[1].text == "Segunda idea.")
    }

    @Test func gapExactlyAtThresholdDoesNotSplit() {
        let result = formatter.paragraphs(from: [seg(0, 2, "Una."), seg(3.5, 5, "Dos.")])
        #expect(result.count == 1)
    }

    @Test func softLimitSplitsOnlyAtSentenceEnd() {
        // 13 segments x 10 words = 130 words; none ends a sentence, so no split yet.
        var segments = run(count: 13, wordsEach: 10)
        // The 14th ends a sentence -> paragraph closes after it (140 words).
        segments.append(seg(13, 14, "fin de la idea."))
        segments.append(seg(14, 15, "Nueva idea empieza aquí"))
        let result = formatter.paragraphs(from: segments)
        #expect(result.count == 2)
        #expect(result[0].text.hasSuffix("fin de la idea."))
        #expect(result[1].text == "Nueva idea empieza aquí")
    }

    @Test func hardLimitSplitsEvenWithoutPunctuation() {
        // 25 segments x 10 words = 250 words, no punctuation at all.
        let result = formatter.paragraphs(from: run(count: 25, wordsEach: 10))
        #expect(result.count == 2)
        let firstWords = result[0].text.split(separator: " ").count
        #expect(firstWords > 220 && firstWords <= 230)
    }

    @Test func outOfOrderSegmentsAreSortedFirst() {
        let result = formatter.paragraphs(from: [seg(10, 12, "Segundo."), seg(0, 2, "Primero.")])
        #expect(result.count == 2)
        #expect(result[0].text == "Primero.")
        #expect(result[1].text == "Segundo.")
    }

    @Test func paragraphStartIsFirstSegmentStart() {
        let result = formatter.paragraphs(from: [seg(3723.4, 3725, "Hola."), seg(3725.2, 3727, "Chao.")])
        #expect(result == [Paragraph(start: 3723.4, text: "Hola. Chao.")])
    }
}
