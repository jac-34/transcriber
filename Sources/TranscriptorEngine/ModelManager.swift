import Foundation
import TranscriptorCore
import WhisperKit

/// Knows where models live on disk and downloads them from Hugging Face.
public struct ModelManager: Sendable {
    public static let repo = "argmaxinc/whisperkit-coreml"

    public let downloadBase: URL

    public static func defaultBase() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Transcriptor", isDirectory: true)
    }

    public init(downloadBase: URL = ModelManager.defaultBase()) {
        self.downloadBase = downloadBase
    }

    /// Matches WhisperKit's Hub cache layout: <base>/models/<repo>/<variant>.
    public func folder(for model: ModelChoice) -> URL {
        downloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(ModelManager.repo, isDirectory: true)
            .appendingPathComponent(model.whisperVariant, isDirectory: true)
    }

    /// Files a model folder must contain before it is loaded without contacting the network.
    static let requiredFiles = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc", "config.json"]

    public func isDownloaded(_ model: ModelChoice) -> Bool {
        let folder = folder(for: model)
        return ModelManager.requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    /// Downloads the model files. `progress` is 0...1. Resumable by the underlying Hub client.
    public func download(_ model: ModelChoice, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        do {
            try FileManager.default.createDirectory(at: downloadBase, withIntermediateDirectories: true)
            return try await WhisperKit.download(
                variant: model.whisperVariant,
                downloadBase: downloadBase,
                from: ModelManager.repo,
                progressCallback: { p in progress(p.fractionCompleted) }
            )
        } catch {
            EngineLog.error("Descarga de \(model.whisperVariant) falló", error)
            throw TranscriptionError.modelDownloadFailed(userFacingDetail(error))
        }
    }
}
