import Foundation

/// The folder where transcripts and the glossary live. Plain files the user can browse.
public struct Library: Sendable {
    public static let sidecarSuffix = ".transcriptor.json"
    public static let glossaryFileName = "glosario.txt"

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func ensureExists() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    // MARK: Glossary

    public var glossaryURL: URL { folder.appendingPathComponent(Library.glossaryFileName) }

    /// True when `glosario.txt` exists in the folder (the template is not written until the user saves).
    public var hasGlossaryFile: Bool { FileManager.default.fileExists(atPath: glossaryURL.path) }

    public func loadGlossaryText() -> String {
        (try? String(contentsOf: glossaryURL, encoding: .utf8)) ?? Glossary.templateText
    }

    public func saveGlossaryText(_ text: String) throws {
        try ensureExists()
        try text.write(to: glossaryURL, atomically: true, encoding: .utf8)
    }

    // MARK: Transcripts

    /// Writes `<stem>.md` and `<stem>.transcriptor.json`. Assigns a unique stem on first save.
    public func save(_ transcript: Transcript) throws -> Transcript {
        try ensureExists()
        var saved = transcript
        if saved.fileStem == nil {
            saved.fileStem = uniqueStem(for: Library.sanitizedStem(transcript.title))
        }
        let stem = saved.fileStem!
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(saved).write(to: sidecarURL(stem: stem), options: .atomic)
        try saved.renderMarkdown().write(to: markdownURL(stem: stem), atomically: true, encoding: .utf8)
        return saved
    }

    /// All transcripts, newest first. Unreadable sidecars are skipped.
    public func list() -> [Transcript] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return names
            .filter { $0.hasSuffix(Library.sidecarSuffix) }
            .compactMap { name -> Transcript? in
                guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
                return try? decoder.decode(Transcript.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func markdownURL(for transcript: Transcript) -> URL? {
        transcript.fileStem.map(markdownURL(stem:))
    }

    /// Replaces characters macOS or Finder treat specially. Empty titles become "Transcripción".
    public static func sanitizedStem(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Transcripción" : cleaned
    }

    private func uniqueStem(for base: String) -> String {
        var candidate = base
        var n = 2
        while FileManager.default.fileExists(atPath: sidecarURL(stem: candidate).path)
            || FileManager.default.fileExists(atPath: markdownURL(stem: candidate).path) {
            candidate = "\(base) (\(n))"
            n += 1
        }
        return candidate
    }

    private func markdownURL(stem: String) -> URL { folder.appendingPathComponent(stem + ".md") }
    private func sidecarURL(stem: String) -> URL { folder.appendingPathComponent(stem + Library.sidecarSuffix) }
}
