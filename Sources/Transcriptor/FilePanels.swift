import AppKit
import TranscriptorCore
import UniformTypeIdentifiers

/// Presents macOS open/save panels for choosing audio files, an export destination, or a folder.
@MainActor
enum FilePanels {
    /// Shows a panel for choosing one or more audio files. Returns the chosen URLs, or an empty
    /// array if the panel is cancelled.
    static func chooseAudioFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Agregar audios"
        panel.prompt = "Agregar"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = SupportedAudio.extensions.compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.urls : []
    }

    /// Shows a save panel pre-filled with `suggestedName` for exporting a transcript as `format`.
    /// Returns the chosen destination, or nil if cancelled.
    static func chooseExportDestination(suggestedName: String, format: ExportFormat) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Exportar transcripción"
        panel.nameFieldStringValue = suggestedName + "." + format.fileExtension
        panel.allowedContentTypes = [format.contentType]
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Shows a panel titled `title` for choosing a folder. Returns the chosen URL, or nil if
    /// cancelled.
    static func chooseFolder(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Reveals `url` in Finder, selecting it.
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// A file format a transcript can be exported to: Markdown (`markdown`) or plain text (`plainText`).
enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown, plainText
    /// Identifies the format by its raw value.
    var id: String { rawValue }
    /// Spanish label shown in the export menu.
    var label: String {
        switch self {
        case .markdown: "Markdown (.md)"
        case .plainText: "Texto plano (.txt)"
        }
    }
    /// File extension used for the exported file.
    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .plainText: "txt"
        }
    }
    /// UTType used to restrict the save panel to this format.
    var contentType: UTType {
        switch self {
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        case .plainText: .plainText
        }
    }
}
