import os

/// Engine diagnostics. Full error dumps go here; the UI only gets `userFacingDetail`.
enum EngineLog {
    static let logger = Logger(subsystem: "com.jac.transcriptor", category: "engine")

    static func error(_ context: String, _ error: Error) {
        logger.error("\(context, privacy: .public): \(String(describing: error), privacy: .public)")
    }
}
