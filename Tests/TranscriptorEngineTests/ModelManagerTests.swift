import Foundation
import Testing
import TranscriptorCore
@testable import TranscriptorEngine

@Suite struct ModelManagerTests {
    @Test func folderFollowsHuggingFaceLayout() {
        let base = URL(fileURLWithPath: "/tmp/base")
        let m = ModelManager(downloadBase: base)
        #expect(m.folder(for: .rapido).path == "/tmp/base/models/argmaxinc/whisperkit-coreml/openai_whisper-small")
        #expect(m.folder(for: .preciso).path == "/tmp/base/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3_turbo")
    }

    @Test func isDownloadedRequiresAllModelFiles() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ModelManagerTests-\(UUID().uuidString)")
        let m = ModelManager(downloadBase: base)
        #expect(!m.isDownloaded(.rapido))
        let folder = m.folder(for: .rapido)
        for bundle in ["TextDecoder.mlmodelc", "AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc"] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(bundle), withIntermediateDirectories: true)
            #expect(!m.isDownloaded(.rapido), "incomplete after \(bundle)")
        }
        try "{}".write(to: folder.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        #expect(m.isDownloaded(.rapido))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("MelSpectrogram.mlmodelc"))
        #expect(!m.isDownloaded(.rapido))
    }

    @Test func defaultBaseIsApplicationSupport() {
        let base = ModelManager.defaultBase()
        #expect(base.path.hasSuffix("/Library/Application Support/Transcriptor"))
    }
}
