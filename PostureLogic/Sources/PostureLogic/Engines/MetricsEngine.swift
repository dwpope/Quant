import Foundation
import simd

public struct MetricsEngine: MetricsEngineProtocol {

    // MARK: - Debug State

    private(set) var computeCount: Int = 0
    private(set) var noBaselineCount: Int = 0

    public var debugState: [String: Any] {
        [
            "computeCount": computeCount,
            "noBaselineCount": noBaselineCount,
        ]
    }

    public init() {}

    // MARK: - MetricsEngineProtocol

    public mutating func compute(from sample: PoseSample, baseline: Baseline?) -> RawMetrics {
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

        // Head drop: baseline head higher than sample head = positive
        let headDrop = baseline.headPosition.y - sample.headPosition.y

        // Shoulder rounding: more torso angle = more forward lean
        let shoulderRounding = sample.torsoAngle - baseline.torsoAngle

        // Lateral lean: off-center from baseline shoulder midpoint
        let lateralLean = abs(sample.shoulderMidpoint.x - baseline.shoulderMidpoint.x)

        // Twist: deviation from baseline shoulder twist
        let twist = abs(sample.shoulderTwist - baseline.shoulderTwist)

        // Movement level: deferred to Ticket 2.5 (requires temporal data)
        let movementLevel: Float = 0

        // Head movement pattern: deferred to Ticket 2.5
        let headMovementPattern: MovementPattern = .still

        return RawMetrics(
            timestamp: sample.timestamp,
            forwardCreep: forwardCreep,
            headDrop: headDrop,
            shoulderRounding: shoulderRounding,
            lateralLean: lateralLean,
            twist: twist,
            movementLevel: movementLevel,
            headMovementPattern: headMovementPattern
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
