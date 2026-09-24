import Testing
@testable import TranscriptorCore

@Suite struct TimestampTests {
    @Test func bracketAlwaysShowsHours() {
        #expect(Timestamp.bracket(0) == "[00:00:00]")
        #expect(Timestamp.bracket(59.9) == "[00:00:59]")
        #expect(Timestamp.bracket(754) == "[00:12:34]")
        #expect(Timestamp.bracket(3723) == "[01:02:03]")
    }

    @Test func durationDropsLeadingZeroHour() {
        #expect(Timestamp.duration(754) == "12:34")
        #expect(Timestamp.duration(3723) == "1:02:03")
        #expect(Timestamp.duration(5530) == "1:32:10")
    }
}
