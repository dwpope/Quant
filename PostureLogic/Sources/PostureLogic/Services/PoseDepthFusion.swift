import Foundation
import CoreGraphics
import simd

/// Fuses pose detection (2D keypoints) with depth data to produce unified PoseSample
public struct PoseDepthFusion: PoseDepthFusionProtocol {
    public var debugState: [String: Any] {
        [
            "lastMode": lastMode.rawValue,
            "lastKeypointCount": lastKeypointCount,
            "last3DPointsComputed": last3DPointsComputed
        ]
    }

    private var lastMode: DepthMode = .twoDOnly
    private var lastKeypointCount: Int = 0
    private var last3DPointsComputed: Int = 0

    public init() {}

    public mutating func fuse(
        pose: PoseObservation,
        depthSamples: [DepthAtPoint]?,
        confidence: DepthConfidence,
        cameraIntrinsics: simd_float3x3?
    ) -> PoseSample {
        lastKeypointCount = pose.keypoints.count

        // Determine which mode to use
        let mode: DepthMode = (confidence >= .medium && depthSamples != nil && cameraIntrinsics != nil) ? .depthFusion : .twoDOnly
        lastMode = mode

        // Extract critical keypoints
        let criticalKeypoints = extractCriticalKeypoints(from: pose)

        // Determine tracking quality based on keypoint availability
        let trackingQuality = determineTrackingQuality(keypoints: criticalKeypoints, poseConfidence: pose.confidence)

        // Compute positions (3D or 2D)
        let positions: KeypointPositions
        if mode == .depthFusion, let intrinsics = cameraIntrinsics, let samples = depthSamples {
            positions = compute3DPositions(keypoints: criticalKeypoints, depthSamples: samples, intrinsics: intrinsics)
            last3DPointsComputed = positions.validCount
        } else {
            positions = compute2DPositions(keypoints: criticalKeypoints)
            last3DPointsComputed = 0
        }

        // Calculate derived metrics
        let torsoAngle = calculateTorsoAngle(
            shoulderMid: positions.shoulderMidpoint,
            mode: mode
        )

        let headForwardOffset = calculateHeadForwardOffset(
            head: positions.head,
            shoulderMid: positions.shoulderMidpoint,
            mode: mode
        )

        let shoulderTwist = calculateShoulderTwist(
            leftShoulder: positions.leftShoulder,
            rightShoulder: positions.rightShoulder,
            mode: mode
        )

        return PoseSample(
            timestamp: pose.timestamp,
            depthMode: mode,
            headPosition: positions.head,
            shoulderMidpoint: positions.shoulderMidpoint,
            leftShoulder: positions.leftShoulder,
            rightShoulder: positions.rightShoulder,
            torsoAngle: torsoAngle,
            headForwardOffset: headForwardOffset,
            shoulderTwist: shoulderTwist,
            trackingQuality: trackingQuality
        )
    }

    // MARK: - Keypoint Extraction

    private struct CriticalKeypoints {
        let nose: Keypoint?
        let leftShoulder: Keypoint?
        let rightShoulder: Keypoint?
        let leftHip: Keypoint?
        let rightHip: Keypoint?

        var hasMinimumRequired: Bool {
            // Need at least both shoulders and nose/head
            return leftShoulder != nil && rightShoulder != nil && nose != nil
        }
    }

    private func extractCriticalKeypoints(from pose: PoseObservation) -> CriticalKeypoints {
        var nose: Keypoint?
        var leftShoulder: Keypoint?
        var rightShoulder: Keypoint?
        var leftHip: Keypoint?
        var rightHip: Keypoint?

        for keypoint in pose.keypoints {
            switch keypoint.joint {
            case .nose:
                nose = keypoint
            case .leftShoulder:
                leftShoulder = keypoint
            case .rightShoulder:
                rightShoulder = keypoint
            case .leftHip:
                leftHip = keypoint
            case .rightHip:
                rightHip = keypoint
            default:
                break
            }
        }

        return CriticalKeypoints(
            nose: nose,
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            leftHip: leftHip,
            rightHip: rightHip
        )
    }

    // MARK: - Tracking Quality

    private func determineTrackingQuality(keypoints: CriticalKeypoints, poseConfidence: Float) -> TrackingQuality {
        // Need minimum keypoints
        guard keypoints.hasMinimumRequired else {
            return .lost
        }

        // Check confidence levels
        let avgConfidence = [
            keypoints.nose?.confidence ?? 0,
            keypoints.leftShoulder?.confidence ?? 0,
            keypoints.rightShoulder?.confidence ?? 0
        ].reduce(0, +) / 3.0

        if avgConfidence > 0.7 && poseConfidence > 0.7 {
            return .good
        } else if avgConfidence > 0.4 {
            return .degraded
        } else {
            return .lost
        }
    }

    // MARK: - 3D Position Computation

    private struct KeypointPositions {
        let head: SIMD3<Float>
        let shoulderMidpoint: SIMD3<Float>
        let leftShoulder: SIMD3<Float>
        let rightShoulder: SIMD3<Float>
        let validCount: Int
    }

    private func compute3DPositions(
        keypoints: CriticalKeypoints,
        depthSamples: [DepthAtPoint],
        intrinsics: simd_float3x3
    ) -> KeypointPositions {
        var validCount = 0

        // Unproject each keypoint using depth data
        let head = unproject(
            keypoint: keypoints.nose,
            depthSamples: depthSamples,
            intrinsics: intrinsics
        )
        if head != .zero { validCount += 1 }

        let leftShoulder = unproject(
            keypoint: keypoints.leftShoulder,
            depthSamples: depthSamples,
            intrinsics: intrinsics
        )
        if leftShoulder != .zero { validCount += 1 }

        let rightShoulder = unproject(
            keypoint: keypoints.rightShoulder,
            depthSamples: depthSamples,
            intrinsics: intrinsics
        )
        if rightShoulder != .zero { validCount += 1 }

        // Calculate shoulder midpoint
        let shoulderMid = (leftShoulder + rightShoulder) / 2.0

        return KeypointPositions(
            head: head,
            shoulderMidpoint: shoulderMid,
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            validCount: validCount
        )
    }

    /// Unproject a 2D keypoint to 3D world coordinates using depth and camera intrinsics
    /// Note: This implements the formula from Ticket 3.1 with proper column-major intrinsics access
    private func unproject(
        keypoint: Keypoint?,
        depthSamples: [DepthAtPoint],
        intrinsics: simd_float3x3
    ) -> SIMD3<Float> {
        guard let kp = keypoint else { return .zero }

        // Find matching depth sample for this keypoint position
        guard let depthSample = findDepthSample(for: kp.position, in: depthSamples) else {
            return .zero
        }

        // Validate depth
        guard depthSample.depth > 0 && depthSample.confidence > 0.5 else {
            return .zero
        }

        // Extract camera intrinsics (column-major ordering per Known Gotchas)
        let fx = intrinsics[0, 0]  // Focal length X
        let fy = intrinsics[1, 1]  // Focal length Y
        let cx = intrinsics[2, 0]  // Principal point X
        let cy = intrinsics[2, 1]  // Principal point Y

        let depth = depthSample.depth

        // Unproject to 3D
        let x = (Float(kp.position.x) - cx) * depth / fx
        let y = (Float(kp.position.y) - cy) * depth / fy
        let z = depth

        return SIMD3(x, y, z)
    }

    private func findDepthSample(for position: CGPoint, in samples: [DepthAtPoint]) -> DepthAtPoint? {
        // Find the closest depth sample to this keypoint
        // In practice, depthSamples should be pre-computed for each keypoint position
        // For now, find the nearest sample
        let closest = samples.min { a, b in
            let distA = distance(a.point, position)
            let distB = distance(b.point, position)
            return distA < distB
        }

        // Only accept if close enough (within 5% of frame)
        if let sample = closest, distance(sample.point, position) < 0.05 {
            return sample
        }

        return nil
    }

    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }

    // MARK: - 2D Position Computation

    private func compute2DPositions(keypoints: CriticalKeypoints) -> KeypointPositions {
        // In 2D mode, we use normalized coordinates (0-1)
        // Z component represents relative depth based on Y position (higher = further)

        let head = keypoints.nose.map { kp in
            SIMD3<Float>(Float(kp.position.x), Float(kp.position.y), 0)
        } ?? .zero

        let leftShoulder = keypoints.leftShoulder.map { kp in
            SIMD3<Float>(Float(kp.position.x), Float(kp.position.y), 0)
        } ?? .zero

        let rightShoulder = keypoints.rightShoulder.map { kp in
            SIMD3<Float>(Float(kp.position.x), Float(kp.position.y), 0)
        } ?? .zero

        let shoulderMid = (leftShoulder + rightShoulder) / 2.0

        return KeypointPositions(
            head: head,
            shoulderMidpoint: shoulderMid,
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            validCount: 3  // In 2D mode, if we have keypoints, they're all "valid"
        )
    }

    // MARK: - Derived Metrics

    private func calculateTorsoAngle(shoulderMid: SIMD3<Float>, mode: DepthMode) -> Float {
        if mode == .depthFusion {
            // In 3D mode, calculate angle from vertical using Z component
            // Angle = atan2(z_offset, vertical_component)
            // For now, return 0 as we need more context about vertical reference
            return 0.0
        } else {
            // In 2D mode, we can't accurately measure torso angle
            return 0.0
        }
    }

    private func calculateHeadForwardOffset(head: SIMD3<Float>, shoulderMid: SIMD3<Float>, mode: DepthMode) -> Float {
        if mode == .depthFusion {
            // In 3D mode, compute how far forward (closer to camera) the head is vs shoulders
            // Positive = head is closer than shoulders (leaning forward)
            return shoulderMid.z - head.z
        } else {
            // In 2D mode, use Y difference as proxy (head lower = potentially leaning forward)
            // Scale by shoulder width for normalization
            let shoulderWidth = 0.4  // Assume normalized shoulder width
            return (head.y - shoulderMid.y) / Float(shoulderWidth)
        }
    }

    private func calculateShoulderTwist(leftShoulder: SIMD3<Float>, rightShoulder: SIMD3<Float>, mode: DepthMode) -> Float {
        if mode == .depthFusion {
            // In 3D mode, calculate rotation based on Z-difference between shoulders
            let zDiff = leftShoulder.z - rightShoulder.z
            let shoulderWidth = distance3D(leftShoulder, rightShoulder)

            guard shoulderWidth > 0 else { return 0 }

            // Calculate angle in degrees
            let angle = atan2(zDiff, shoulderWidth) * 180.0 / .pi
            return angle
        } else {
            // In 2D mode, we can't measure true twist
            return 0.0
        }
    }

    private func distance3D(_ p1: SIMD3<Float>, _ p2: SIMD3<Float>) -> Float {
        return simd_distance(p1, p2)
    }
}
