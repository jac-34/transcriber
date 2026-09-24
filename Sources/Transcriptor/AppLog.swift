import Foundation
import os

/// os.Logger plus an append-only file at ~/Library/Logs/Transcriptor/transcriptor.log (rotated at 5 MB).
enum AppLog {
    static let logger = Logger(subsystem: "com.jac.transcriptor", category: "app")
    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Transcriptor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("transcriptor.log")
    }()
    private static let queue = DispatchQueue(label: "com.jac.transcriptor.log")

    static func info(_ message: String) { write("INFO", message); logger.info("\(message, privacy: .public)") }
    static func error(_ message: String) { write("ERROR", message); logger.error("\(message, privacy: .public)") }

    private static func write(_ level: String, _ message: String) {
        queue.async {
            rotateIfNeeded()
            let line = "\(ISO8601DateFormatter().string(from: Date())) \(level) \(message)\n"
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func rotateIfNeeded() {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        guard size > 5_000_000 else { return }
        let old = fileURL.deletingPathExtension().appendingPathExtension("old.log")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: fileURL, to: old)
    }
}
