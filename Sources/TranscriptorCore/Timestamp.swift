import Foundation

/// Formats seconds as human-readable time strings.
public enum Timestamp {
    /// "[hh:mm:ss]" with hours always present so columns align.
    public static func bracket(_ seconds: TimeInterval) -> String {
        let (h, m, s) = split(seconds)
        return String(format: "[%02d:%02d:%02d]", h, m, s)
    }

    /// "h:mm:ss" or "mm:ss" when under an hour. Used for durations in metadata.
    public static func duration(_ seconds: TimeInterval) -> String {
        let (h, m, s) = split(seconds)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// Splits `seconds` into (hours, minutes, seconds), clamping non-finite or negative input to zero.
    private static func split(_ seconds: TimeInterval) -> (Int, Int, Int) {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded(.down))) : 0
        return (total / 3600, (total % 3600) / 60, total % 60)
    }
}
