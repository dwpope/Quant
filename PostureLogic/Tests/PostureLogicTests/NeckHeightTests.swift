import XCTest
import simd
@testable import PostureLogic

/// Geometry tests for the ear-based head-carriage height (`PoseSample.neckHeight`),
/// the refined source of `RawMetrics.headDrop`. Exercises `PoseDepthFusion` end to
/// end (via `fuse`) since `computeNeckHeight` is private; `neckHeight` on the
/// produced `PoseSample` is the observable.
///
/// `neckHeight = (earMidY − shoulderMidY) / shoulderWidth` in Vision y-up image
/// coordinates: ears above shoulders ⇒ positive; sinking the head toward the
/// shoulders ⇒ decreasing; scale-invariant under a uniform zoom about any center.
final class NeckHeightTests: XCTestCase {

    // MARK: - Helpers

    private func makeKeypoint(_ joint: Joint, x: CGFloat, y: CGFloat, confidence: Float = 0.9) -> Keypoint {
        Keypoint(joint: joint, position: CGPoint(x: x, y: y), confidence: confidence)
    }

    private func makePose(keypoints: [Keypoint], timestamp: TimeInterval = 1.0, confidence: Float = 0.9) -> PoseObservation {
        PoseObservation(timestamp: timestamp, keypoints: keypoints, confidence: confidence)
    }

    private func fuse(_ pose: PoseObservation, fusion: inout PoseDepthFusion) -> PoseSample? {
        fusion.fuse(pose: pose, depthSamples: nil, confidence: .unavailable, intrinsics: nil, trackingQuality: .good)
    }

    /// Upright pose with a full ear pair. Shoulders at `shoulderY`, ears level at
    /// `earY` (default above the shoulders), nose present as the resolved head.
    private func earPose(
        shoulderY: CGFloat = 0.4,
        earY: CGFloat = 0.6,
        noseY: CGFloat = 0.62,
        leftShoulderX: CGFloat = 0.4,
        rightShoulderX: CGFloat = 0.6,
        leftEarX: CGFloat = 0.45,
        rightEarX: CGFloat = 0.55
    ) -> PoseObservation {
        makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: leftShoulderX, y: shoulderY),
            makeKeypoint(.rightShoulder, x: rightShoulderX, y: shoulderY),
            makeKeypoint(.leftEar, x: leftEarX, y: earY),
            makeKeypoint(.rightEar, x: rightEarX, y: earY),
            makeKeypoint(.nose, x: 0.5, y: noseY),
        ])
    }

    /// Scales every keypoint about `center` by `factor` (a uniform zoom), preserving
    /// joints/confidence.
    private func scaled(_ pose: PoseObservation, by factor: CGFloat, about center: CGPoint) -> PoseObservation {
        let scaledKeypoints = pose.keypoints.map { kp -> Keypoint in
            let nx = center.x + (kp.position.x - center.x) * factor
            let ny = center.y + (kp.position.y - center.y) * factor
            return Keypoint(joint: kp.joint, position: CGPoint(x: nx, y: ny), confidence: kp.confidence)
        }
        return makePose(keypoints: scaledKeypoints, timestamp: pose.timestamp, confidence: pose.confidence)
    }

    // MARK: - Sign / Magnitude

    func test_earsAboveShoulders_neckHeightPositive() {
        var fusion = PoseDepthFusion()
        let sample = fuse(earPose(shoulderY: 0.4, earY: 0.6), fusion: &fusion)!
        XCTAssertGreaterThan(sample.neckHeight, 0, "Ears above shoulders should give positive neckHeight")
    }

    func test_knownGeometry_matchesFormula() {
        var fusion = PoseDepthFusion()
        // Shoulders x∈{0.4,0.6} y=0.4 ⇒ shoulderMidY=0.4, shoulderWidth=0.2.
        // Ears level at y=0.6 ⇒ earMidY=0.6. neckHeight = (0.6-0.4)/0.2 = 1.0.
        let sample = fuse(earPose(shoulderY: 0.4, earY: 0.6), fusion: &fusion)!
        XCTAssertEqual(sample.neckHeight, 1.0, accuracy: 0.001)
    }

    func test_loweringEars_decreasesNeckHeight() {
        var fusion = PoseDepthFusion()
        let high = fuse(earPose(shoulderY: 0.4, earY: 0.62), fusion: &fusion)!
        let low = fuse(earPose(shoulderY: 0.4, earY: 0.50), fusion: &fusion)!
        XCTAssertLessThan(low.neckHeight, high.neckHeight,
                          "Lowering the ears (head sinking toward shoulders) should decrease neckHeight")
    }

    func test_earsBelowShoulders_neckHeightNegative() {
        var fusion = PoseDepthFusion()
        // Extreme slump: ears drop below the shoulder line ⇒ negative carriage.
        let sample = fuse(earPose(shoulderY: 0.5, earY: 0.42, noseY: 0.44), fusion: &fusion)!
        XCTAssertLessThan(sample.neckHeight, 0, "Ears below shoulders should give negative neckHeight")
    }

    // MARK: - Scale Invariance

    func test_uniformZoom_neckHeightInvariant() {
        var fusion = PoseDepthFusion()
        let base = earPose(shoulderY: 0.4, earY: 0.6)
        let baseSample = fuse(base, fusion: &fusion)!

        // Zoom in 1.5x about the frame center — camera-distance change; carriage ratio
        // is scale-invariant so neckHeight must be unchanged.
        let zoomed = scaled(base, by: 1.5, about: CGPoint(x: 0.5, y: 0.5))
        let zoomedSample = fuse(zoomed, fusion: &fusion)!

        XCTAssertEqual(zoomedSample.neckHeight, baseSample.neckHeight, accuracy: 0.001,
                       "neckHeight must be invariant under a uniform zoom (scale-invariant like torsoAngle)")
    }

    func test_uniformZoom_aboutOffCenter_neckHeightInvariant() {
        var fusion = PoseDepthFusion()
        let base = earPose(shoulderY: 0.4, earY: 0.6)
        let baseSample = fuse(base, fusion: &fusion)!

        // Zoom about an off-center point (subject not centered in frame).
        let zoomed = scaled(base, by: 0.7, about: CGPoint(x: 0.2, y: 0.9))
        let zoomedSample = fuse(zoomed, fusion: &fusion)!

        XCTAssertEqual(zoomedSample.neckHeight, baseSample.neckHeight, accuracy: 0.001,
                       "neckHeight must be invariant under a uniform zoom about any center")
    }

    // MARK: - Ear Fallback (nose-first head Y)

    func test_missingEars_fallsBackToNose_noCrash() {
        var fusion = PoseDepthFusion()
        // No ears at all — head resolves nose-first; neckHeight uses that fallback Y.
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.4),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.4),
            makeKeypoint(.nose, x: 0.5, y: 0.6),
        ])
        let sample = fuse(pose, fusion: &fusion)
        XCTAssertNotNil(sample, "Missing ears must not prevent a sample (nose fallback)")
        // Fallback formula: (noseY 0.6 − shoulderMidY 0.4) / width 0.2 = 1.0.
        XCTAssertEqual(sample!.neckHeight, 1.0, accuracy: 0.001,
                       "With ears absent, neckHeight falls back to the resolved nose-first head Y")
        XCTAssertTrue(sample!.neckHeight.isFinite)
    }

    func test_oneEarMissing_fallsBackToNose() {
        var fusion = PoseDepthFusion()
        // Only one ear passes the gate ⇒ ear-pair branch fails ⇒ nose fallback.
        // Nose sits lower than the (ignored) ear so the fallback value is distinct.
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.4),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.4),
            makeKeypoint(.leftEar, x: 0.45, y: 0.7),   // present
            // rightEar omitted
            makeKeypoint(.nose, x: 0.5, y: 0.6),
        ])
        let sample = fuse(pose, fusion: &fusion)!
        // Uses nose (0.6), not the lone ear (0.7): (0.6 − 0.4)/0.2 = 1.0.
        XCTAssertEqual(sample.neckHeight, 1.0, accuracy: 0.001,
                       "A single confident ear should not be used; falls back to nose")
    }

    func test_lowConfidenceEars_fallBackToNose() {
        var fusion = PoseDepthFusion()
        // Ears present but below the confidence gate (0.3) ⇒ nose fallback.
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.4),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.4),
            makeKeypoint(.leftEar, x: 0.45, y: 0.7, confidence: 0.1),
            makeKeypoint(.rightEar, x: 0.55, y: 0.7, confidence: 0.1),
            makeKeypoint(.nose, x: 0.5, y: 0.6),
        ])
        let sample = fuse(pose, fusion: &fusion)!
        XCTAssertEqual(sample.neckHeight, 1.0, accuracy: 0.001,
                       "Sub-threshold ears are ignored; neckHeight falls back to nose")
    }

    // MARK: - 2D / 3D Parity (same image-space computation)

    func test_depthFusion_neckHeightMatches2D() {
        // The 3D path must compute neckHeight in the SAME image space as 2D, so the
        // metric stays comparable across camera modes.
        let base = earPose(shoulderY: 0.4, earY: 0.6)

        var fusion2D = PoseDepthFusion()
        let sample2D = fuse(base, fusion: &fusion2D)!

        var fusion3D = PoseDepthFusion()
        let intrinsics = simd_float3x3(columns: (
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0.5, 0.5, 1)
        ))
        let depthSamples = base.keypoints.map { DepthAtPoint(point: $0.position, depth: 0.6, confidence: 1.0) }
        let sample3D = fusion3D.fuse(
            pose: base,
            depthSamples: depthSamples,
            confidence: .medium,
            intrinsics: intrinsics,
            trackingQuality: .good
        )!

        XCTAssertEqual(sample3D.depthMode, .depthFusion)
        XCTAssertEqual(sample3D.neckHeight, sample2D.neckHeight, accuracy: 0.001,
                       "3D-path neckHeight must equal the 2D-path value (image-space computation in both)")
    }

    // MARK: - Default

    func test_neckHeightDefaultsZero() {
        // The additive-default keeps existing call sites valid.
        let sample = PoseSample(
            timestamp: 0,
            depthMode: .twoDOnly,
            headPosition: .zero,
            shoulderMidpoint: .zero,
            leftShoulder: .zero,
            rightShoulder: .zero,
            torsoAngle: 0,
            headForwardOffset: 0,
            shoulderTwist: 0,
            shoulderWidthRaw: 0,
            trackingQuality: .lost
        )
        XCTAssertEqual(sample.neckHeight, 0)
    }
}
