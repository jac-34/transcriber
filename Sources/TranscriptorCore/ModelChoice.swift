import Foundation

/// The two speech models the user can pick between.
public enum ModelChoice: String, CaseIterable, Codable, Sendable, Identifiable {
    case preciso
    case rapido

    public var id: String { rawValue }

    /// WhisperKit variant name inside the argmaxinc/whisperkit-coreml repo.
    public var whisperVariant: String {
        switch self {
        case .preciso: "openai_whisper-large-v3_turbo"
        case .rapido: "openai_whisper-small"
        }
    }

    public var displayName: String {
        switch self {
        case .preciso: "Preciso"
        case .rapido: "Rápido"
        }
    }

    /// Size and speed hint shown next to the picker.
    public var detailText: String {
        switch self {
        case .preciso: "Whisper large-v3-turbo · descarga de ~3 GB · unos 11 min por clase de 90 min"
        case .rapido: "Whisper small · descarga de ~0,5 GB · unos 3 min por clase de 90 min"
        }
    }

    /// Parallel decoding windows. Measured best value on an M5 for the turbo model.
    public var concurrentWorkers: Int {
        switch self {
        case .preciso: 8
        case .rapido: 4
        }
    }
}
