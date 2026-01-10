import XCTest
import simd
@testable import PostureLogic

final class PoseDepthFusionTests: XCTestCase {

    // MARK: - Mode Selection Tests

    func test_usesDepthFusionMode_whenConfidenceIsHighAndDepthAvailable() {
        var fusion = PoseDepthFusion()

        let pose = createMockPose()
        let depthSamples = createMockDepthSamples()
        let intrinsics = createMockIntrinsics()

        let sample = fusion.fuse(
            pose: pose,
            depthSamples: depthSamples,
            confidence: .high,
            cameraIntrinsics: intrinsics
        )

        XCTAssertEqual(sample.depthMode, .depthFusion)
    }

    func test_usesTwoDOnlyMode_whenConfidenceIsLow() {
        var fusion = PoseDepthFusion()

        let pose = createMockPose()
        let depthSamples = createMockDepthSamples()
        let intrinsics = createMockIntrinsics()

        let sample = fusion.fuse(
            pose: pose,
            depthSamples: depthSamples,
            confidence: .low,
            cameraIntrinsics: intrinsics
        )

        XCTAssertEqual(sample.depthMode, .twoDOnly)
    }

    func test_usesTwoDOnlyMode_whenDepthSamplesNil() {
        var fusion = PoseDepthFusion()

        let pose = createMockPose()

        let sample = fusion.fuse(
            pose: pose,
            depthSamples: nil,
            confidence: .high,
            cameraIntrinsics: createMockIntrinsics()
        )

        XCTAssertEqual(sample.depthMode, .twoDOnly)
    }

    func test_usesTwoDOnlyMode_whenIntrinsicsNil() {
        var fusion = PoseDepthFusion()

        let pose = createMockPose()
        let depthSamples = createMockDepthSamples()

        let sample = fusion.fuse(
            pose: pose,
            depthSamples: depthSamples,
            confidence: .high,
            cameraIntrinsics: nil
        )

        XCTAssertEqual(sample.depthMode, .twoDOnly)
    }

    // MARK: - Tracking Quality Tests

    func test_trackingQualityGood_whenAllKeypointsPresent() {
        var fusion = PoseDepthFusion()

        let pose = createMockPose(confidence: 0.9)

        let sample = fusion.fuse(
            pose: pose,
            depthSamples: nil,
            confidence: .unavailable,
            cameraIntrinsics: nil
        )

        XCTAssertEqual(sample.trackingQuality, .good)
    }

    func test_trackingQualityDegraded_whenConfidenceLow() {
        var fusion = PoseDepthFusion()

        let pose = createMockPose(confidence: 0.5, keypointConfidence: 0.5)

        let sample = fusion.fuse(
            pose: pose,
            depthSamples: nil,
            confidence: .unavailable,
            cameraIntrinsics: nil
        )

        XCTAssertEqual(sample.trackingQuality, .degraded)
    }

    func test_trackingQualityLost_whenMissingKeypoints() {
        var fusion = PoseDepthFusion()

        // Create pose with only one shoulder (missing critical keypoints)
        let keypoints = [
            Keypoint(joint: .leftShoulder, position: CGPoint(x: 0.3, y: 0.4), confidence: 0.8)
        ]
        let pose = PoseObservation(timestamp: 1.0, keypoints: keypoints, confidence: 0.8)

        let sample = fusion.fuse(
            pose: pose,
            depthSamples: nil,
            confidence: .unavailable,
            cameraIntrinsics: nil
        )

        XCTAssertEqual(sample.trackingQuality, .lost)
    }

    // MARK: - 2D Mode Position Tests

    func test_twoDMode_producesValidPositions() {
        var fusion = PoseDepthFusion()

        let pose = createMockPose()

        let sample = fusion.fuse(
            pose: pose,
            depthSamples: nil,
            confidence: .unavailable,
            cameraIntrinsics: nil
        )

        // Verify positions are set (not zero)
        XCTAssertNotEqual(sample.headPosition, .zero)
        XCTAssertNotEqual(sample.shoulderMidpoint, .zero)
        XCTAssertNotEqual(sample.leftShoulder, .zero)
        XCTAssertNotEqual(sample.rightShoulder, .zero)

        // Verify shoulder midpoint is between shoulders
        let expectedMid = (sample.leftShoulder + sample.rightShoulder) / 2.0
        XCTAssertEqual(sample.shoulderMidpoint.x, expectedMid.x, accuracy: 0.001)
        XCTAssertEqual(sample.shoulderMidpoint.y, expectedMid.y, accuracy: 0.001)
    }

    // MARK: - 3D Mode Position Tests

    func test_depthFusionMode_uses3DPositions() {
        var fusion = PoseDepthFusion()

        let pose = createMockPose()
        let depthSamples = createMockDepthSamples()
        let intrinsics = createMockIntrinsics()

        let sample = fusion.fuse(
            pose: pose,
            depthSamples: depthSamples,
            confidence: .high,
            cameraIntrinsics: intrinsics
        )

        XCTAssertEqual(sample.depthMode, .depthFusion)

        // In 3D mode, Z components should be non-zero (representing depth)
        // At least one position should have depth
        let hasDepth = sample.headPosition.z != 0 ||
                      sample.shoulderMidpoint.z != 0 ||
                      sample.leftShoulder.z != 0 ||
                      sample.rightShoulder.z != 0

        XCTAssertTrue(hasDepth, "3D mode should produce positions with depth (non-zero Z)")
    }

    /// Ticket 3.1 Acceptance Test: Verify unprojection with known values produces correct 3D position
    /// This test validates the mathematical correctness of the pinhole camera model implementation
    func test_unprojection_withKnownValues_producesCorrect3DPosition() {
        var fusion = PoseDepthFusion()

        // Setup known camera intrinsics
        // fx = 1000, fy = 1000, cx = 960, cy = 540 (center of 1920x1080 image)
        let intrinsics = simd_float3x3(
            SIMD3<Float>(1000, 0, 0),      // Column 0: fx, 0, 0
            SIMD3<Float>(0, 1000, 0),      // Column 1: 0, fy, 0
            SIMD3<Float>(960, 540, 1)      // Column 2: cx, cy, 1
        )

        // Test Case 1: Point at image center should unproject to (0, 0, depth)
        // Point: (960, 540) - exactly at principal point
        // Depth: 1.5 meters
        // Expected 3D: x = (960-960)*1.5/1000 = 0
        //             y = (540-540)*1.5/1000 = 0
        //             z = 1.5
        let centerPose = PoseObservation(
            timestamp: 1.0,
            keypoints: [
                Keypoint(joint: .nose, position: CGPoint(x: 960, y: 540), confidence: 0.9),
                Keypoint(joint: .leftShoulder, position: CGPoint(x: 860, y: 640), confidence: 0.9),
                Keypoint(joint: .rightShoulder, position: CGPoint(x: 1060, y: 640), confidence: 0.9)
            ],
            confidence: 0.9
        )

        let centerDepthSamples = [
            DepthAtPoint(point: CGPoint(x: 960, y: 540), depth: 1.5, confidence: 1.0),
            DepthAtPoint(point: CGPoint(x: 860, y: 640), depth: 1.6, confidence: 1.0),
            DepthAtPoint(point: CGPoint(x: 1060, y: 640), depth: 1.6, confidence: 1.0)
        ]

        let centerSample = fusion.fuse(
            pose: centerPose,
            depthSamples: centerDepthSamples,
            confidence: .high,
            cameraIntrinsics: intrinsics
        )

        // Verify head position (nose at center)
        XCTAssertEqual(centerSample.headPosition.x, 0.0, accuracy: 0.001,
                      "Head X should be 0 when at principal point")
        XCTAssertEqual(centerSample.headPosition.y, 0.0, accuracy: 0.001,
                      "Head Y should be 0 when at principal point")
        XCTAssertEqual(centerSample.headPosition.z, 1.5, accuracy: 0.001,
                      "Head Z should equal depth value")

        // Test Case 2: Point offset from center
        // Point: (1160, 640) - 200px right, 100px down from center
        // Depth: 2.0 meters
        // Expected 3D: x = (1160-960)*2.0/1000 = 200*2.0/1000 = 0.4
        //             y = (640-540)*2.0/1000 = 100*2.0/1000 = 0.2
        //             z = 2.0
        let offsetPose = PoseObservation(
            timestamp: 2.0,
            keypoints: [
                Keypoint(joint: .nose, position: CGPoint(x: 1160, y: 640), confidence: 0.9),
                Keypoint(joint: .leftShoulder, position: CGPoint(x: 1060, y: 740), confidence: 0.9),
                Keypoint(joint: .rightShoulder, position: CGPoint(x: 1260, y: 740), confidence: 0.9)
            ],
            confidence: 0.9
        )

        let offsetDepthSamples = [
            DepthAtPoint(point: CGPoint(x: 1160, y: 640), depth: 2.0, confidence: 1.0),
            DepthAtPoint(point: CGPoint(x: 1060, y: 740), depth: 2.1, confidence: 1.0),
            DepthAtPoint(point: CGPoint(x: 1260, y: 740), depth: 2.1, confidence: 1.0)
        ]

        let offsetSample = fusion.fuse(
            pose: offsetPose,
            depthSamples: offsetDepthSamples,
            confidence: .high,
            cameraIntrinsics: intrinsics
        )

        // Verify offset position calculations
        XCTAssertEqual(offsetSample.headPosition.x, 0.4, accuracy: 0.001,
                      "Head X should be 0.4m (200px offset * 2.0m depth / 1000 focal length)")
        XCTAssertEqual(offsetSample.headPosition.y, 0.2, accuracy: 0.001,
                      "Head Y should be 0.2m (100px offset * 2.0m depth / 1000 focal length)")
        XCTAssertEqual(offsetSample.headPosition.z, 2.0, accuracy: 0.001,
                      "Head Z should equal depth value")
    }

    // MARK: - Timestamp Tests

    func test_preservesTimestamp() {
        var fusion = PoseDepthFusion()

        let timestamp: TimeInterval = 123.456
        let pose = createMockPose(timestamp: timestamp)

        let sample = fusion.fuse(
            pose: pose,
            depthSamples: nil,
            confidence: .unavailable,
            cameraIntrinsics: nil
        )

        XCTAssertEqual(sample.timestamp, timestamp)
    }

    // MARK: - Debug State Tests

    func test_debugState_tracksMode() {
        var fusion = PoseDepthFusion()

        let pose = createMockPose()

        _ = fusion.fuse(
            pose: pose,
            depthSamples: nil,
            confidence: .unavailable,
            cameraIntrinsics: nil
        )

        let debugState = fusion.debugState
        XCTAssertEqual(debugState["lastMode"] as? String, "twoDOnly")
    }

    func test_debugState_tracksKeypointCount() {
        var fusion = PoseDepthFusion()

        let pose = createMockPose()

        _ = fusion.fuse(
            pose: pose,
            depthSamples: nil,
            confidence: .unavailable,
            cameraIntrinsics: nil
        )

        let debugState = fusion.debugState
        let count = debugState["lastKeypointCount"] as? Int
        XCTAssertNotNil(count)
        XCTAssertGreaterThan(count!, 0)
    }

    // MARK: - Helper Functions

    private func createMockPose(
        timestamp: TimeInterval = 1.0,
        confidence: Float = 0.9,
        keypointConfidence: Float = 0.8
    ) -> PoseObservation {
        let keypoints = [
            Keypoint(joint: .nose, position: CGPoint(x: 0.5, y: 0.3), confidence: keypointConfidence),
            Keypoint(joint: .leftShoulder, position: CGPoint(x: 0.3, y: 0.4), confidence: keypointConfidence),
            Keypoint(joint: .rightShoulder, position: CGPoint(x: 0.7, y: 0.4), confidence: keypointConfidence),
            Keypoint(joint: .leftHip, position: CGPoint(x: 0.35, y: 0.6), confidence: keypointConfidence),
            Keypoint(joint: .rightHip, position: CGPoint(x: 0.65, y: 0.6), confidence: keypointConfidence)
        ]

        return PoseObservation(timestamp: timestamp, keypoints: keypoints, confidence: confidence)
    }

    private func createMockDepthSamples() -> [DepthAtPoint] {
        // Create depth samples at the same positions as keypoints
        return [
            DepthAtPoint(point: CGPoint(x: 0.5, y: 0.3), depth: 0.9, confidence: 1.0),   // nose
            DepthAtPoint(point: CGPoint(x: 0.3, y: 0.4), depth: 1.0, confidence: 1.0),  // left shoulder
            DepthAtPoint(point: CGPoint(x: 0.7, y: 0.4), depth: 1.0, confidence: 1.0),  // right shoulder
            DepthAtPoint(point: CGPoint(x: 0.35, y: 0.6), depth: 1.05, confidence: 1.0), // left hip
            DepthAtPoint(point: CGPoint(x: 0.65, y: 0.6), depth: 1.05, confidence: 1.0)  // right hip
        ]
    }

    private func createMockIntrinsics() -> simd_float3x3 {
        // Create typical camera intrinsics matrix
        // Note: Column-major ordering per Known Gotchas
        return simd_float3x3(
            SIMD3<Float>(1000, 0, 0),      // fx, 0, 0
            SIMD3<Float>(0, 1000, 0),      // 0, fy, 0
            SIMD3<Float>(960, 540, 1)      // cx, cy, 1 (1920x1080 center)
        )
    }
}
