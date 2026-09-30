import Foundation
import Testing
@testable import TranscriptorEngine

@Suite struct MemoryGuardTests {
    @Test func footprintIsReadAndGrowsWithDirtiedMemory() throws {
        let before = try #require(WhisperKitEngine.physicalFootprintBytes())
        #expect(before > 0 && before < ProcessInfo.processInfo.physicalMemory)
        let size = 256 * 1_048_576
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16_384)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 1, count: size)
        let after = try #require(WhisperKitEngine.physicalFootprintBytes())
        #expect(after >= before + UInt64(size) / 2)
    }

    @Test func limitIsHalfOfPhysicalMemory() {
        #expect(WhisperKitEngine.memoryLimitBytes == ProcessInfo.processInfo.physicalMemory / 2)
    }
}
