import Testing
@testable import TranscriptorCore

@Suite struct HallucinationFilterTests {
    let filter = HallucinationFilter()

    @Test func dropsExactRepeatOfPreviousSegment() {
        let s = [
            Segment(start: 0, end: 1, text: "El potasio sérico."),
            Segment(start: 1, end: 2, text: " el potasio sérico "),
            Segment(start: 2, end: 3, text: "Otra cosa."),
        ]
        #expect(filter.filter(s).map(\.text) == ["El potasio sérico.", "Otra cosa."])
    }

    @Test func dropsKnownSpanishHallucinations() {
        let s = [
            Segment(start: 0, end: 1, text: "Subtítulos realizados por la comunidad de Amara.org"),
            Segment(start: 1, end: 2, text: "Gracias por ver el video."),
            Segment(start: 2, end: 3, text: "¡Suscríbete!"),
            Segment(start: 3, end: 4, text: "Gracias por venir a clases."),
        ]
        #expect(filter.filter(s).map(\.text) == ["Gracias por venir a clases."])
    }

    @Test func dropsLowConfidenceSilence() {
        let quiet = Segment(start: 0, end: 1, text: "mmm", avgLogprob: -1.4, noSpeechProb: 0.8)
        let confidentButNoSpeechy = Segment(start: 1, end: 2, text: "Ya.", avgLogprob: -0.2, noSpeechProb: 0.8)
        let unsureButSpeech = Segment(start: 2, end: 3, text: "Eh.", avgLogprob: -1.4, noSpeechProb: 0.1)
        #expect(filter.filter([quiet, confidentButNoSpeechy, unsureButSpeech]).map(\.text) == ["Ya.", "Eh."])
    }

    @Test func keepsNormalSpeechUntouched() {
        let s = [Segment(start: 0, end: 1, text: "Hola."), Segment(start: 1, end: 2, text: "Chao.")]
        #expect(filter.filter(s) == s)
    }
}
