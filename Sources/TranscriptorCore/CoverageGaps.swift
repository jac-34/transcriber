import Foundation

/// Arithmetic over the parts of a recording an engine actually decoded.
public enum CoverageGaps {
    /// Smallest share of the audio a transcript must cover to be saved.
    public static let minimumCoverage = 0.9

    /// The parts of `0...duration` outside every range in `ranges`, sorted by start.
    /// Gaps shorter than `minGap` seconds are dropped, and the last `trailingPad` seconds of the audio
    /// are not counted as a gap (WhisperKit stops each clip up to one second early by design).
    public static func uncovered(
        ranges: [ClosedRange<Double>],
        duration: Double,
        minGap: Double = 2,
        trailingPad: Double = 1
    ) -> [ClosedRange<Double>] {
        guard duration.isFinite, duration > 0 else { return [] }
        let end = max(0, duration - max(0, trailingPad))
        var gaps: [ClosedRange<Double>] = []
        var cursor = 0.0
        for range in merged(ranges, duration: duration) {
            if range.lowerBound > cursor {
                appendGap(cursor...min(range.lowerBound, end), to: &gaps, minGap: minGap)
            }
            cursor = max(cursor, range.upperBound)
        }
        if cursor < end {
            appendGap(cursor...end, to: &gaps, minGap: minGap)
        }
        return gaps
    }

    /// Seconds of `0...duration` inside at least one range; overlaps count once.
    public static func coveredSeconds(ranges: [ClosedRange<Double>], duration: Double) -> Double {
        merged(ranges, duration: duration).reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
    }

    /// Share of `0...duration` inside at least one range, from 0 to 1.
    public static func coverageFraction(ranges: [ClosedRange<Double>], duration: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(1, coveredSeconds(ranges: ranges, duration: duration) / duration)
    }

    /// Whether `fraction` meets `minimumCoverage`.
    public static func isComplete(fraction: Double) -> Bool {
        fraction >= minimumCoverage
    }

    /// Error detail for a transcript that covers too little of the audio. The percentage is rounded down.
    public static func incompleteDetail(fraction: Double) -> String {
        let percent = Int((max(0, min(1, fraction)) * 100).rounded(.down))
        return "quedó incompleta: solo se transcribió el \(percent)% del audio"
    }

    /// `ranges` clipped to `0...duration`, sorted and with overlapping or touching ranges joined.
    private static func merged(_ ranges: [ClosedRange<Double>], duration: Double) -> [ClosedRange<Double>] {
        guard duration.isFinite, duration > 0 else { return [] }
        let clipped = ranges
            .filter { $0.lowerBound.isFinite && $0.upperBound.isFinite }
            .compactMap { r -> ClosedRange<Double>? in
                let lower = max(0, r.lowerBound), upper = min(duration, r.upperBound)
                return lower < upper ? lower...upper : nil
            }
            .sorted { $0.lowerBound < $1.lowerBound }
        var result: [ClosedRange<Double>] = []
        for range in clipped {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    private static func appendGap(_ gap: ClosedRange<Double>, to gaps: inout [ClosedRange<Double>], minGap: Double) {
        if gap.upperBound - gap.lowerBound >= minGap { gaps.append(gap) }
    }
}
