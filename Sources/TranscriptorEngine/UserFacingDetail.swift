import Foundation
import WhisperKit

/// Returns a short, Spanish-language detail for the parenthesis in an engine error message.
///
/// Returns "sin conexión a internet" for a `URLError`, "cancelado" for a `CancellationError`,
/// "faltan archivos del modelo" for a `WhisperError` reporting missing model files, and otherwise
/// the first 120 characters of `error.localizedDescription`.
func userFacingDetail(_ error: Error) -> String {
    if error is URLError { return "sin conexión a internet" }
    if error is CancellationError { return "cancelado" }
    if let whisperError = error as? WhisperError {
        // Missing audio is reported by the app itself; do not blame the model for it.
        if case .loadAudioFailed = whisperError {} else {
            let description = String(describing: whisperError)
            if description.contains("modelsUnavailable") || description.contains("not found") {
                return "faltan archivos del modelo"
            }
        }
    }
    return String(error.localizedDescription.prefix(120))
}
