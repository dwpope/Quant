import Foundation

/// A short rolling store of face samples, written at camera rate from ARKit's delegate callbacks (no delegate queue is set, so the main queue) and read
/// when the posture log writes a line. Guarded by a lock; safe from any thread.
public final class FaceSampleBuffer: @unchecked Sendable {
    private let keep: TimeInterval
    private let lock = NSLock()
    private var samples: [FaceSample] = []
    private var newest: TimeInterval?

    public init(keep: TimeInterval = 30) {
        self.keep = keep
    }

    /// Adds a sample and drops those older than `keep` before the newest.
    public func append(_ s: FaceSample) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(s)
        let latest = max(newest ?? s.t, s.t)
        newest = latest
        let cutoff = latest - keep
        if let first = samples.first, first.t < cutoff {
            samples.removeAll { $0.t < cutoff }
        }
    }

    public func summary(from: TimeInterval, to: TimeInterval) -> FaceSignalSummary? {
        lock.lock()
        let copy = samples
        lock.unlock()
        return FaceSignals.summary(copy, from: from, to: to)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
        newest = nil
    }
}
