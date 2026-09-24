import AppKit
import TranscriptorCore
import UniformTypeIdentifiers

@MainActor
enum FilePanels {
    static func chooseAudioFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Agregar audios"
        panel.prompt = "Agregar"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = SupportedAudio.extensions.compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.urls : []
    }

    /// Returns the chosen destination or nil if cancelled.
    static func chooseExportDestination(suggestedName: String, format: ExportFormat) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Exportar transcripción"
        panel.nameFieldStringValue = suggestedName + "." + format.fileExtension
        panel.allowedContentTypes = [format.contentType]
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFolder(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown, plainText
    var id: String { rawValue }
    var label: String {
        switch self {
        case .markdown: "Markdown (.md)"
        case .plainText: "Texto plano (.txt)"
        }
    }
    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .plainText: "txt"
        }
    }
    var contentType: UTType {
        switch self {
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        case .plainText: .plainText
        }
    }
}
