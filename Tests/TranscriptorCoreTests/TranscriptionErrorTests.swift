import Foundation
import Testing
@testable import TranscriptorCore

@Suite struct TranscriptionErrorTests {
    @Test func unknownErrorsUseTheLocalizedDescription() {
        let error = NSError(domain: "Prueba", code: 7, userInfo: [NSLocalizedDescriptionKey: "El disco está lleno."])
        #expect(TranscriptionError.message(for: error) == "Error inesperado: El disco está lleno.")
    }

    @Test func saveFailedHasSpanishMessage() {
        #expect(TranscriptionError.saveFailed("sin permiso").errorDescription == "No se pudo guardar la transcripción: sin permiso")
    }
}
