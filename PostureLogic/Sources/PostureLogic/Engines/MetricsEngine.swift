import Foundation
import simd

struct MetricsEngine: MetricsEngineProtocol {

    // MARK: - Debug State

    private(set) var computeCount: Int = 0
    private(set) var noBaselineCount: Int = 0

    var debugState: [String: Any] {
        [
            "computeCount": computeCount,
            "noBaselineCount": noBaselineCount,
        ]
    }

    init() {}

    // MARK: - MetricsEngineProtocol

    mutating func compute(from sample: PoseSample, baseline: Baseline?) -> RawMetrics {
        guard let baseline = baseline else {
            noBaselineCount += 1
            return zeroMetrics(timestamp: sample.timestamp)
        }

        computeCount += 1

        // Forward creep: wider shoulders in frame = closer to camera
        let forwardCreep: Float
        if baseline.shoulderWidth > 0 {
            forwardCreep = (sample.shoulderWidthRaw - baseline.shoulderWidth) / baseline.shoulderWidth
        } else {
            forwardCreep = 0
        }

        // Head drop: ear-based head carriage against the calibrated neutral. Image y runs down
        // (PoseService flips Vision's), so on the device a head dropping towards the shoulders
        // reads NEGATIVE; see `PostureThresholds.headDropThreshold`.
        // Sourced from `neckHeight` (ear-midpoint height above the shoulders,
        // shoulder-normalized) rather than the nose-relative `headPosition.y`, so it
        // tracks true neck/head carriage and ignores transient look-down/chin-drops.
        let headDrop = baseline.neckHeight - sample.neckHeight

        // Shoulder rounding: more torso angle = more forward lean
        let shoulderRounding = sample.torsoAngle - baseline.torsoAngle

        // Lateral lean: off-center from baseline shoulder midpoint. Signed keeps
        // left/right (for the visualization); magnitude is what scoring thresholds.
        let lateralLeanSigned = sample.shoulderMidpoint.x - baseline.shoulderMidpoint.x
        let lateralLean = abs(lateralLeanSigned)

        // Twist: deviation from baseline shoulder twist. Signed keeps left/right
        // (for the visualization); magnitude is what scoring thresholds.
        let twistSigned = sample.shoulderTwist - baseline.shoulderTwist
        let twist = abs(twistSigned)

        // Movement level: deferred to Ticket 2.5 (requires temporal data)
        let movementLevel: Float = 0

        // Head movement pattern: deferred to Ticket 2.5
        let headMovementPattern: MovementPattern = .still

        // Shoulder sink: the shoulders' drop in the frame, in calibrated shoulder widths. Image y
        // runs down (PoseService flips Vision's), so lower is positive. Only where the midpoint
        // and the width are both image-space: the depth path's midpoint is in metres.
        let shoulderSink: Float
        if sample.depthMode == .twoDOnly, !baseline.depthAvailable, baseline.shoulderWidth > 1e-6 {
            shoulderSink = (sample.shoulderMidpoint.y - baseline.shoulderMidpoint.y) / baseline.shoulderWidth
        } else {
            shoulderSink = 0
        }

        return RawMetrics(
            timestamp: sample.timestamp,
            forwardCreep: forwardCreep,
            headDrop: headDrop,
            shoulderRounding: shoulderRounding,
            lateralLean: lateralLean,
            twist: twist,
            movementLevel: movementLevel,
            headMovementPattern: headMovementPattern,
            lateralLeanSigned: lateralLeanSigned,
            twistSigned: twistSigned,
            shoulderSink: shoulderSink
        )
    }

    // MARK: - Helpers

    private func zeroMetrics(timestamp: TimeInterval) -> RawMetrics {
        RawMetrics(
            timestamp: timestamp,
            forwardCreep: 0,
            headDrop: 0,
            shoulderRounding: 0,
            lateralLean: 0,
            twist: 0,
            movementLevel: 0,
            headMovementPattern: .still
        )
    }
}
