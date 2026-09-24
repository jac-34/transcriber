import Foundation
import Testing
@testable import TranscriptorCore

@Suite struct SupportedAudioTests {
    @Test func acceptsCommonAudioAndVideoExtensions() {
        for ext in ["m4a", "mp3", "wav", "aac", "aiff", "aif", "caf", "flac", "mp4", "mov", "m4v", "M4A"] {
            #expect(SupportedAudio.isSupported(URL(fileURLWithPath: "/tmp/clase.\(ext)")), "\(ext) should be supported")
        }
    }

    @Test func rejectsUnknownExtensions() {
        for ext in ["opus", "ogg", "pdf", "txt", ""] {
            #expect(!SupportedAudio.isSupported(URL(fileURLWithPath: "/tmp/clase.\(ext)")), "\(ext) should be rejected")
        }
    }

    @Test func opusMessageMentionsWhatsApp() {
        let message = SupportedAudio.rejectionMessage(for: URL(fileURLWithPath: "/tmp/nota.opus"))
        #expect(message.contains("WhatsApp"))
        #expect(message.contains(".opus"))
    }

    @Test func genericMessageListsAcceptedFormats() {
        let message = SupportedAudio.rejectionMessage(for: URL(fileURLWithPath: "/tmp/apuntes.pdf"))
        #expect(message.contains(".pdf"))
        #expect(message.contains("m4a"))
        #expect(message.contains("mp3"))
    }
}
