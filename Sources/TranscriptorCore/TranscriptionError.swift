import Foundation

/// Every failure the UI can show. Descriptions are plain Spanish, one sentence.
public enum TranscriptionError: Error, LocalizedError, Sendable, Equatable {
    /// File format rejected by `SupportedAudio`; the associated value is the message to show as-is.
    case unsupportedFormat(String)
    /// Source file could not be read; the associated value is its file name.
    case fileUnreadable(String)
    /// Model download failed; the associated value is the underlying error detail.
    case modelDownloadFailed(String)
    /// Model failed to load after downloading; the associated value is the underlying error detail.
    case modelLoadFailed(String)
    /// The job was cancelled by the user.
    case cancelled
    /// Transcription failed inside the engine; the associated value is the underlying error detail.
    case engineFailure(String)
    /// The transcript could not be written to the library; the associated value is the
    /// underlying error detail.
    case saveFailed(String)

    /// Spanish message shown to the user for this error.
    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let message):
            return message
        case .fileUnreadable(let name):
            return "No se pudo leer el archivo \"\(name)\". ¿Se movió o borró?"
        case .modelDownloadFailed(let detail):
            return "No se pudo descargar el modelo. Revisa la conexión a internet e inténtalo de nuevo. (\(detail))"
        case .modelLoadFailed(let detail):
            return "No se pudo cargar el modelo de transcripción. (\(detail))"
        case .cancelled:
            return "Cancelado."
        case .engineFailure(let detail):
            return "La transcripción falló. (\(detail))"
        case .saveFailed(let detail):
            return "No se pudo guardar la transcripción: \(detail)"
        }
    }

    /// Message for any thrown error, in Spanish. Recognizes `TranscriptionError` and
    /// `CancellationError`; any other error falls back to its `localizedDescription`.
    public static func message(for error: Error) -> String {
        if let known = error as? TranscriptionError { return known.errorDescription ?? "Error." }
        if error is CancellationError { return TranscriptionError.cancelled.errorDescription! }
        return "Error inesperado: \(error.localizedDescription)"
    }
}
