import CoreGraphics
import Foundation
import simd

/// Converts a 2D `PoseObservation` into a shoulder-width-normalized `PoseSample`.
///
/// All positions are expressed relative to the shoulder midpoint and divided by
/// shoulder width, making them scale-invariant regardless of camera distance.
/// In `twoDOnly` mode all z-values are 0.
public struct PoseDepthFusion: PoseDepthFusionProtocol {

    // MARK: - Constants

    private static let minKeypointConfidence: Float = 0.3
    private static let minShoulderWidth: CGFloat = 0.01

    // MARK: - Debug State

    private(set) var lastShoulderWidth: CGFloat = 0
    private(set) var lastHeadPosition: CGPoint = .zero
    private(set) var fusionCount: Int = 0
    private(set) var missingKeypointCount: Int = 0

    public var debugState: [String: Any] {
        [
            "lastShoulderWidth": lastShoulderWidth,
            "lastHeadPosition": [lastHeadPosition.x, lastHeadPosition.y],
            "fusionCount": fusionCount,
            "missingKeypointCount": missingKeypointCount,
        ]
    }

    public init() {}

    // MARK: - PoseDepthFusionProtocol

    public mutating func fuse(
        pose: PoseObservation,
        depthSamples: [DepthAtPoint]?,
        confidence: DepthConfidence,
        trackingQuality: TrackingQuality
    ) -> PoseSample? {
        // Extract required keypoints
        guard let leftShoulder = keypoint(.leftShoulder, from: pose),
              let rightShoulder = keypoint(.rightShoulder, from: pose)
        else {
            missingKeypointCount += 1
            return nil
        }

        guard let headPos = resolveHeadPosition(from: pose) else {
            missingKeypointCount += 1
            return nil
        }

        // Guard degenerate shoulder width
        let shoulderWidth = distance(leftShoulder.position, rightShoulder.position)
        guard shoulderWidth > Self.minShoulderWidth else {
            missingKeypointCount += 1
            return nil
        }

        // Update debug state
        lastShoulderWidth = shoulderWidth
        lastHeadPosition = headPos
        fusionCount += 1

        // Shoulder midpoint in image coords
        let midX = (leftShoulder.position.x + rightShoulder.position.x) / 2
        let midY = (leftShoulder.position.y + rightShoulder.position.y) / 2

        // Normalized positions (relative to midpoint, divided by shoulder width)
        let normLeftShoulder = SIMD3<Float>(
            Float((leftShoulder.position.x - midX) / shoulderWidth),
            Float((leftShoulder.position.y - midY) / shoulderWidth),
            0
        )
        let normRightShoulder = SIMD3<Float>(
            Float((rightShoulder.position.x - midX) / shoulderWidth),
            Float((rightShoulder.position.y - midY) / shoulderWidth),
            0
        )
        let normHead = SIMD3<Float>(
            Float((headPos.x - midX) / shoulderWidth),
            Float((headPos.y - midY) / shoulderWidth),
            0
        )

        // Derived angles
        let torsoAngle = computeTorsoAngle(
            pose: pose,
            shoulderMidX: midX,
            shoulderMidY: midY,
            shoulderWidth: shoulderWidth,
            headPos: headPos
        )
        let shoulderTwist = computeShoulderTwist(
            leftShoulder: leftShoulder.position,
            rightShoulder: rightShoulder.position,
            shoulderWidth: shoulderWidth
        )

        return PoseSample(
            timestamp: pose.timestamp,
            depthMode: .twoDOnly,
            headPosition: normHead,
            shoulderMidpoint: SIMD3<Float>(0, 0, 0),
            leftShoulder: normLeftShoulder,
            rightShoulder: normRightShoulder,
            torsoAngle: torsoAngle,
            headForwardOffset: 0,  // z-axis unobservable in 2D
            shoulderTwist: shoulderTwist,
            shoulderWidthRaw: Float(shoulderWidth),
            trackingQuality: trackingQuality
        )
    }

    // MARK: - Head Fallback Chain

    /// Resolves head position using fallback chain: nose → eye midpoint → single eye → ear midpoint → nil
    private func resolveHeadPosition(from pose: PoseObservation) -> CGPoint? {
        // 1. Nose
        if let nose = keypoint(.nose, from: pose) {
            return nose.position
        }

        // 2. Eye midpoint
        let leftEye = keypoint(.leftEye, from: pose)
        let rightEye = keypoint(.rightEye, from: pose)
        if let le = leftEye, let re = rightEye {
            return CGPoint(
                x: (le.position.x + re.position.x) / 2,
                y: (le.position.y + re.position.y) / 2
            )
        }

        // 3. Single eye
        if let eye = leftEye ?? rightEye {
            return eye.position
        }

        // 4. Ear midpoint
        let leftEar = keypoint(.leftEar, from: pose)
        let rightEar = keypoint(.rightEar, from: pose)
        if let le = leftEar, let re = rightEar {
            return CGPoint(
                x: (le.position.x + re.position.x) / 2,
                y: (le.position.y + re.position.y) / 2
            )
        }

        return nil
    }

    // MARK: - Angle Computation

    /// Computes torso forward lean angle in degrees.
    /// If hips visible: `atan2(|dx|, dy)` of hip→shoulder vector.
    /// Fallback: head-shoulder vertical ratio mapped to pseudo-angle.
    private func computeTorsoAngle(
        pose: PoseObservation,
        shoulderMidX: CGFloat,
        shoulderMidY: CGFloat,
        shoulderWidth: CGFloat,
        headPos: CGPoint
    ) -> Float {
        // Try hip-based calculation first
        let leftHip = keypoint(.leftHip, from: pose)
        let rightHip = keypoint(.rightHip, from: pose)

        if let lh = leftHip, let rh = rightHip {
            let hipMidX = (lh.position.x + rh.position.x) / 2
            let hipMidY = (lh.position.y + rh.position.y) / 2
            let dx = abs(shoulderMidX - hipMidX)
            let dy = shoulderMidY - hipMidY
            // atan2(|dx|, dy) gives 0 when upright, increases with lean
            return Float(atan2(dx, dy)) * (180.0 / .pi)
        }

        // Fallback: map head-shoulder vertical distance ratio to pseudo-angle
        // When upright, head is ~1.0-1.5 shoulder-widths above shoulders
        // As user leans forward, this ratio decreases
        let headVerticalOffset = headPos.y - shoulderMidY
        let ratio = headVerticalOffset / shoulderWidth
        // Map ratio: 1.2 → 0°, 0.0 → 45°  (linear interpolation, clamped)
        let normalizedRatio = max(0, min(Float(ratio) / 1.2, 1.0))
        return (1.0 - normalizedRatio) * 45.0
    }

    /// `asin(yDiff / shoulderWidth)` in degrees. Positive = left shoulder higher.
    private func computeShoulderTwist(
        leftShoulder: CGPoint,
        rightShoulder: CGPoint,
        shoulderWidth: CGFloat
    ) -> Float {
        let yDiff = leftShoulder.y - rightShoulder.y
        let ratio = Float(yDiff / shoulderWidth)
        // Clamp to valid asin range
        let clamped = max(-1, min(ratio, 1))
        return asin(clamped) * (180.0 / .pi)
    }

    // MARK: - Helpers

    private func keypoint(_ joint: Joint, from pose: PoseObservation) -> Keypoint? {
        pose.keypoints.first {
            $0.joint == joint && $0.confidence >= Self.minKeypointConfidence
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
