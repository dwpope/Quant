import Foundation

/// Counts the frames the pipeline has handed to tasks and not yet finished, so a caller can
/// wait for them all (2026-10-12). Frames arrive on a camera queue and finish on the main
/// actor, so the count is behind a lock.
final class FramesInFlight: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func begin() {
        lock.withLock { count += 1 }
    }

    func end() {
        let ready: [CheckedContinuation<Void, Never>] = lock.withLock {
            count -= 1
            guard count == 0 else { return [] }
            defer { waiters = [] }
            return waiters
        }
        ready.forEach { $0.resume() }
    }

    /// Returns once nothing is in flight.
    func settled() async {
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            let now: Bool = lock.withLock {
                if count == 0 { return true }
                waiters.append(waiter)
                return false
            }
            if now { waiter.resume() }
        }
    }
}
