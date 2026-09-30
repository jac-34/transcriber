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
        case .preciso: "Whisper large-v3-turbo · descarga de ~3 GB · unos 26 min por clase de 90 min"
        case .rapido: "Whisper small · descarga de ~0,5 GB · unos 10 min por clase de 90 min"
        }
    }

    /// Parallel decoding windows. Inside the app the Neural Engine times out CoreML predictions when the turbo
    /// model runs 6 or more windows at once (WhisperKit then drops those chunks); 2 decode as fast as 4 on an M5.
    public var concurrentWorkers: Int {
        switch self {
        case .preciso: 2
        case .rapido: 4
        }
    }
}
