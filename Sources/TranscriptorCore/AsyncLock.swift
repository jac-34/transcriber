import Foundation

/// Non-reentrant async mutex. Waiters are resumed in FIFO order; `release` hands ownership
/// directly to the next waiter so no newcomer can jump the line.
public actor AsyncLock {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func acquire() async {
        guard locked else {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    public func release() {
        if waiters.isEmpty {
            locked = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// Runs `body` while holding the lock. Calling `withLock` again from inside `body` deadlocks.
    public func withLock<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await body()
    }
}
