import Foundation

/// Every failure the UI can show. Descriptions are plain Spanish, one sentence.
public enum TranscriptionError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedFormat(String)
    case fileUnreadable(String)
    case modelDownloadFailed(String)
    case modelLoadFailed(String)
    case cancelled
    case engineFailure(String)
    case saveFailed(String)

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

    /// Message for any thrown error, in Spanish.
    public static func message(for error: Error) -> String {
        if let known = error as? TranscriptionError { return known.errorDescription ?? "Error." }
        if error is CancellationError { return TranscriptionError.cancelled.errorDescription! }
        return "Error inesperado: \(error.localizedDescription)"
    }
}
