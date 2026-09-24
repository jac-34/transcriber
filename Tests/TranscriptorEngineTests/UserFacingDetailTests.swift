import Foundation
import Testing
import WhisperKit
@testable import TranscriptorEngine

@Suite struct UserFacingDetailTests {
    @Test func networkErrorsSayNoConnection() {
        #expect(userFacingDetail(URLError(.notConnectedToInternet)) == "sin conexión a internet")
        #expect(userFacingDetail(URLError(.timedOut)) == "sin conexión a internet")
    }

    @Test func cancellationSaysCancelled() {
        #expect(userFacingDetail(CancellationError()) == "cancelado")
    }

    @Test func missingModelFilesAreNamed() {
        #expect(userFacingDetail(WhisperError.modelsUnavailable()) == "faltan archivos del modelo")
        #expect(userFacingDetail(WhisperError.initializationError("Model file not found at /x")) == "faltan archivos del modelo")
    }

    @Test func missingAudioIsNotBlamedOnTheModel() {
        let detail = userFacingDetail(WhisperError.loadAudioFailed("Audio file not found at path: /x.m4a"))
        #expect(detail == "Audio file not found at path: /x.m4a")
    }

    @Test func otherErrorsUseATruncatedLocalizedDescription() {
        let short = NSError(domain: "Prueba", code: 1, userInfo: [NSLocalizedDescriptionKey: "Algo salió mal."])
        #expect(userFacingDetail(short) == "Algo salió mal.")
        let long = NSError(domain: "Prueba", code: 2, userInfo: [NSLocalizedDescriptionKey: String(repeating: "x", count: 500)])
        #expect(userFacingDetail(long).count == 120)
    }
}
