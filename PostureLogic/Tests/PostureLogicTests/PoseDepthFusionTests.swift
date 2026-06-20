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

    // MARK: - Head Roll (ear-line atan2; eye-line fallback)
    //
    // Sign convention is locked to `computeShoulderTwist` above: inside the
    // fusion, *larger y = physically higher* (see test_shoulderTwistPositiveWhenLeftHigher,
    // which calls y=0.55 "higher"). Roll is the tilt of the ear line from
    // horizontal; the run uses |Δx| so a level head reads ~0° regardless of
    // which ear sits at larger image-x (front-facing subjects vs. synthetic
    // layouts). Defined sign: right ear physically lower → negative roll.

    func test_headRoll_zeroWhenEarsLevel() {
        let fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftEar,  x: 0.45, y: 0.70),
            makeKeypoint(.rightEar, x: 0.55, y: 0.70),
        ])
        XCTAssertEqual(fusion.computeHeadAngles(from: pose).roll, 0, accuracy: 0.5)
    }

    func test_headRoll_negativeWhenRightEarLower() {
        let fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftEar,  x: 0.45, y: 0.72),   // higher
            makeKeypoint(.rightEar, x: 0.55, y: 0.68),   // lower
        ])
        XCTAssertLessThan(fusion.computeHeadAngles(from: pose).roll, 0)
    }

    func test_headRoll_positiveWhenLeftEarLower() {
        let fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftEar,  x: 0.45, y: 0.68),   // lower
            makeKeypoint(.rightEar, x: 0.55, y: 0.72),   // higher
        ])
        XCTAssertGreaterThan(fusion.computeHeadAngles(from: pose).roll, 0)
    }

    func test_headRoll_fallsBackToEyeLineWhenEarsMissing() {
        let fusion = PoseDepthFusion()
        // No ears; eyes present and tilted so the right side is lower.
        let pose = makePose(keypoints: [
            makeKeypoint(.leftEye,  x: 0.47, y: 0.72),   // higher
            makeKeypoint(.rightEye, x: 0.53, y: 0.68),   // lower
        ])
        XCTAssertLessThan(fusion.computeHeadAngles(from: pose).roll, 0)
    }

    func test_headRoll_zeroWhenNoEarsOrEyes() {
        let fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ])
        XCTAssertEqual(fusion.computeHeadAngles(from: pose).roll, 0, accuracy: 0.001)
    }

    // MARK: - Head Yaw (nose horizontal offset from ear-midpoint ÷ ear separation)

    // Sign convention (locked here, deferred semantics handled in the ViewModel):
    // positive yaw = nose displaced toward `.rightEar` (larger image-x in these
    // synthetic layouts); negative = toward `.leftEar`. One-ear-missing rule: a
    // strong head turn occludes the far ear, so exactly one ear present implies a
    // strong yaw *toward the missing side* — missing `.rightEar` → strong positive,
    // missing `.leftEar` → strong negative.

    func test_headYaw_zeroWhenNoseCentredBetweenEars() {
        let fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftEar,  x: 0.40, y: 0.70),
            makeKeypoint(.rightEar, x: 0.60, y: 0.70),
            makeKeypoint(.nose,     x: 0.50, y: 0.65),   // centred between ears
        ])
        XCTAssertEqual(fusion.computeHeadAngles(from: pose).yaw, 0, accuracy: 0.5)
    }

    func test_headYaw_positiveWhenNoseTowardRightEar() {
        let fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftEar,  x: 0.40, y: 0.70),
            makeKeypoint(.rightEar, x: 0.60, y: 0.70),
            makeKeypoint(.nose,     x: 0.55, y: 0.65),   // shifted toward right ear
        ])
        XCTAssertGreaterThan(fusion.computeHeadAngles(from: pose).yaw, 0)
    }

    func test_headYaw_negativeWhenNoseTowardLeftEar() {
        let fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftEar,  x: 0.40, y: 0.70),
            makeKeypoint(.rightEar, x: 0.60, y: 0.70),
            makeKeypoint(.nose,     x: 0.45, y: 0.65),   // shifted toward left ear
        ])
        XCTAssertLessThan(fusion.computeHeadAngles(from: pose).yaw, 0)
    }

    func test_headYaw_strongPositiveWhenRightEarMissing() {
        let fusion = PoseDepthFusion()
        // Right ear occluded by a strong turn → strong yaw toward the right.
        let pose = makePose(keypoints: [
            makeKeypoint(.leftEar, x: 0.45, y: 0.70),
            makeKeypoint(.nose,    x: 0.50, y: 0.65),
        ])
        XCTAssertGreaterThan(fusion.computeHeadAngles(from: pose).yaw, 30)
    }

    func test_headYaw_strongNegativeWhenLeftEarMissing() {
        let fusion = PoseDepthFusion()
        // Left ear occluded by a strong turn → strong yaw toward the left.
        let pose = makePose(keypoints: [
            makeKeypoint(.rightEar, x: 0.55, y: 0.70),
            makeKeypoint(.nose,     x: 0.50, y: 0.65),
        ])
        XCTAssertLessThan(fusion.computeHeadAngles(from: pose).yaw, -30)
    }

    func test_headYaw_zeroWhenNoEars() {
        let fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ])
        XCTAssertEqual(fusion.computeHeadAngles(from: pose).yaw, 0, accuracy: 0.001)
    }

    func test_headYaw_zeroWhenNoseMissing() {
        let fusion = PoseDepthFusion()
        // Both ears present but no nose → can't measure the offset → neutral.
        let pose = makePose(keypoints: [
            makeKeypoint(.leftEar,  x: 0.40, y: 0.70),
            makeKeypoint(.rightEar, x: 0.60, y: 0.70),
        ])
        XCTAssertEqual(fusion.computeHeadAngles(from: pose).yaw, 0, accuracy: 0.001)
    }

    // MARK: - Head Yaw (one-ear proportional regime, scaled off the eyes)

    // When one ear occludes (strong turn) but the eyes are still visible, yaw is
    // a *proportional* estimate — θ = atan(k · noseOffset/eyeSeparation) — rather
    // than the flat ±oneEarMissingYawDegrees fallback. It must (a) keep the locked
    // sign (missing right → +, missing left → −), (b) stay strictly monotonic in
    // the turn (more nose offset ⇒ more yaw, no snap), and (c) stay bounded < 90°.

    /// Builds a one-ear-occluded pose with the eyes visible. `noseOffset` is the
    /// nose's image-x displacement from the eye midpoint (0.5); larger ⇒ more turn.
    private func oneEarPose(missingRightEar: Bool, noseOffset: CGFloat) -> PoseObservation {
        let visibleEar: Keypoint = missingRightEar
            ? makeKeypoint(.leftEar,  x: 0.45, y: 0.70)
            : makeKeypoint(.rightEar, x: 0.55, y: 0.70)
        // Sign of the nose displacement follows the missing side (toward the turn).
        let noseX = 0.5 + (missingRightEar ? noseOffset : -noseOffset)
        return makePose(keypoints: [
            visibleEar,
            makeKeypoint(.leftEye,  x: 0.45, y: 0.72),
            makeKeypoint(.rightEye, x: 0.55, y: 0.72),
            makeKeypoint(.nose,     x: noseX, y: 0.65),
        ])
    }

    func test_headYaw_oneEar_proportionalAndMonotonicWithEyes() {
        let fusion = PoseDepthFusion()
        // Right ear missing, eyes visible, increasing nose offset ⇒ bigger turn.
        let small = fusion.computeHeadAngles(from: oneEarPose(missingRightEar: true, noseOffset: 0.05)).yaw
        let mid   = fusion.computeHeadAngles(from: oneEarPose(missingRightEar: true, noseOffset: 0.20)).yaw
        let large = fusion.computeHeadAngles(from: oneEarPose(missingRightEar: true, noseOffset: 0.40)).yaw

        // Locked sign + proportional (not pinned to the flat 60° fallback).
        XCTAssertGreaterThan(small, 0)
        XCTAssertLessThan(small, mid)       // strictly monotonic — the anti-snap property
        XCTAssertLessThan(mid, large)
        XCTAssertLessThan(large, 90)        // bounded by the atan ceiling
        XCTAssertNotEqual(mid, 60, accuracy: 0.001)  // genuinely proportional, not the constant
    }

    func test_headYaw_oneEar_signFollowsMissingSideWithEyes() {
        let fusion = PoseDepthFusion()
        let rightMissing = fusion.computeHeadAngles(from: oneEarPose(missingRightEar: true,  noseOffset: 0.25)).yaw
        let leftMissing  = fusion.computeHeadAngles(from: oneEarPose(missingRightEar: false, noseOffset: 0.25)).yaw
        XCTAssertGreaterThan(rightMissing, 0)               // missing right ear → positive
        XCTAssertLessThan(leftMissing, 0)                   // missing left ear  → negative
        XCTAssertEqual(rightMissing, -leftMissing, accuracy: 0.001)  // symmetric magnitude
    }

    func test_headYaw_oneEar_fallsBackToConstantWhenEyesMissing() {
        let fusion = PoseDepthFusion()
        // No eyes to scale the turn → flat fallback (still strong, still signed).
        let pose = makePose(keypoints: [
            makeKeypoint(.leftEar, x: 0.45, y: 0.70),
            makeKeypoint(.nose,    x: 0.50, y: 0.65),
        ])
        XCTAssertEqual(fusion.computeHeadAngles(from: pose).yaw, 60, accuracy: 0.001)
    }

    // MARK: - Head Pitch (2D: nose vertical offset vs eye/ear line, normalized)

    // Coarse 2D proxy — refined by LiDAR depth in a later sub-stage. Sign locked:
    // nose *below* the eye/ear line (chin-down / forward-head tilt) → positive
    // pitch (matches Step 8's "forward head tilt ≈ pitch > 15°"). Raw zero is the
    // geometric on-the-line case, not a physiological neutral; the ViewModel's
    // rest-relative calibration re-zeros it downstream. y-up: nose below ⇒ nose.y
    // < lineY. Ear line primary, eye line fallback (mirrors roll).

    func test_headPitch_zeroWhenNoseOnEarLine() {
        let fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftEar,  x: 0.45, y: 0.70),
            makeKeypoint(.rightEar, x: 0.55, y: 0.70),
            makeKeypoint(.nose,     x: 0.50, y: 0.70),   // on the ear line
        ])
        XCTAssertEqual(fusion.computeHeadAngles(from: pose).pitch, 0, accuracy: 0.5)
    }

    func test_headPitch_positiveWhenNoseBelowLine() {
        let fusion = PoseDepthFusion()
        // Nose dropped below the ear line (chin-down geometry).
        let pose = makePose(keypoints: [
            makeKeypoint(.leftEar,  x: 0.45, y: 0.70),
            makeKeypoint(.rightEar, x: 0.55, y: 0.70),
            makeKeypoint(.nose,     x: 0.50, y: 0.60),   // below the line (y-up)
        ])
        XCTAssertGreaterThan(fusion.computeHeadAngles(from: pose).pitch, 0)
    }

    func test_headPitch_negativeWhenNoseAboveLine() {
        let fusion = PoseDepthFusion()
        // Nose raised above the ear line (chin-up geometry).
        let pose = makePose(keypoints: [
            makeKeypoint(.leftEar,  x: 0.45, y: 0.70),
            makeKeypoint(.rightEar, x: 0.55, y: 0.70),
            makeKeypoint(.nose,     x: 0.50, y: 0.80),   // above the line (y-up)
        ])
        XCTAssertLessThan(fusion.computeHeadAngles(from: pose).pitch, 0)
    }

    func test_headPitch_fallsBackToEyeLineWhenEarsMissing() {
        let fusion = PoseDepthFusion()
        // No ears; eyes present, nose dropped below the eye line → positive.
        let pose = makePose(keypoints: [
            makeKeypoint(.leftEye,  x: 0.47, y: 0.72),
            makeKeypoint(.rightEye, x: 0.53, y: 0.72),
            makeKeypoint(.nose,     x: 0.50, y: 0.62),
        ])
        XCTAssertGreaterThan(fusion.computeHeadAngles(from: pose).pitch, 0)
    }

    func test_headPitch_zeroWhenNoseMissing() {
        let fusion = PoseDepthFusion()
        let pose = makePose(keypoints: [
            makeKeypoint(.leftEar,  x: 0.45, y: 0.70),
            makeKeypoint(.rightEar, x: 0.55, y: 0.70),
        ])
        XCTAssertEqual(fusion.computeHeadAngles(from: pose).pitch, 0, accuracy: 0.001)
    }

    func test_headPitch_zeroWhenNoReferenceLine() {
        let fusion = PoseDepthFusion()
        // Only the nose → no eye/ear line to reference → neutral.
        let pose = makePose(keypoints: [
            makeKeypoint(.nose, x: 0.5, y: 0.7),
        ])
        XCTAssertEqual(fusion.computeHeadAngles(from: pose).pitch, 0, accuracy: 0.001)
    }

    // MARK: - Head Pitch (3D: LiDAR depth elevation, nose vs. ear plane)
    //
    // Step 3 upgrade: when depth is available, pitch becomes a true elevation angle
    // from the nose's *depth* relative to the ear plane — NOT the image-plane
    // vertical the 2D path uses. To isolate that signal these poses keep the nose
    // ON the ear line (equal image-y) so the 2D pitch is ~0; any non-zero pitch
    // must therefore come from depth. Sign matches the 2D *direction* so the
    // ViewModel behaves identically in either mode: nose nearer than the ears
    // (relaxed, protruding face) → negative; nose farther / through the ear plane
    // (chin-down / tech-neck) → positive. When the nose/ear depth is unavailable
    // the 2D vertical fallback still drives pitch.

    /// Shoulders + level ears + nose-on-ear-line, with a depth per point. Nose is
    /// at the same image-y as the ears so the 2D pitch is ~0 and only depth moves
    /// the 3D pitch.
    private func headDepthPose(noseDepth: Float, earDepth: Float) -> (PoseObservation, [DepthAtPoint]) {
        let keypoints = [
            makeKeypoint(.leftShoulder,  x: 0.40, y: 0.50),
            makeKeypoint(.rightShoulder, x: 0.60, y: 0.50),
            makeKeypoint(.leftEar,       x: 0.45, y: 0.70),
            makeKeypoint(.rightEar,      x: 0.55, y: 0.70),
            makeKeypoint(.nose,          x: 0.50, y: 0.70),   // ON the ear line ⇒ 2D pitch ~0
        ]
        let samples = [
            DepthAtPoint(point: keypoints[0].position, depth: 0.60, confidence: 1.0),  // shoulders
            DepthAtPoint(point: keypoints[1].position, depth: 0.60, confidence: 1.0),
            DepthAtPoint(point: keypoints[2].position, depth: earDepth, confidence: 1.0),  // ears
            DepthAtPoint(point: keypoints[3].position, depth: earDepth, confidence: 1.0),
            DepthAtPoint(point: keypoints[4].position, depth: noseDepth, confidence: 1.0),  // nose
        ]
        return (makePose(keypoints: keypoints), samples)
    }

    func test_headPitch3D_negativeWhenNoseNearerThanEars() {
        var fusion = PoseDepthFusion()
        // Nose closer to the camera than the ears (relaxed, protruding face).
        let (pose, samples) = headDepthPose(noseDepth: 0.50, earDepth: 0.60)
        let sample = fusion.fuse(
            pose: pose,
            depthSamples: samples,
            confidence: .high,
            intrinsics: makeIntrinsics(),
            trackingQuality: .good
        )!
        XCTAssertEqual(sample.depthMode, .depthFusion)
        XCTAssertLessThan(sample.headPitch, 0, "nose nearer than ears ⇒ negative 3D pitch")
    }

    func test_headPitch3D_positiveWhenNoseFartherThanEars() {
        var fusion = PoseDepthFusion()
        // Nose farther from the camera than the ears (chin-down / tech-neck).
        let (pose, samples) = headDepthPose(noseDepth: 0.70, earDepth: 0.60)
        let sample = fusion.fuse(
            pose: pose,
            depthSamples: samples,
            confidence: .high,
            intrinsics: makeIntrinsics(),
            trackingQuality: .good
        )!
        XCTAssertEqual(sample.depthMode, .depthFusion)
        XCTAssertGreaterThan(sample.headPitch, 0, "nose farther than ears ⇒ positive 3D pitch")
    }

    func test_headPitch3D_fallsBackTo2DPitchWhenEarDepthMissing() {
        var fusion = PoseDepthFusion()
        // Depth covers the shoulders + nose (so the depth path runs → .depthFusion),
        // but the EARS have no depth sample → the 3D elevation can't be formed →
        // pitch falls back to the 2D nose-vs-ear-line value. Nose dropped below the
        // ear line (y-up) so that 2D fallback is positive.
        let keypoints = [
            makeKeypoint(.leftShoulder,  x: 0.40, y: 0.50),
            makeKeypoint(.rightShoulder, x: 0.60, y: 0.50),
            makeKeypoint(.leftEar,       x: 0.45, y: 0.70),
            makeKeypoint(.rightEar,      x: 0.55, y: 0.70),
            makeKeypoint(.nose,          x: 0.50, y: 0.60),   // below the ear line (y-up)
        ]
        // Depth for shoulders + nose only — none near the ears.
        let samples = [
            DepthAtPoint(point: keypoints[0].position, depth: 0.60, confidence: 1.0),
            DepthAtPoint(point: keypoints[1].position, depth: 0.60, confidence: 1.0),
            DepthAtPoint(point: keypoints[4].position, depth: 0.50, confidence: 1.0),
        ]
        let sample = fusion.fuse(
            pose: makePose(keypoints: keypoints),
            depthSamples: samples,
            confidence: .high,
            intrinsics: makeIntrinsics(),
            trackingQuality: .good
        )!
        XCTAssertEqual(sample.depthMode, .depthFusion)
        XCTAssertGreaterThan(sample.headPitch, 0, "ear depth missing ⇒ 2D pitch fallback (positive)")
    }

    // MARK: - Head Angles on PoseSample (plumbing: fuse → sample)

    // The angle math above is exercised directly via `computeHeadAngles`. These two
    // assert the *plumbing*: that `fuse(...)` actually writes those three angles
    // onto the produced `PoseSample`. A fully-keypointed frame must surface
    // non-zero values on all three channels; a frame whose head reduces to a bare
    // position (nose only — no ear/eye line, no ear pair) must surface neutral 0.

    func test_fuse_populatesHeadAnglesWhenFacialKeypointsPresent() {
        var fusion = PoseDepthFusion()
        // One layout that drives all three axes off-zero at once:
        //  • ear line tilted (left ear lower)      → positive roll
        //  • nose displaced toward the right ear    → positive yaw
        //  • nose dropped below the ear line (y-up)  → positive pitch
        let pose = makePose(keypoints: [
            makeKeypoint(.leftShoulder,  x: 0.40, y: 0.50),
            makeKeypoint(.rightShoulder, x: 0.60, y: 0.50),
            makeKeypoint(.leftEar,       x: 0.45, y: 0.68),   // lower
            makeKeypoint(.rightEar,      x: 0.55, y: 0.72),   // higher
            makeKeypoint(.nose,          x: 0.53, y: 0.60),   // right-of-mid, below line
        ])
        guard let sample = fuse(pose, fusion: &fusion) else {
            return XCTFail("fuse should produce a sample for a fully-keypointed pose")
        }
        XCTAssertGreaterThan(sample.headRoll,  0, "left ear lower ⇒ positive roll")
        XCTAssertGreaterThan(sample.headYaw,   0, "nose toward right ear ⇒ positive yaw")
        XCTAssertGreaterThan(sample.headPitch, 0, "nose below ear line ⇒ positive pitch")
    }

    func test_fuse_headAnglesNeutralWhenNoFacialGeometry() {
        var fusion = PoseDepthFusion()
        // `uprightPose()` is shoulders + a bare nose: the head position resolves
        // (so a sample IS produced), but there is no ear/eye line and no ear pair,
        // so all three head angles must read exactly 0.
        guard let sample = fuse(uprightPose(), fusion: &fusion) else {
            return XCTFail("fuse should produce a sample for shoulders + nose")
        }
        XCTAssertEqual(sample.headPitch, 0, accuracy: 0.001)
        XCTAssertEqual(sample.headYaw,   0, accuracy: 0.001)
        XCTAssertEqual(sample.headRoll,  0, accuracy: 0.001)
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

    // MARK: - Shared turn geometry (used by the external/legacy head-angle tests)

    /// Keypoints that encode a left/right TURN: the nose sits offset toward one ear
    /// and below the ear line, so the legacy 2D pitch formula couples the turn into a
    /// phantom nod (this is the "W"). The external/legacy tests reuse it.
    private func turnGeometry() -> [Keypoint] {
        [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.3),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.3),
            makeKeypoint(.leftEar, x: 0.40, y: 0.60),
            makeKeypoint(.rightEar, x: 0.60, y: 0.60),
            makeKeypoint(.nose, x: 0.55, y: 0.50),   // offset right + below line ⇒ legacy phantom pitch
        ]
    }

    // MARK: - External (ARKit ARFaceAnchor) head angles — Layer 1, Tier 1

    private func makeExternalPose(
        _ angles: HeadAngles,
        keypoints: [Keypoint]? = nil
    ) -> PoseObservation {
        PoseObservation(
            timestamp: 1.0, keypoints: keypoints ?? turnGeometry(), confidence: 0.9,
            externalHeadAngles: angles
        )
    }

    /// ARKit angles are authoritative and pass through verbatim — the legacy 2D
    /// estimate is never consulted when an external head pose is present.
    func test_external_winsVerbatim() {
        var fusion = PoseDepthFusion()
        let ext = HeadAngles(pitch: 7, yaw: -23, roll: 4)
        let s = fuse(makeExternalPose(ext), fusion: &fusion)!
        XCTAssertEqual(s.headPitch, 7, accuracy: 1e-4)
        XCTAssertEqual(s.headYaw, -23, accuracy: 1e-4)
        XCTAssertEqual(s.headRoll, 4, accuracy: 1e-4)
    }

    /// External nil → byte-identical to the pre-Layer-1 legacy path (regression pin).
    func test_external_nil_isLegacyExactly() {
        var fusion = PoseDepthFusion()
        let kps = turnGeometry()
        let legacy = fuse(makePose(keypoints: kps), fusion: &fusion)!
        let viaNil = fuse(
            PoseObservation(timestamp: 1.0, keypoints: kps, confidence: 0.9, externalHeadAngles: nil),
            fusion: &fusion
        )!
        XCTAssertEqual(viaNil.headPitch, legacy.headPitch, accuracy: 1e-6)
        XCTAssertEqual(viaNil.headYaw, legacy.headYaw, accuracy: 1e-6)
        XCTAssertEqual(viaNil.headRoll, legacy.headRoll, accuracy: 1e-6)
    }

    /// In depth mode, the LiDAR elevation pitch must NOT clobber an authoritative
    /// ARKit pitch (the fuse3D guard).
    func test_external_pitchSurvivesLiDAROverrideInDepthMode() {
        var fusion = PoseDepthFusion()
        let ext = HeadAngles(pitch: 12, yaw: 0, roll: 0)
        // Upright depth pose with the external head angles attached.
        let kps = [
            makeKeypoint(.leftShoulder, x: 0.4, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.6, y: 0.5),
            makeKeypoint(.nose, x: 0.5, y: 0.7),
            makeKeypoint(.leftEar, x: 0.45, y: 0.72),
            makeKeypoint(.rightEar, x: 0.55, y: 0.72),
        ]
        let pose = PoseObservation(timestamp: 1.0, keypoints: kps, confidence: 0.9, externalHeadAngles: ext)
        let samples = makeDepthSamples(for: pose.keypoints, depth: 0.6)
        let result = fusion.fuse(
            pose: pose, depthSamples: samples, confidence: .high,
            intrinsics: makeIntrinsics(), trackingQuality: .good
        )!
        XCTAssertEqual(result.depthMode, .depthFusion)
        XCTAssertEqual(result.headPitch, 12, accuracy: 1e-4, "ARKit pitch must survive the LiDAR pitch3D override")
    }
}
