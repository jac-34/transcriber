import Foundation
import WhisperKit

/// Short Spanish-friendly detail for the parenthesis in engine error messages.
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
