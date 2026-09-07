import Foundation
import simd

/// Applies exponential moving average (EMA) smoothing to posture metrics
/// and computes temporal metrics (movementLevel, headMovementPattern)
/// that require a history of recent samples.
///
/// ## Why `headDrop` gets its own filter
/// Every field except `headDrop` shares the fixed-weight `alpha` EMA (~0.33 s at
/// 10 Hz) — responsive enough for the larger-amplitude creep/lean/twist/rounding
/// signals. `headDrop` is the exception: it is now **ear-sourced carriage**
/// (`baseline.neckHeight − sample.neckHeight`), and the ear barely moves from a
/// front camera, so the real mild→bad separation (~0.013 shoulder-widths) is small
/// relative to keypoint jitter (~±0.01 even after the shared EMA). A heavier fixed
/// EMA would fix the jitter but lag every signal equally. Instead `headDrop` runs
/// through a dedicated ``OneEuroFilter`` — an adaptive low-pass that smooths hard
/// while the head is still (killing the flicker) yet raises its cutoff when the
/// head actually sinks (so a genuine slouch still converges). This leaves `alpha`
/// untouched for the four responsive metrics.
///
/// The One Euro stage is keyed on `sample.timestamp` and is the identity whenever
/// `dt <= 0` (its documented seed / non-advancing-timestamp contract). The camera-
/// free unit tests stamp constant timestamps, so there the `headDrop` filter is a
/// pass-through and the pre-existing exact assertions still hold.
struct MetricsSmoother: DebugDumpable {

    // MARK: - Configuration

    /// EMA blending factor. Higher = more responsive but jittery; lower = smoother but laggy.
    /// Applies to every posture field **except** `headDrop`, which has its own
    /// dedicated adaptive filter (see ``headDropFilter``).
    var alpha: Float

    /// Adaptive denoiser for the ear-sourced `headDrop` signal only.
    ///
    /// Tuned for the ~10 Hz pose cadence against a small-amplitude, jitter-dominated
    /// input. `minCutoff = 0.15 Hz` sets the stationary smoothing floor at
    /// `tau = 1 / (2π·fc) ≈ 1.06 s`, i.e. roughly a 1-second time constant while the
    /// head is held still — deliberately heavy, since posture is slow and ~1 s of lag
    /// on the neck signal is acceptable in exchange for a steady reading. `beta = 6.0`
    /// is large because posture speeds are tiny in these normalized units: a real
    /// slouch moves `headDrop` on the order of a few hundredths per second, and only
    /// a large `beta` lets that speed lift the cutoff enough to cut the lag on a
    /// genuine change while a still head stays pinned at `minCutoff`.
    ///
    /// **Provisional — tune on device** against the now-smoothed live signal, in
    /// concert with `PostureThresholds.headDropThreshold`.
    private var headDropFilter = OneEuroFilter(
        minCutoff: headDropMinCutoff,
        beta: headDropBeta
    )

    /// Stationary-cutoff floor (Hz) for the `headDrop` One Euro filter. See
    /// ``headDropFilter`` for the time-constant derivation. Provisional.
    static let headDropMinCutoff: Float = 0.15

    /// Speed coefficient for the `headDrop` One Euro filter. See ``headDropFilter``.
    /// Provisional.
    static let headDropBeta: Float = 6.0

    // MARK: - Debug State

    var debugState: [String: Any] {
        [
            "alpha": alpha,
            "headDropMinCutoff": Self.headDropMinCutoff,
            "headDropBeta": Self.headDropBeta,
            "headDropFiltered": headDropFilter.value,
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

    init(alpha: Float = 0.3) {
        self.alpha = alpha
    }

    // MARK: - Public API

    /// Smooths raw metrics using EMA and computes temporal fields (movementLevel, headMovementPattern).
    ///
    /// - Parameters:
    ///   - current: Raw metrics from MetricsEngine
    ///   - sample: The PoseSample that produced these metrics (needed for position deltas)
    /// - Returns: Smoothed metrics with temporal fields populated
    mutating func smooth(_ current: RawMetrics, sample: PoseSample) -> RawMetrics {
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

        // `headDrop` bypasses the shared EMA and rides its own adaptive filter,
        // keyed on the sample's timestamp. The filter seeds on the first sample
        // (returns it raw) and is the identity whenever `dt <= 0`, so the first-
        // sample passthrough and the constant-timestamp unit tests are unaffected.
        let filteredHeadDrop = headDropFilter.update(current.headDrop, timestamp: sample.timestamp)

        guard let prev = previous else {
            // First sample: pass through posture metrics unsmoothed
            let result = RawMetrics(
                timestamp: current.timestamp,
                forwardCreep: current.forwardCreep,
                headDrop: filteredHeadDrop,
                shoulderRounding: current.shoulderRounding,
                lateralLean: current.lateralLean,
                twist: current.twist,
                movementLevel: movementLevel,
                headMovementPattern: headPattern,
                lateralLeanSigned: current.lateralLeanSigned,
                twistSigned: current.twistSigned
            )
            previous = result
            return result
        }

        let smoothed = RawMetrics(
            timestamp: current.timestamp,
            forwardCreep: lerp(prev.forwardCreep, current.forwardCreep, alpha),
            headDrop: filteredHeadDrop,
            shoulderRounding: lerp(prev.shoulderRounding, current.shoulderRounding, alpha),
            lateralLean: lerp(prev.lateralLean, current.lateralLean, alpha),
            twist: lerp(prev.twist, current.twist, alpha),
            movementLevel: movementLevel,
            headMovementPattern: headPattern,
            lateralLeanSigned: lerp(prev.lateralLeanSigned, current.lateralLeanSigned, alpha),
            twistSigned: lerp(prev.twistSigned, current.twistSigned, alpha)
        )

        previous = smoothed
        return smoothed
    }

    /// Resets all internal state. Call when baseline changes or user re-enters frame.
    mutating func reset() {
        previous = nil
        previousSample = nil
        recentHeadPositions.removeAll()
        sampleCount = 0
        lastMovementLevel = 0
        lastHeadPattern = .still
        headDropFilter.reset()   // re-seed the neck signal on the next sample
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
