import Foundation
import Testing
@testable import TranscriptorCore

@Suite struct AsyncLockTests {
    /// Tracks how many bodies are inside the lock at once.
    actor Probe {
        private(set) var inside = 0
        private(set) var maxInside = 0
        private(set) var completed = 0

        func enter() {
            inside += 1
            maxInside = max(maxInside, inside)
        }

        func leave() {
            inside -= 1
            completed += 1
        }
    }

    @Test func withLockRunsBodiesOneAtATime() async throws {
        let lock = AsyncLock()
        let probe = Probe()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await lock.withLock {
                        await probe.enter()
                        try await Task.sleep(nanoseconds: 1_000_000)
                        await probe.leave()
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(await probe.maxInside == 1)
        #expect(await probe.completed == 20)
    }

    @Test func bodyErrorsReleaseTheLock() async throws {
        struct Boom: Error {}
        let lock = AsyncLock()
        await #expect(throws: Boom.self) {
            try await lock.withLock { throw Boom() }
        }
        let value = await lock.withLock { 42 }
        #expect(value == 42)
    }
}
