import Foundation
import simd

/// Applies exponential moving average (EMA) smoothing to posture metrics
/// and computes temporal metrics (movementLevel, headMovementPattern)
/// that require a history of recent samples.
public struct MetricsSmoother: DebugDumpable {

    // MARK: - Configuration

    /// EMA blending factor. Higher = more responsive but jittery; lower = smoother but laggy.
    public var alpha: Float

    // MARK: - Debug State

    public var debugState: [String: Any] {
        [
            "alpha": alpha,
            "sampleCount": sampleCount,
            "headWindowCount": recentHeadPositions.count,
            "lastMovementLevel": lastMovementLevel,
            "lastHeadPattern": lastHeadPattern.rawValue,
        ]
    }

    // MARK: - Internal State

    private var previous: RawMetrics?
    private var previousSample: PoseSample?
    private var recentHeadPositions: [(timestamp: TimeInterval, position: SIMD3<Float>)] = []
    private var sampleCount: Int = 0
    private var lastMovementLevel: Float = 0
    private var lastHeadPattern: MovementPattern = .still

    /// Number of head positions to keep for pattern classification (~3 seconds at 10 FPS).
    private let headWindowSize = 30

    // MARK: - Initialization

    public init(alpha: Float = 0.3) {
        self.alpha = alpha
    }

    // MARK: - Public API

    /// Smooths raw metrics using EMA and computes temporal fields (movementLevel, headMovementPattern).
    ///
    /// - Parameters:
    ///   - current: Raw metrics from MetricsEngine
    ///   - sample: The PoseSample that produced these metrics (needed for position deltas)
    /// - Returns: Smoothed metrics with temporal fields populated
    public mutating func smooth(_ current: RawMetrics, sample: PoseSample) -> RawMetrics {
        sampleCount += 1

        // Compute movement level from position delta
        let movementLevel = computeMovementLevel(current: sample)
        lastMovementLevel = movementLevel

        // Track head positions for pattern classification
        updateHeadWindow(sample: sample)
        let headPattern = classifyHeadPattern()
        lastHeadPattern = headPattern

        defer {
            previousSample = sample
        }

        guard let prev = previous else {
            // First sample: pass through posture metrics unsmoothed
            let result = RawMetrics(
                timestamp: current.timestamp,
                forwardCreep: current.forwardCreep,
                headDrop: current.headDrop,
                shoulderRounding: current.shoulderRounding,
                lateralLean: current.lateralLean,
                twist: current.twist,
                movementLevel: movementLevel,
                headMovementPattern: headPattern
            )
            previous = result
            return result
        }

        let smoothed = RawMetrics(
            timestamp: current.timestamp,
            forwardCreep: lerp(prev.forwardCreep, current.forwardCreep, alpha),
            headDrop: lerp(prev.headDrop, current.headDrop, alpha),
            shoulderRounding: lerp(prev.shoulderRounding, current.shoulderRounding, alpha),
            lateralLean: lerp(prev.lateralLean, current.lateralLean, alpha),
            twist: lerp(prev.twist, current.twist, alpha),
            movementLevel: movementLevel,
            headMovementPattern: headPattern
        )

        previous = smoothed
        return smoothed
    }

    /// Resets all internal state. Call when baseline changes or user re-enters frame.
    public mutating func reset() {
        previous = nil
        previousSample = nil
        recentHeadPositions.removeAll()
        sampleCount = 0
        lastMovementLevel = 0
        lastHeadPattern = .still
    }

    // MARK: - Movement Level

    /// Computes instantaneous movement level (0-1) from frame-to-frame position change.
    private func computeMovementLevel(current: PoseSample) -> Float {
        guard let prev = previousSample else { return 0 }

        let dt = current.timestamp - prev.timestamp
        guard dt > 0 else { return 0 }

        // Compute displacement of key body points
        let shoulderDelta = simd_length(current.shoulderMidpoint - prev.shoulderMidpoint)
        let headDelta = simd_length(current.headPosition - prev.headPosition)

        // Average displacement, normalized by time to get velocity
        let velocity = (shoulderDelta + headDelta) / (2.0 * Float(dt))

        // Normalize to 0-1 range:
        // 0.0 velocity → 0.0 movement
        // 0.5+ normalized units/sec → 1.0 movement (very active)
        let maxVelocity: Float = 0.5
        return min(velocity / maxVelocity, 1.0)
    }

    // MARK: - Head Movement Pattern

    private mutating func updateHeadWindow(sample: PoseSample) {
        recentHeadPositions.append((timestamp: sample.timestamp, position: sample.headPosition))
        if recentHeadPositions.count > headWindowSize {
            recentHeadPositions.removeFirst()
        }
    }

    /// Classifies head movement pattern from the sliding window of recent positions.
    private func classifyHeadPattern() -> MovementPattern {
        guard recentHeadPositions.count >= 5 else { return .still }

        // Compute frame-to-frame displacements
        var displacements: [Float] = []
        for i in 1..<recentHeadPositions.count {
            let delta = simd_length(recentHeadPositions[i].position - recentHeadPositions[i - 1].position)
            displacements.append(delta)
        }

        let meanDisplacement = displacements.reduce(0, +) / Float(displacements.count)

        // Compute variance of displacements to distinguish regular from erratic
        let variance: Float = displacements.reduce(0) { sum, d in
            let diff = d - meanDisplacement
            return sum + diff * diff
        } / Float(displacements.count)

        // Classification thresholds (in normalized coordinate space)
        let stillThreshold: Float = 0.005
        let smallOscThreshold: Float = 0.02
        let largeThreshold: Float = 0.06
        let erraticVarianceThreshold: Float = 0.001

        if meanDisplacement < stillThreshold {
            return .still
        }

        if meanDisplacement < smallOscThreshold {
            return .smallOscillations
        }

        if variance > erraticVarianceThreshold && meanDisplacement < largeThreshold {
            return .erratic
        }

        return .largeMovements
    }

    // MARK: - Helpers

    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }
}
