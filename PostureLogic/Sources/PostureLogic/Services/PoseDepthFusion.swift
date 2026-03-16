import CoreGraphics
import Foundation
import simd

/// Converts a 2D `PoseObservation` into a shoulder-width-normalized `PoseSample`.
///
/// All positions are expressed relative to the shoulder midpoint and divided by
/// shoulder width, making them scale-invariant regardless of camera distance.
/// In `twoDOnly` mode all z-values are 0. When depth is available with sufficient
/// confidence, uses `unproject()` to produce 3D positions in `depthFusion` mode.
public struct PoseDepthFusion: PoseDepthFusionProtocol {

    // MARK: - Constants

    private static let minKeypointConfidence: Float = 0.3
    private static let minShoulderWidth: CGFloat = 0.01
    private static let edgeMargin: CGFloat = 0.05  // Ignore depth within 5% of frame edges
    private static let minDepthSampleConfidence: Float = 0.5

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
        intrinsics: simd_float3x3?,
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

        // Attempt 3D fusion when depth is available with sufficient confidence
        if confidence >= .medium,
           let samples = depthSamples,
           let intr = intrinsics {
            if let sample3D = fuse3D(
                pose: pose,
                leftShoulder: leftShoulder,
                rightShoulder: rightShoulder,
                headPos: headPos,
                shoulderWidth: shoulderWidth,
                depthSamples: samples,
                intrinsics: intr,
                trackingQuality: trackingQuality
            ) {
                return sample3D
            }
        }

        // Fallback: 2D-only path
        return fuse2D(
            pose: pose,
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            headPos: headPos,
            shoulderWidth: shoulderWidth,
            trackingQuality: trackingQuality
        )
    }

    // MARK: - 2D Fusion (existing path)

    private func fuse2D(
        pose: PoseObservation,
        leftShoulder: Keypoint,
        rightShoulder: Keypoint,
        headPos: CGPoint,
        shoulderWidth: CGFloat,
        trackingQuality: TrackingQuality
    ) -> PoseSample {
        let midX = (leftShoulder.position.x + rightShoulder.position.x) / 2
        let midY = (leftShoulder.position.y + rightShoulder.position.y) / 2

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
            shoulderMidpoint: SIMD3<Float>(Float(midX), Float(midY), 0),
            leftShoulder: normLeftShoulder,
            rightShoulder: normRightShoulder,
            torsoAngle: torsoAngle,
            headForwardOffset: 0,
            shoulderTwist: shoulderTwist,
            shoulderWidthRaw: Float(shoulderWidth),
            trackingQuality: trackingQuality
        )
    }

    // MARK: - 3D Fusion (depth-enhanced path)

    private func fuse3D(
        pose: PoseObservation,
        leftShoulder: Keypoint,
        rightShoulder: Keypoint,
        headPos: CGPoint,
        shoulderWidth: CGFloat,
        depthSamples: [DepthAtPoint],
        intrinsics: simd_float3x3,
        trackingQuality: TrackingQuality
    ) -> PoseSample? {
        // Find depth for each critical keypoint
        guard let lsDepth = findDepth(for: leftShoulder.position, in: depthSamples),
              let rsDepth = findDepth(for: rightShoulder.position, in: depthSamples),
              let headDepth = findDepth(for: headPos, in: depthSamples)
        else {
            return nil  // Fall back to 2D if any critical depth is missing
        }

        // Unproject to 3D camera space
        let ls3D = unproject(
            point: SIMD2<Float>(Float(leftShoulder.position.x), Float(leftShoulder.position.y)),
            depth: lsDepth,
            intrinsics: intrinsics
        )
        let rs3D = unproject(
            point: SIMD2<Float>(Float(rightShoulder.position.x), Float(rightShoulder.position.y)),
            depth: rsDepth,
            intrinsics: intrinsics
        )
        let head3D = unproject(
            point: SIMD2<Float>(Float(headPos.x), Float(headPos.y)),
            depth: headDepth,
            intrinsics: intrinsics
        )

        // 3D shoulder midpoint
        let mid3D = (ls3D + rs3D) / 2

        // 3D shoulder width for normalization
        let shoulderWidth3D = simd_length(ls3D - rs3D)
        guard shoulderWidth3D > 0.01 else {
            return nil  // Degenerate 3D shoulder width
        }

        // Normalize positions relative to 3D midpoint, divided by 3D shoulder width
        let normLeftShoulder = (ls3D - mid3D) / shoulderWidth3D
        let normRightShoulder = (rs3D - mid3D) / shoulderWidth3D
        let normHead = (head3D - mid3D) / shoulderWidth3D

        // Head forward offset: z-difference between head and shoulder midpoint
        // Positive = head is further from camera than shoulders (leaning back)
        // Negative = head is closer to camera than shoulders (leaning forward)
        let headForwardOffset = head3D.z - mid3D.z

        // Shoulder twist using 3D: angle from y-difference in 3D space
        let yDiff3D = ls3D.y - rs3D.y
        let twistRatio = yDiff3D / shoulderWidth3D
        let clampedTwist = max(-1, min(twistRatio, 1))
        let shoulderTwist = asin(clampedTwist) * (180.0 / .pi)

        // Torso angle using 3D: use z-offset as proxy for forward lean
        // atan2(|z-offset|, y-extent) gives forward lean in 3D
        let torsoAngle = computeTorsoAngle(
            pose: pose,
            shoulderMidX: CGFloat(mid3D.x),
            shoulderMidY: CGFloat(mid3D.y),
            shoulderWidth: CGFloat(shoulderWidth3D),
            headPos: headPos
        )

        return PoseSample(
            timestamp: pose.timestamp,
            depthMode: .depthFusion,
            headPosition: normHead,
            shoulderMidpoint: mid3D,
            leftShoulder: normLeftShoulder,
            rightShoulder: normRightShoulder,
            torsoAngle: torsoAngle,
            headForwardOffset: headForwardOffset,
            shoulderTwist: shoulderTwist,
            shoulderWidthRaw: Float(shoulderWidth),
            trackingQuality: trackingQuality
        )
    }

    // MARK: - Depth Lookup

    /// Finds the depth value for a given 2D point from the depth samples.
    /// Returns nil if the point is near a frame edge or has low confidence.
    private func findDepth(for point: CGPoint, in samples: [DepthAtPoint]) -> Float? {
        // Ignore points near edges (within 5% of frame boundaries)
        if isNearEdge(point) {
            return nil
        }

        // Find the sample closest to this point
        let threshold: CGFloat = 0.01  // Match within 1% of frame
        guard let match = samples.min(by: {
            hypot($0.point.x - point.x, $0.point.y - point.y) <
            hypot($1.point.x - point.x, $1.point.y - point.y)
        }) else {
            return nil
        }

        let dist = hypot(match.point.x - point.x, match.point.y - point.y)
        guard dist < threshold else {
            return nil
        }

        // Check confidence and validity
        guard match.confidence >= Self.minDepthSampleConfidence,
              match.depth > 0,
              match.depth.isFinite
        else {
            return nil
        }

        return match.depth
    }

    /// Returns true if the point is within the edge margin (5% of frame boundaries).
    private func isNearEdge(_ point: CGPoint) -> Bool {
        point.x < Self.edgeMargin || point.x > (1.0 - Self.edgeMargin) ||
        point.y < Self.edgeMargin || point.y > (1.0 - Self.edgeMargin)
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
    ///
    /// Note: Vision framework uses y-up coordinates (0 at bottom, 1 at top).
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
            // Vision y-up: shoulders above hips → shoulderMidY > hipMidY when upright
            let dy = shoulderMidY - hipMidY
            // atan2(|dx|, dy) gives 0 when upright, increases with lean
            return Float(atan2(dx, dy)) * (180.0 / .pi)
        }

        // Fallback: map head-shoulder vertical distance ratio to pseudo-angle
        // Vision y-up: head.y > shoulderMid.y when upright
        let headVerticalOffset = headPos.y - shoulderMidY
        let ratio = headVerticalOffset / shoulderWidth
        // Map ratio: 1.2 → 0°, 0.0 → 45° (linear interpolation, clamped)
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
