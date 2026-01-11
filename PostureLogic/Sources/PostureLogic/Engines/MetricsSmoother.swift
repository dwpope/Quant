import Foundation

/// Applies temporal smoothing to metrics to reduce jitter
/// Ticket 3.4: Uses exponential moving average (EMA) with configurable alpha
/// Higher alpha = more responsive but more jittery
/// Lower alpha = smoother but less responsive to real changes
public struct MetricsSmoother: MetricsSmootherProtocol {
    public var debugState: [String: Any] {
        [
            "alpha": alpha,
            "hasPrevious": previous != nil
        ]
    }

    /// Smoothing factor: 0 = no change (ignore new), 1 = no smoothing (use new completely)
    /// Default 0.3 balances responsiveness with smoothing
    public var alpha: Float

    /// Previous smoothed metrics for EMA calculation
    private var previous: RawMetrics?

    public init(alpha: Float = 0.3) {
        self.alpha = alpha
    }

    /// Apply exponential moving average smoothing to metrics
    /// First call returns the input unchanged (no previous value to smooth with)
    /// Subsequent calls blend with previous: smoothed = alpha * current + (1 - alpha) * previous
    public mutating func smooth(_ current: RawMetrics) -> RawMetrics {
        guard let prev = previous else {
            // First sample - no smoothing possible
            previous = current
            return current
        }

        // Apply EMA to all numeric fields
        let smoothed = RawMetrics(
            timestamp: current.timestamp,  // Don't smooth timestamp
            forwardCreep: lerp(prev.forwardCreep, current.forwardCreep, alpha),
            headDrop: lerp(prev.headDrop, current.headDrop, alpha),
            shoulderRounding: lerp(prev.shoulderRounding, current.shoulderRounding, alpha),
            lateralLean: lerp(prev.lateralLean, current.lateralLean, alpha),
            twist: lerp(prev.twist, current.twist, alpha),
            movementLevel: lerp(prev.movementLevel, current.movementLevel, alpha),
            headMovementPattern: current.headMovementPattern  // Don't smooth enum
        )

        previous = smoothed
        return smoothed
    }

    /// Reset smoother state (clears previous value)
    public mutating func reset() {
        previous = nil
    }

    // MARK: - Helper Functions

    /// Linear interpolation: lerp(a, b, t) = a + t * (b - a)
    /// When t = 0, returns a
    /// When t = 1, returns b
    /// For EMA: smoothed = prev + alpha * (current - prev) = (1 - alpha) * prev + alpha * current
    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + t * (b - a)
    }
}
