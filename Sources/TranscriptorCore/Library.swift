import Foundation

/// The folder where transcripts and the glossary live. Plain files the user can browse.
public struct Library: Sendable {
    /// File suffix for a transcript's JSON sidecar.
    public static let sidecarSuffix = ".transcriptor.json"
    /// File name for the glossary inside the library folder.
    public static let glossaryFileName = "glosario.txt"

    /// Folder this library reads and writes.
    public let folder: URL

    /// Creates a library rooted at `folder`. Does not create the folder.
    public init(folder: URL) {
        self.folder = folder
    }

    /// Creates `folder`, and any missing parent directories, if it does not already exist.
    public func ensureExists() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    // MARK: Glossary

    /// Location of the glossary file inside `folder`.
    public var glossaryURL: URL { folder.appendingPathComponent(Library.glossaryFileName) }

    /// True when `glosario.txt` exists in the folder (the template is not written until the user saves).
    public var hasGlossaryFile: Bool { FileManager.default.fileExists(atPath: glossaryURL.path) }

    /// Returns the glossary file's contents, or `Glossary.templateText` when the file does not
    /// exist or cannot be read.
    public func loadGlossaryText() -> String {
        (try? String(contentsOf: glossaryURL, encoding: .utf8)) ?? Glossary.templateText
    }

    /// Writes `text` to the glossary file, creating `folder` first if needed.
    public func saveGlossaryText(_ text: String) throws {
        try ensureExists()
        try text.write(to: glossaryURL, atomically: true, encoding: .utf8)
    }

    // MARK: Transcripts

    /// Writes `<stem>.md` and `<stem>.transcriptor.json`. Assigns a unique stem on first save.
    /// Returns the transcript with `fileStem` set.
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

    /// Location of `transcript`'s markdown file, or `nil` when it has not been saved yet.
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

    /// Returns `base`, or `base` suffixed with " (n)" for the smallest `n` not already used by a
    /// saved transcript's markdown or sidecar file.
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
