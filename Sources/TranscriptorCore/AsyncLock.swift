import Foundation

/// Non-reentrant async mutex. Waiters are resumed in FIFO order; `release` hands ownership
/// directly to the next waiter so no newcomer can jump the line.
public actor AsyncLock {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Creates an unlocked lock.
    public init() {}

    /// Waits until the lock is free, then holds it. Callers are queued in FIFO order.
    public func acquire() async {
        guard locked else {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Releases the lock, resuming the longest-waiting caller if one exists.
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
