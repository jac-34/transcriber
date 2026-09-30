import Foundation

/// File types the app accepts. AVFoundation decodes all of these natively.
public enum SupportedAudio {
    /// Lowercase file extensions accepted for transcription, without the leading dot.
    public static let extensions: Set<String> = [
        "m4a", "mp3", "wav", "aac", "aiff", "aif", "caf", "flac", "mp4", "mov", "m4v",
    ]

    /// Extensions we know people will try and that AVFoundation cannot decode.
    private static let opusLike: Set<String> = ["opus", "ogg", "oga"]

    /// True when `url`'s extension is in `extensions`, case-insensitively.
    public static func isSupported(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// Spanish message explaining why `url` was rejected: tailored for an undownloaded iCloud
    /// placeholder, a known unsupported format such as .opus, or any other unsupported extension.
    public static func rejectionMessage(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        if ext == "icloud" {
            // iCloud placeholders are named ".clase.m4a.icloud"; show the real file name.
            var shown = url.deletingPathExtension().lastPathComponent
            if shown.hasPrefix(".") { shown.removeFirst() }
            return "\"\(shown)\": este archivo aún no se descargó de iCloud. Ábrelo en Finder para descargarlo y vuelve a intentarlo."
        }
        if opusLike.contains(ext) {
            return "\"\(name)\": los audios .\(ext) (notas de voz de WhatsApp en Android) no son compatibles. Conviértelo a .m4a o .mp3 primero."
        }
        let shown = ext.isEmpty ? "(sin extensión)" : ".\(ext)"
        let accepted = extensions.sorted().joined(separator: ", ")
        return "\"\(name)\": el formato \(shown) no es compatible. Formatos aceptados: \(accepted)."
    }
}
