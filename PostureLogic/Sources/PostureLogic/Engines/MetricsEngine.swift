import Foundation
import simd

/// Computes posture metrics from PoseSample, with proper 2D fallback
/// Ticket 3.2: Uses shoulder width as scale reference for 2D mode
public struct MetricsEngine: MetricsEngineProtocol {
    public var debugState: [String: Any] {
        [
            "lastMode": lastMode?.rawValue ?? "none",
            "last2DShoulderWidth": last2DShoulderWidth,
            "lastBaselineShoulderWidth": lastBaselineShoulderWidth
        ]
    }

    private var lastMode: DepthMode?
    private var last2DShoulderWidth: Float = 0
    private var lastBaselineShoulderWidth: Float = 0

    // Movement tracking for movement level calculation
    private var previousSample: PoseSample?
    private var movementHistory: [Float] = []
    private let maxMovementHistory = 10

    public init() {}

    public mutating func compute(from sample: PoseSample, baseline: Baseline?) -> RawMetrics {
        lastMode = sample.depthMode

        // Without baseline, we can't compute deltas - return zeros
        guard let baseline = baseline else {
            return RawMetrics(
                timestamp: sample.timestamp,
                forwardCreep: 0,
                headDrop: 0,
                shoulderRounding: 0,
                lateralLean: 0,
                twist: 0,
                movementLevel: 0,
                headMovementPattern: .still
            )
        }

        lastBaselineShoulderWidth = baseline.shoulderWidth

        // Compute metrics differently based on mode
        if sample.depthMode == .depthFusion {
            return compute3DMetrics(from: sample, baseline: baseline)
        } else {
            return compute2DMetrics(from: sample, baseline: baseline)
        }
    }

    // MARK: - 3D Metrics (Depth Fusion Mode)

    private mutating func compute3DMetrics(from sample: PoseSample, baseline: Baseline) -> RawMetrics {
        // Forward creep: How much closer to camera (positive = worse)
        // In camera space, closer = smaller Z value
        let forwardCreep = baseline.shoulderMidpoint.z - sample.shoulderMidpoint.z

        // Head drop: How much head has dropped (positive = worse)
        let headDrop = baseline.headPosition.y - sample.headPosition.y

        // Shoulder rounding: Use torso angle as proxy
        // Larger angle from vertical = more rounding
        let shoulderRounding = abs(sample.torsoAngle - baseline.torsoAngle)

        // Lateral lean: Side-to-side offset from baseline
        let lateralLean = abs(sample.shoulderMidpoint.x - baseline.shoulderMidpoint.x)

        // Twist: Already computed in PoseSample
        let twist = abs(sample.shoulderTwist)

        // Movement level and pattern
        let movementLevel = computeMovementLevel(from: sample)
        let headMovementPattern = computeHeadMovementPattern(movementLevel: movementLevel)

        // Store for next iteration
        previousSample = sample

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

    // MARK: - 2D Metrics (Fallback Mode)

    /// Ticket 3.2: Compute metrics using only 2D keypoints
    /// Key insight: Use shoulder width as scale reference
    /// All distances expressed as ratios of shoulder width
    private mutating func compute2DMetrics(from sample: PoseSample, baseline: Baseline) -> RawMetrics {
        // Compute current shoulder width (in normalized 2D space)
        let shoulderWidth = distance2D(sample.leftShoulder, sample.rightShoulder)
        last2DShoulderWidth = shoulderWidth

        // Avoid division by zero
        guard shoulderWidth > 0.01 && baseline.shoulderWidth > 0.01 else {
            return RawMetrics(
                timestamp: sample.timestamp,
                forwardCreep: 0,
                headDrop: 0,
                shoulderRounding: 0,
                lateralLean: 0,
                twist: 0,
                movementLevel: 0,
                headMovementPattern: .still
            )
        }

        // Forward creep: In 2D mode, use Y-position change as proxy
        // When leaning forward, head and shoulders move down in frame (higher Y in normalized coords)
        // Normalize by shoulder width to make scale-independent
        let shoulderYDelta = (sample.shoulderMidpoint.y - baseline.shoulderMidpoint.y) / shoulderWidth
        let forwardCreep = max(0, shoulderYDelta) // Only positive values (moving down = leaning forward)

        // Head drop: Vertical distance change, normalized by shoulder width
        // In 2D, head dropping shows as Y coordinate change
        let headYDelta = (sample.headPosition.y - baseline.headPosition.y) / shoulderWidth
        let headDrop = max(0, headYDelta) // Only positive values

        // Head forward offset: Distance between head and shoulder line
        // Normalized by shoulder width
        let headForwardDistance = abs(sample.headPosition.y - sample.shoulderMidpoint.y)
        let baselineHeadDistance = abs(baseline.headPosition.y - baseline.shoulderMidpoint.y)
        let headForwardDelta = (headForwardDistance - baselineHeadDistance) / shoulderWidth

        // Shoulder rounding: Use head-to-shoulder ratio change
        // When rounding forward, the head-shoulder distance changes
        let shoulderRounding = max(0, headForwardDelta)

        // Lateral lean: Horizontal offset from baseline, normalized
        let lateralLean = abs(sample.shoulderMidpoint.x - baseline.shoulderMidpoint.x) / shoulderWidth

        // Twist: In 2D, detect twist by shoulder width change
        // If one shoulder comes forward, apparent shoulder width shrinks
        // Also check for X-position asymmetry
        let shoulderWidthRatio = shoulderWidth / baseline.shoulderWidth
        let widthChange = abs(1.0 - shoulderWidthRatio)

        // Also check shoulder symmetry around midpoint
        let currentLeftDist = abs(sample.leftShoulder.x - sample.shoulderMidpoint.x)
        let currentRightDist = abs(sample.rightShoulder.x - sample.shoulderMidpoint.x)
        let asymmetry = abs(currentLeftDist - currentRightDist) / shoulderWidth

        // Combine width change and asymmetry as proxy for twist
        // Convert to degrees-like scale for consistency with 3D mode (0-30 range)
        let twist = (widthChange + asymmetry) * 30.0

        // Movement level and pattern
        let movementLevel = computeMovementLevel(from: sample)
        let headMovementPattern = computeHeadMovementPattern(movementLevel: movementLevel)

        // Store for next iteration
        previousSample = sample

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

    // MARK: - Movement Analysis

    /// Compute movement level by comparing current sample to previous
    /// Returns 0 (still) to 1 (very active)
    private mutating func computeMovementLevel(from sample: PoseSample) -> Float {
        guard let previous = previousSample else {
            return 0
        }

        // Compute total movement as sum of position changes
        let headDelta = distance3D(sample.headPosition, previous.headPosition)
        let shoulderDelta = distance3D(sample.shoulderMidpoint, previous.shoulderMidpoint)

        // Average the deltas
        let totalMovement = (headDelta + shoulderDelta) / 2.0

        // Normalize: 0.01 units of movement = moderately active
        // Scale to 0-1 range
        let normalizedMovement = min(1.0, totalMovement / 0.01)

        // Add to history and compute moving average
        movementHistory.append(normalizedMovement)
        if movementHistory.count > maxMovementHistory {
            movementHistory.removeFirst()
        }

        // Return average of recent movements for smoothing
        return movementHistory.reduce(0, +) / Float(movementHistory.count)
    }

    /// Infer head movement pattern from movement level
    private func computeHeadMovementPattern(movementLevel: Float) -> MovementPattern {
        if movementLevel < 0.1 {
            return .still
        } else if movementLevel < 0.3 {
            return .smallOscillations
        } else if movementLevel < 0.7 {
            return .largeMovements
        } else {
            return .erratic
        }
    }

    // MARK: - Helper Functions

    private func distance2D(_ p1: SIMD3<Float>, _ p2: SIMD3<Float>) -> Float {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }

    private func distance3D(_ p1: SIMD3<Float>, _ p2: SIMD3<Float>) -> Float {
        return simd_distance(p1, p2)
    }
}
