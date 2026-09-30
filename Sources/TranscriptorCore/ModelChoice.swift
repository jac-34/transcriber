import Foundation

/// The two speech models the user can pick between.
public enum ModelChoice: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Whisper large-v3-turbo: slower, more accurate.
    case preciso
    /// Whisper small: faster, less accurate.
    case rapido

    /// Raw value used as the stable identifier.
    public var id: String { rawValue }

    /// WhisperKit variant name inside the argmaxinc/whisperkit-coreml repo.
    public var whisperVariant: String {
        switch self {
        case .preciso: "openai_whisper-large-v3_turbo"
        case .rapido: "openai_whisper-small"
        }
    }

    /// Spanish name shown in the model picker.
    public var displayName: String {
        switch self {
        case .preciso: "Preciso"
        case .rapido: "Rápido"
        }
    }

    /// Size and speed hint shown next to the picker.
    public var detailText: String {
        switch self {
        case .preciso: "Whisper large-v3-turbo · descarga de ~3 GB · unos 26 min por clase de 90 min"
        case .rapido: "Whisper small · descarga de ~0,5 GB · unos 10 min por clase de 90 min"
        }
    }

    /// Number of decoding windows the engine runs in parallel for this model.
    public var concurrentWorkers: Int {
        switch self {
        case .preciso: 2
        case .rapido: 4
        }
    }
}
