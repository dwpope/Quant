import XCTest
import simd
@testable import PostureLogic

/// The wire payload for the Jev proxy, and the one piece of arithmetic in it.
///
/// Two things here are load-bearing and were established by reading the metrics pipeline rather
/// than the plan. `lateralLeanSigned` is a raw `shoulderMidpoint.x` delta whose units change with
/// the camera mode — normalised image fraction in `.twoDOnly`, camera-space metres in
/// `.depthFusion` — so it is divided by the baseline shoulder width, which is expressed in the
/// same space in either mode, to make it dimensionless and comparable. And the proxy rejects any
/// non-finite number with a 400, while nothing upstream in this app guarantees finiteness, so the
/// payload refuses to build rather than producing a request that cannot succeed.
final class JevFeaturesTests: XCTestCase {

    private func makeSample(
        torsoAngle: Float = 9,
        shoulderWidthRaw: Float = 0.30,
        quality: TrackingQuality = .good,
        depthMode: DepthMode = .twoDOnly,
        headPitch: Float = -14,
        headYaw: Float = 2,
        headRoll: Float = 0.5
    ) -> PoseSample {
        PoseSample(
            timestamp: 123,
            depthMode: depthMode,
            headPosition: SIMD3<Float>(0.5, 0.8, 0),
            shoulderMidpoint: SIMD3<Float>(0.52, 0.6, 0),
            leftShoulder: SIMD3<Float>(0.37, 0.6, 0),
            rightShoulder: SIMD3<Float>(0.67, 0.6, 0),
            torsoAngle: torsoAngle,
            headForwardOffset: 0.02,
            shoulderTwist: 3,
            shoulderWidthRaw: shoulderWidthRaw,
            trackingQuality: quality,
            headPitch: headPitch,
            headYaw: headYaw,
            headRoll: headRoll
        )
    }

    private func makeMetrics(
        forwardCreep: Float = 0.22,
        headDrop: Float = 0.18,
        shoulderRounding: Float = 11,
        lateralLeanSigned: Float = 0.04,
        twistSigned: Float = 6
    ) -> RawMetrics {
        RawMetrics(
            timestamp: 123,
            forwardCreep: forwardCreep,
            headDrop: headDrop,
            shoulderRounding: shoulderRounding,
            lateralLean: abs(lateralLeanSigned),
            twist: abs(twistSigned),
            movementLevel: 0,
            headMovementPattern: .still,
            lateralLeanSigned: lateralLeanSigned,
            twistSigned: twistSigned
        )
    }

    private func makeBaseline(shoulderWidth: Float = 0.20) -> Baseline {
        Baseline(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
            headPosition: SIMD3<Float>(0.5, 0.8, 0),
            torsoAngle: 3,
            shoulderTwist: 1,
            shoulderWidth: shoulderWidth,
            depthAvailable: false,
            neckHeight: 0.35
        )
    }

    // MARK: - Mapping

    func test_make_takesHeadAnglesAndTorsoAngleFromThePoseSample() throws {
        let f = try XCTUnwrap(JevFeatures.make(
            sample: makeSample(), metrics: makeMetrics(), baseline: makeBaseline()))

        XCTAssertEqual(f.headYawDegrees, 2)
        XCTAssertEqual(f.headPitchDegrees, -14)
        XCTAssertEqual(f.headRollDegrees, 0.5)
        XCTAssertEqual(f.torsoAngleDegrees, 9)
    }

    func test_make_takesTheBaselineRelativeMetricsFromRawMetrics() throws {
        let f = try XCTUnwrap(JevFeatures.make(
            sample: makeSample(), metrics: makeMetrics(), baseline: makeBaseline()))

        XCTAssertEqual(f.forwardCreepFraction, 0.22)
        XCTAssertEqual(f.headDropInShoulderWidths, 0.18)
        XCTAssertEqual(f.torsoLeanDeltaDegrees, 11)
        XCTAssertEqual(f.shoulderTiltSignedDegrees, 6)
    }

    /// The correction that matters: a raw midpoint delta divided by baseline shoulder width.
    func test_make_normalisesLateralLeanByBaselineShoulderWidth() throws {
        let f = try XCTUnwrap(JevFeatures.make(
            sample: makeSample(),
            metrics: makeMetrics(lateralLeanSigned: 0.04),
            baseline: makeBaseline(shoulderWidth: 0.20)))

        XCTAssertEqual(f.lateralLeanInShoulderWidths, 0.2, accuracy: 1e-6)
    }

    func test_make_preservesTheSignOfLateralLean() throws {
        let f = try XCTUnwrap(JevFeatures.make(
            sample: makeSample(),
            metrics: makeMetrics(lateralLeanSigned: -0.04),
            baseline: makeBaseline(shoulderWidth: 0.20)))

        XCTAssertEqual(f.lateralLeanInShoulderWidths, -0.2, accuracy: 1e-6)
    }

    // MARK: - Refusing to build an unsendable payload

    func test_make_isNilWhenTheBaselineShoulderWidthIsDegenerate() {
        for width in [Float(0), 1e-7, -0.2] {
            XCTAssertNil(
                JevFeatures.make(sample: makeSample(), metrics: makeMetrics(),
                                 baseline: makeBaseline(shoulderWidth: width)),
                "shoulderWidth \(width) must not produce a payload")
        }
    }

    func test_make_isNilWhenAnyValueIsNotFinite() {
        XCTAssertNil(JevFeatures.make(
            sample: makeSample(torsoAngle: .nan), metrics: makeMetrics(), baseline: makeBaseline()))
        XCTAssertNil(JevFeatures.make(
            sample: makeSample(), metrics: makeMetrics(headDrop: .infinity), baseline: makeBaseline()))
        XCTAssertNil(JevFeatures.make(
            sample: makeSample(headYaw: -.infinity), metrics: makeMetrics(), baseline: makeBaseline()))
    }

    // MARK: - The wire contract

    func test_encodesExactlyTheKeysTheProxyAccepts() throws {
        let f = try XCTUnwrap(JevFeatures.make(
            sample: makeSample(), metrics: makeMetrics(), baseline: makeBaseline()))

        let data = try JSONEncoder().encode(f)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(json.keys), Set([
            "head_yaw_degrees", "head_pitch_degrees", "head_roll_degrees",
            "forward_creep_fraction_of_baseline_shoulder_width", "head_drop_in_shoulder_widths",
            "torso_lean_delta_degrees", "lateral_lean_in_shoulder_widths",
            "shoulder_tilt_signed_degrees", "torso_angle_degrees",
            "tracking_quality", "depth_mode",
        ]))
        XCTAssertEqual(json["tracking_quality"] as? String, "good")
        XCTAssertEqual(json["depth_mode"] as? String, "twoDOnly")
    }

    func test_trackingQualityEncodesEveryCaseTheProxyAccepts() throws {
        for quality in [TrackingQuality.good, .degraded, .lost] {
            let f = try XCTUnwrap(JevFeatures.make(
                sample: makeSample(quality: quality), metrics: makeMetrics(), baseline: makeBaseline()))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(
                with: try JSONEncoder().encode(f)) as? [String: Any])
            XCTAssertEqual(json["tracking_quality"] as? String, quality.rawValue)
        }
    }

    // MARK: - Decoding the proxy's answer

    func test_verdictDecodesTheProxyResponse() throws {
        let body = Data("""
        {"posture":"chair_swivel","confidence":0.81,
         "probabilities":{"chair_swivel":0.81,"lean":0.12,"slouch":0.07},
         "model":"jev-1.13.0"}
        """.utf8)

        let v = try JSONDecoder().decode(JevVerdict.self, from: body)

        XCTAssertEqual(v.posture, "chair_swivel")
        XCTAssertEqual(v.confidence, 0.81, accuracy: 1e-9)
        XCTAssertEqual(v.probabilities["lean"], 0.12)
        XCTAssertEqual(v.model, "jev-1.13.0")
    }

    /// The comparison record persists the exact payload that was sent, so it must decode as
    /// well as encode — otherwise step 3c cannot read back what Jev was actually asked.
    func test_featuresRoundTripThroughCodable() throws {
        let original = try XCTUnwrap(JevFeatures.make(
            sample: makeSample(), metrics: makeMetrics(), baseline: makeBaseline()))

        let decoded = try JSONDecoder().decode(
            JevFeatures.self, from: try JSONEncoder().encode(original))

        XCTAssertEqual(decoded, original)
    }
}
