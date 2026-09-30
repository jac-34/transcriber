import os

/// Engine diagnostics. Full error dumps go here; the UI only gets `userFacingDetail`.
enum EngineLog {
    /// Logger for the engine subsystem, category "engine".
    static let logger = Logger(subsystem: "com.jac.transcriptor", category: "engine")

    /// Logs `error`'s full description at error level, tagged with `context`.
    static func error(_ context: String, _ error: Error) {
        logger.error("\(context, privacy: .public): \(String(describing: error), privacy: .public)")
    }
}
