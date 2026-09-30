import Testing
@testable import TranscriptorCore

@Suite struct CoverageGapsTests {
    @Test func fullCoverageHasNoGaps() {
        let ranges: [ClosedRange<Double>] = [0...30, 30...58.5, 58.5...89.2]
        #expect(CoverageGaps.uncovered(ranges: ranges, duration: 90).isEmpty)
        #expect(CoverageGaps.coveredSeconds(ranges: ranges, duration: 90) == 89.2)
    }

    @Test func leadingGapIsReported() {
        #expect(CoverageGaps.uncovered(ranges: [12...60], duration: 60) == [0...12])
    }

    @Test func trailingGapStopsBeforeThePad() {
        #expect(CoverageGaps.uncovered(ranges: [0...40], duration: 60) == [40...59])
        // A pad-sized tail is not a gap.
        #expect(CoverageGaps.uncovered(ranges: [0...59.2], duration: 60).isEmpty)
    }

    @Test func missingMiddleChunksBecomeOneGap() {
        let ranges: [ClosedRange<Double>] = [0...28, 83...110, 110...140]
        #expect(CoverageGaps.uncovered(ranges: ranges, duration: 140) == [28...83])
    }

    @Test func subSecondSeamsBetweenAdjacentChunksAreIgnored() {
        let ranges: [ClosedRange<Double>] = [0...29.6, 30.1...59.8, 60.9...90]
        #expect(CoverageGaps.uncovered(ranges: ranges, duration: 90).isEmpty)
    }

    @Test func gapsShorterThanMinGapAreIgnored() {
        #expect(CoverageGaps.uncovered(ranges: [0...10, 11.9...30], duration: 30).isEmpty)
        #expect(CoverageGaps.uncovered(ranges: [0...10, 12...30], duration: 30) == [10...12])
    }

    @Test func overlappingChunksCountOnce() {
        let ranges: [ClosedRange<Double>] = [0...30, 20...50, 45...60]
        #expect(CoverageGaps.uncovered(ranges: ranges, duration: 60).isEmpty)
        #expect(CoverageGaps.coveredSeconds(ranges: ranges, duration: 60) == 60)
    }

    @Test func unsortedAndOutOfBoundsRangesAreHandled() {
        let ranges: [ClosedRange<Double>] = [50...80, -5...10, 30...40]
        #expect(CoverageGaps.uncovered(ranges: ranges, duration: 70) == [10...30, 40...50])
        #expect(CoverageGaps.coveredSeconds(ranges: ranges, duration: 70) == 40)
    }

    @Test func noRangesMeansEverythingIsUncovered() {
        #expect(CoverageGaps.uncovered(ranges: [], duration: 900) == [0...899])
        #expect(CoverageGaps.coverageFraction(ranges: [], duration: 900) == 0)
        #expect(CoverageGaps.uncovered(ranges: [], duration: 0).isEmpty)
    }

    @Test func coverageThresholdIsNinetyPercent() {
        #expect(CoverageGaps.isComplete(fraction: CoverageGaps.coverageFraction(ranges: [0...90], duration: 100)))
        #expect(!CoverageGaps.isComplete(fraction: CoverageGaps.coverageFraction(ranges: [0...89.9], duration: 100)))
        #expect(CoverageGaps.isComplete(fraction: 1))
    }

    @Test func incompleteDetailShowsTheWholePercentage() {
        #expect(CoverageGaps.incompleteDetail(fraction: 0.4478) == "quedó incompleta: solo se transcribió el 44% del audio")
        #expect(TranscriptionError.engineFailure(CoverageGaps.incompleteDetail(fraction: 0.899)).errorDescription
            == "La transcripción falló. (quedó incompleta: solo se transcribió el 89% del audio)")
    }
}
