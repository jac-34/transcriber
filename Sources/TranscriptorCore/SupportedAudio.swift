import Foundation

/// File types the app accepts. AVFoundation decodes all of these natively.
public enum SupportedAudio {
    public static let extensions: Set<String> = [
        "m4a", "mp3", "wav", "aac", "aiff", "aif", "caf", "flac", "mp4", "mov", "m4v",
    ]

    /// Extensions we know people will try and that AVFoundation cannot decode.
    private static let opusLike: Set<String> = ["opus", "ogg", "oga"]

    public static func isSupported(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    public static func rejectionMessage(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        if opusLike.contains(ext) {
            return "\"\(name)\": los audios .\(ext) (notas de voz de WhatsApp en Android) no son compatibles. Conviértelo a .m4a o .mp3 primero."
        }
        let shown = ext.isEmpty ? "(sin extensión)" : ".\(ext)"
        let accepted = extensions.sorted().joined(separator: ", ")
        return "\"\(name)\": el formato \(shown) no es compatible. Formatos aceptados: \(accepted)."
    }
}
