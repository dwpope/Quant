import XCTest
import simd
@testable import PostureLogic

final class PoseDepthFusionTests: XCTestCase {

    // MARK: - Helpers

    private func makeKeypoint(_ joint: Joint, x: CGFloat, y: CGFloat, confidence: Float = 0.9) -> Keypoint {
        Keypoint(joint: joint, position: CGPoint(x: x, y: y), confidence: confidence)
    }

    private func makePose(keypoints: [Keypoint], timestamp: TimeInterval = 1.0, confidence: Float = 0.9) -> PoseObservation {
        PoseObservation(timestamp: timestamp, keypoints: keypoints, confidence: confidence)
    }

    /// Standard upright pose: shoulders at y=0.5, nose above at y=0.7
    private func uprightPose(shoulderY: CGFloat = 0.5, noseY: CGFloat = 0.7) -> PoseObservation {
        makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: shoulderY),
            makeKeypoint(.rightShoulder, x: 0.6, y: shoulderY),
            makeKeypoint(.nose, x: 0.5, y: noseY),
        ])
    }

    private func fuse(_ pose: PoseObservation, fusion: inout PoseDepthFusion) -> PoseSample? {
        fusion.fuse(pose: pose, depthSamples: nil, confidence: .unavailable, intrinsics: nil, trackingQuality: .good)
    }

    // MARK: - Basic Functionality: nil when critical keypoints missing

    func test_nilWhenBothShouldersMissing() {
        var fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ])
        XCTAssertNil(fuse(pose, fusion: &fusion))
    }

    func test_nilWhenLeftShoulderMissing() {
        var fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ])
        XCTAssertNil(fuse(pose, fusion: &fusion))
    }

    func test_nilWhenRightShoulderMissing() {
        var fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5),
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ])
        XCTAssertNil(fuse(pose, fusion: &fusion))
    }

    func test_nilWhenHeadMissing() {
        var fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
        ])
        XCTAssertNil(fuse(pose, fusion: &fusion))
    }

    func test_nonNilWithMinimalKeypoints() {
        var fusion = PoseDepthFusion()
        let sample = fuse(uprightPose(), fusion: &fusion)
        XCTAssertNotNil(sample)
    }

    // MARK: - Normalization

    func test_shoulderMidpointIsRawImageCoords() {
        var fusion = PoseDepthFusion()
        // uprightPose: shoulders at x=0.4,0.6 y=0.5 → midpoint (0.5, 0.5)
        let sample = fuse(uprightPose(), fusion: &fusion)!
        XCTAssertEqual(sample.shoulderMidpoint.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(sample.shoulderMidpoint.y, 0.5, accuracy: 0.001)
        XCTAssertEqual(sample.shoulderMidpoint.z, 0, accuracy: 0.001)
    }

    func test_shouldersSymmetric() {
        var fusion = PoseDepthFusion()
        let sample = fuse(uprightPose(), fusion: &fusion)!
        // When shoulders level, left ≈ (-0.5, 0, 0), right ≈ (0.5, 0, 0)
        XCTAssertEqual(sample.leftShoulder.x, -0.5, accuracy: 0.001)
        XCTAssertEqual(sample.rightShoulder.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(sample.leftShoulder.y, 0, accuracy: 0.001)
        XCTAssertEqual(sample.rightShoulder.y, 0, accuracy: 0.001)
    }

    func test_headAboveShoulders() {
        var fusion = PoseDepthFusion()
        let sample = fuse(uprightPose(), fusion: &fusion)!
        // Head y should be positive (above shoulder midpoint in normalized coords)
        XCTAssertGreaterThan(sample.headPosition.y, 0)
    }

    func test_allZValuesZeroIn2DMode() {
        var fusion = PoseDepthFusion()
        let sample = fuse(uprightPose(), fusion: &fusion)!
        XCTAssertEqual(sample.headPosition.z, 0)
        XCTAssertEqual(sample.shoulderMidpoint.z, 0)
        XCTAssertEqual(sample.leftShoulder.z, 0)
        XCTAssertEqual(sample.rightShoulder.z, 0)
    }

    func test_depthModeIsTwoDOnly() {
        var fusion = PoseDepthFusion()
        let sample = fuse(uprightPose(), fusion: &fusion)!
        XCTAssertEqual(sample.depthMode, .twoDOnly)
    }

    func test_headForwardOffsetIsZeroIn2D() {
        var fusion = PoseDepthFusion()
        let sample = fuse(uprightPose(), fusion: &fusion)!
        XCTAssertEqual(sample.headForwardOffset, 0)
    }

    func test_shoulderWidthRawPreserved() {
        var fusion = PoseDepthFusion()
        // Shoulders at x=0.4 and x=0.6, same y → width = 0.2
        let sample = fuse(uprightPose(), fusion: &fusion)!
        XCTAssertEqual(sample.shoulderWidthRaw, 0.2, accuracy: 0.001)
    }

    func test_timestampPreserved() {
        var fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ], timestamp: 42.0)
        let sample = fuse(pose, fusion: &fusion)!
        XCTAssertEqual(sample.timestamp, 42.0)
    }

    // MARK: - Directional Correctness: Torso Angle

    func test_torsoAngleIncreasesWithForwardLean() {
        var fusion = PoseDepthFusion()
        // Upright: head well above shoulders
        let upright = fuse(uprightPose(noseY: 0.8), fusion: &fusion)!

        // Leaned: head barely above shoulders (closer to shoulder level = more lean)
        let leaned = fuse(uprightPose(noseY: 0.52), fusion: &fusion)!

        XCTAssertGreaterThan(leaned.torsoAngle, upright.torsoAngle)
    }

    func test_torsoAngleWithHips() {
        var fusion = PoseDepthFusion()
        // With hips visible, torsoAngle uses hip→shoulder vector
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
            makeKeypoint(.nose, x: 0.5, y: 0.7),
            makeKeypoint(.leftHip, x: 0.42, y: 0.3),
            makeKeypoint(.rightHip, x: 0.58, y: 0.3),
        ])
        let sample = fuse(pose, fusion: &fusion)!
        // Upright with hips directly below → small angle
        XCTAssertLessThan(sample.torsoAngle, 20)
    }

    // MARK: - Directional Correctness: Shoulder Twist

    func test_shoulderTwistZeroWhenLevel() {
        var fusion = PoseDepthFusion()
        let sample = fuse(uprightPose(), fusion: &fusion)!
        XCTAssertEqual(sample.shoulderTwist, 0, accuracy: 0.1)
    }

    func test_shoulderTwistPositiveWhenLeftHigher() {
        var fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.55),   // higher
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.45),   // lower
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ])
        let sample = fuse(pose, fusion: &fusion)!
        XCTAssertGreaterThan(sample.shoulderTwist, 0)
    }

    func test_shoulderTwistNegativeWhenRightHigher() {
        var fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.45),   // lower
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.55),   // higher
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ])
        let sample = fuse(pose, fusion: &fusion)!
        XCTAssertLessThan(sample.shoulderTwist, 0)
    }

    // MARK: - Head Fallback Chain

    func test_headFallback_nose() {
        var fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ])
        XCTAssertNotNil(fuse(pose, fusion: &fusion))
    }

    func test_headFallback_eyeMidpoint() {
        var fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
            makeKeypoint(.leftEye, x: 0.48, y: 0.7),
            makeKeypoint(.rightEye, x: 0.52, y: 0.7),
        ])
        let sample = fuse(pose, fusion: &fusion)!
        // Eye midpoint should resolve to head position above shoulders
        XCTAssertGreaterThan(sample.headPosition.y, 0)
    }

    func test_headFallback_singleEye() {
        var fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
            makeKeypoint(.leftEye, x: 0.48, y: 0.7),
        ])
        XCTAssertNotNil(fuse(pose, fusion: &fusion))
    }

    func test_headFallback_earMidpoint() {
        var fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
            makeKeypoint(.leftEar, x: 0.45, y: 0.7),
            makeKeypoint(.rightEar, x: 0.55, y: 0.7),
        ])
        XCTAssertNotNil(fuse(pose, fusion: &fusion))
    }

    func test_headFallback_nilWhenNoHeadKeypoints() {
        var fusion = PoseDepthFusion()
        // Only shoulders, no head-region keypoints at all
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
            makeKeypoint(.leftHip, x: 0.42, y: 0.3),
        ])
        XCTAssertNil(fuse(pose, fusion: &fusion))
    }

    // MARK: - Confidence Filtering

    func test_rejectsLowConfidenceShoulder() {
        var fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5, confidence: 0.2),  // below 0.3
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ])
        XCTAssertNil(fuse(pose, fusion: &fusion))
    }

    func test_rejectsLowConfidenceHead() {
        var fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
            makeKeypoint(.nose, x: 0.5, y: 0.7, confidence: 0.1),
        ])
        XCTAssertNil(fuse(pose, fusion: &fusion))
    }

    func test_acceptsKeypointAtExactlyThreshold() {
        var fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5, confidence: 0.3),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5, confidence: 0.3),
            makeKeypoint(.nose, x: 0.5, y: 0.7, confidence: 0.3),
        ])
        XCTAssertNotNil(fuse(pose, fusion: &fusion))
    }

    // MARK: - Degenerate Poses

    func test_rejectsDegenerateShoulderWidth() {
        var fusion = PoseDepthFusion()
        // Shoulders nearly on top of each other
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.5, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.5005, y: 0.5),
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ])
        XCTAssertNil(fuse(pose, fusion: &fusion))
    }

    // MARK: - Debug State

    func test_fusionCountIncrementsOnSuccess() {
        var fusion = PoseDepthFusion()
        XCTAssertEqual(fusion.fusionCount, 0)
        _ = fuse(uprightPose(), fusion: &fusion)
        XCTAssertEqual(fusion.fusionCount, 1)
        _ = fuse(uprightPose(), fusion: &fusion)
        XCTAssertEqual(fusion.fusionCount, 2)
    }

    func test_missingKeypointCountIncrementsOnFailure() {
        var fusion = PoseDepthFusion()
        XCTAssertEqual(fusion.missingKeypointCount, 0)
        let pose = makePose(keypoints: [])
        _ = fuse(pose, fusion: &fusion)
        XCTAssertEqual(fusion.missingKeypointCount, 1)
    }

    func test_debugStateContainsExpectedKeys() {
        var fusion = PoseDepthFusion()
        _ = fuse(uprightPose(), fusion: &fusion)
        let state = fusion.debugState
        XCTAssertNotNil(state["lastShoulderWidth"])
        XCTAssertNotNil(state["lastHeadPosition"])
        XCTAssertNotNil(state["fusionCount"])
        XCTAssertNotNil(state["missingKeypointCount"])
    }

    func test_lastShoulderWidthUpdatedAfterFusion() {
        var fusion = PoseDepthFusion()
        XCTAssertEqual(fusion.lastShoulderWidth, 0)
        _ = fuse(uprightPose(), fusion: &fusion)
        XCTAssertEqual(fusion.lastShoulderWidth, 0.2, accuracy: 0.001)
    }

    func test_trackingQualityPassedThrough() {
        var fusion = PoseDepthFusion()
        let sample = fusion.fuse(
            pose: uprightPose(),
            depthSamples: nil,
            confidence: .unavailable,
            intrinsics: nil,
            trackingQuality: .degraded
        )
        XCTAssertEqual(sample?.trackingQuality, .degraded)
    }

    // MARK: - 3D Depth Fusion

    /// Creates intrinsics in normalized coordinate space (matching 0-1 keypoint coords).
    /// Default: unit focal length, principal point at center.
    private func makeIntrinsics(fx: Float = 1.0, fy: Float = 1.0, cx: Float = 0.5, cy: Float = 0.5) -> simd_float3x3 {
        // Column-major: columns.0 = (fx, 0, 0), columns.1 = (0, fy, 0), columns.2 = (cx, cy, 1)
        simd_float3x3(columns: (
            SIMD3<Float>(fx, 0, 0),
            SIMD3<Float>(0, fy, 0),
            SIMD3<Float>(cx, cy, 1)
        ))
    }

    private func makeDepthSamples(for keypoints: [Keypoint], depth: Float = 0.6, confidence: Float = 1.0) -> [DepthAtPoint] {
        keypoints.map { kp in
            DepthAtPoint(point: kp.position, depth: depth, confidence: confidence)
        }
    }

    func test_depthFusion_producesDepthFusionMode() {
        var fusion = PoseDepthFusion()
        let pose = uprightPose()
        let samples = makeDepthSamples(for: pose.keypoints, depth: 0.6)
        let result = fusion.fuse(
            pose: pose,
            depthSamples: samples,
            confidence: .medium,
            intrinsics: makeIntrinsics(),
            trackingQuality: .good
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.depthMode, .depthFusion)
    }

    func test_depthFusion_hasNonZeroZValues() {
        var fusion = PoseDepthFusion()
        let keypoints = [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ]
        let pose = makePose(keypoints: keypoints)
        // Use different depths so 3D positions have z variance
        let samples = [
            DepthAtPoint(point: keypoints[0].position, depth: 0.6, confidence: 1.0),
            DepthAtPoint(point: keypoints[1].position, depth: 0.6, confidence: 1.0),
            DepthAtPoint(point: keypoints[2].position, depth: 0.5, confidence: 1.0),
        ]
        let result = fusion.fuse(
            pose: pose,
            depthSamples: samples,
            confidence: .high,
            intrinsics: makeIntrinsics(),
            trackingQuality: .good
        )!
        // Shoulder midpoint z should be the average shoulder depth (0.6)
        XCTAssertNotEqual(result.shoulderMidpoint.z, 0)
    }

    func test_depthFusion_headForwardOffset_nonZeroWhenDifferentDepths() {
        var fusion = PoseDepthFusion()
        let keypoints = [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ]
        let pose = makePose(keypoints: keypoints)
        // Head closer to camera (smaller depth) than shoulders
        let samples = [
            DepthAtPoint(point: keypoints[0].position, depth: 0.7, confidence: 1.0),
            DepthAtPoint(point: keypoints[1].position, depth: 0.7, confidence: 1.0),
            DepthAtPoint(point: keypoints[2].position, depth: 0.5, confidence: 1.0),
        ]
        let result = fusion.fuse(
            pose: pose,
            depthSamples: samples,
            confidence: .high,
            intrinsics: makeIntrinsics(),
            trackingQuality: .good
        )!
        // Head is closer (depth 0.5) vs shoulders (depth 0.7)
        // headForwardOffset = head.z - mid.z = 0.5 - 0.7 = negative (forward lean)
        XCTAssertLessThan(result.headForwardOffset, 0)
    }

    func test_depthFusion_fallsBackTo2DWhenConfidenceLow() {
        var fusion = PoseDepthFusion()
        let pose = uprightPose()
        let samples = makeDepthSamples(for: pose.keypoints, depth: 0.6)
        let result = fusion.fuse(
            pose: pose,
            depthSamples: samples,
            confidence: .low,
            intrinsics: makeIntrinsics(),
            trackingQuality: .good
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.depthMode, .twoDOnly)
    }

    func test_depthFusion_fallsBackTo2DWhenNoIntrinsics() {
        var fusion = PoseDepthFusion()
        let pose = uprightPose()
        let samples = makeDepthSamples(for: pose.keypoints, depth: 0.6)
        let result = fusion.fuse(
            pose: pose,
            depthSamples: samples,
            confidence: .high,
            intrinsics: nil,
            trackingQuality: .good
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.depthMode, .twoDOnly)
    }

    func test_depthFusion_fallsBackTo2DWhenNoDepthSamples() {
        var fusion = PoseDepthFusion()
        let result = fusion.fuse(
            pose: uprightPose(),
            depthSamples: nil,
            confidence: .high,
            intrinsics: makeIntrinsics(),
            trackingQuality: .good
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.depthMode, .twoDOnly)
    }

    func test_depthFusion_fallsBackTo2DWhenDepthSamplesLowConfidence() {
        var fusion = PoseDepthFusion()
        let pose = uprightPose()
        let samples = makeDepthSamples(for: pose.keypoints, depth: 0.6, confidence: 0.1)
        let result = fusion.fuse(
            pose: pose,
            depthSamples: samples,
            confidence: .high,
            intrinsics: makeIntrinsics(),
            trackingQuality: .good
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.depthMode, .twoDOnly)
    }

    func test_depthFusion_ignoresEdgePoints() {
        var fusion = PoseDepthFusion()
        // Place shoulders near edges (within 5% of frame boundary)
        let keypoints = [
            makeKeypoint(.leftShoulder, x: 0.02, y: 0.5),  // Near left edge
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ]
        let pose = makePose(keypoints: keypoints)
        let samples = makeDepthSamples(for: keypoints, depth: 0.6)
        let result = fusion.fuse(
            pose: pose,
            depthSamples: samples,
            confidence: .high,
            intrinsics: makeIntrinsics(),
            trackingQuality: .good
        )
        // Should fall back to 2D because left shoulder is near edge
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.depthMode, .twoDOnly)
    }

    func test_depthFusion_preservesTimestamp() {
        var fusion = PoseDepthFusion()
        let keypoints = [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ]
        let pose = makePose(keypoints: keypoints, timestamp: 99.0)
        let samples = makeDepthSamples(for: keypoints, depth: 0.6)
        let result = fusion.fuse(
            pose: pose,
            depthSamples: samples,
            confidence: .high,
            intrinsics: makeIntrinsics(),
            trackingQuality: .good
        )!
        XCTAssertEqual(result.timestamp, 99.0)
    }

    func test_depthFusion_shoulderWidthRawPreserved() {
        var fusion = PoseDepthFusion()
        let pose = uprightPose()
        let samples = makeDepthSamples(for: pose.keypoints, depth: 0.6)
        let result = fusion.fuse(
            pose: pose,
            depthSamples: samples,
            confidence: .high,
            intrinsics: makeIntrinsics(),
            trackingQuality: .good
        )!
        // shoulderWidthRaw should still be the 2D image-space width (0.2)
        XCTAssertEqual(result.shoulderWidthRaw, 0.2, accuracy: 0.001)
    }
}
