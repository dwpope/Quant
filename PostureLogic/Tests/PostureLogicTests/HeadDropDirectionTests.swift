import XCTest
import Combine
@testable import PostureLogic

/// Head drop counts the way it actually reads on the device (2026-10-05).
///
/// Image y runs down on the device (PoseService flips Vision's), so a head dropping towards the
/// shoulders reads NEGATIVE: every one of Dave's 15 slouches across five sessions read -0.013 to
/// -0.186. The thresholds tripped on head drop above +0.15, which assumed y runs up and never
/// happens: across 64 captures it fired once, on a chair swivel. The Jev wording already uses it
/// the right way round: -0.015 or lower is a slouch. The thresholds now do the same, except with
/// the chair turned, where it can read a little negative too.
///
/// Replaying the thresholds over all 65 judged captures: misses 3 -> 0, false alarms 11 -> 10.
final class HeadDropDirectionTests: XCTestCase {

    private func metrics(headDrop: Float, forwardCreep: Float = 0, at time: TimeInterval) -> RawMetrics {
        RawMetrics(timestamp: time, forwardCreep: forwardCreep, headDrop: headDrop, shoulderRounding: 0,
                   lateralLean: 0, twist: 0, movementLevel: 0, headMovementPattern: .still,
                   lateralLeanSigned: 0, twistSigned: 0)
    }

    /// The state after one good frame, then one frame at `headDrop`.
    private func state(headDrop: Float, chairTurned: Bool = false) -> PostureState {
        let engine = PostureEngine()
        engine.update(metrics: metrics(headDrop: 0, at: 0), taskMode: .unknown, trackingQuality: .good)
        return engine.update(metrics: metrics(headDrop: headDrop, at: 1), taskMode: .unknown,
                             trackingQuality: .good, chairTurned: chairTurned)
    }

    private func isDrifting(_ state: PostureState) -> Bool {
        if case .drifting = state { return true }
        return false
    }

    func test_theTripPoint_isTheJevWordings() {
        XCTAssertEqual(PostureThresholds().headDropThreshold, 0.015,
                       "the head 0.015 shoulder widths closer to the shoulders than at calibration")
    }

    /// Every slouch measured on device read at or below -0.013; the weakest two that barely came
    /// forward read -0.020 and -0.040.
    func test_aHeadDroppedTowardsTheShoulders_isASlouch() {
        XCTAssertTrue(isDrifting(state(headDrop: -0.02)))
        XCTAssertTrue(isDrifting(state(headDrop: -0.015)))
    }

    /// Every upright read -0.007 or above.
    func test_sittingAsCalibrated_isNot() {
        XCTAssertEqual(state(headDrop: -0.007), .good)
        XCTAssertEqual(state(headDrop: 0.019), .good)
    }

    /// The old direction fired once in 64 captures, on a swivel (+0.183), and never on a slouch.
    func test_aPositiveHeadDrop_isNoLongerASlouch() {
        XCTAssertEqual(state(headDrop: 0.183), .good)
    }

    /// Two measured swivels read -0.016 and -0.021: with the chair turned, it isn't a slouch.
    func test_withTheChairTurned_aHeadDropIsNot() {
        XCTAssertEqual(state(headDrop: -0.021, chairTurned: true), .good)
    }

    // MARK: - The nudge's advice

    /// A dropped head is the nudge's reason when it dominates, and the advice is to lift it.
    func test_aDroppedHead_isTheNudgesReason_whenItDominates() {
        var thresholds = PostureThresholds()
        thresholds.slouchDurationBeforeNudge = 0
        let engine = NudgeEngine(thresholds: thresholds)
        let decision = engine.evaluate(state: .bad(since: 0), trackingQuality: .good, movementLevel: 0,
                                       taskMode: .unknown, currentTime: 1,
                                       metrics: metrics(headDrop: -0.06, forwardCreep: 0.01, at: 1),
                                       headTurnedSince: nil, silenced: false)
        guard case .fire(let reason) = decision else { return XCTFail("expected a nudge") }
        XCTAssertEqual(reason, .headDrop)
        XCTAssertTrue(NudgeReason.headDrop.coachingMessage.contains("Lift your head"))
    }

    // MARK: - The chair, as the pipeline sees it

    func test_chairTurned_isTheHeadTurnRulesOtherHalf() {
        let h = HeadTurnThresholds()
        XCTAssertTrue(HeadTurnTracker.isChairTurned(headYaw: -66, forwardCreep: -0.277, thresholds: h))
        XCTAssertTrue(HeadTurnTracker.isChairTurned(headYaw: -71, forwardCreep: -0.053, thresholds: h))
        XCTAssertFalse(HeadTurnTracker.isChairTurned(headYaw: 70, forwardCreep: 0.05, thresholds: h),
                       "the neck turned, not the chair")
        XCTAssertFalse(HeadTurnTracker.isChairTurned(headYaw: 10, forwardCreep: -0.1, thresholds: h))
    }

    private func samples(yaw: Float, shoulderWidth: Float, neckHeight: Float, count: Int) -> [PoseSample] {
        (0..<count).map { i in
            PoseSample(
                timestamp: 670_636 + Double(i) * 0.5, depthMode: .twoDOnly,
                headPosition: SIMD3<Float>(0, 1.0, 0), shoulderMidpoint: SIMD3<Float>(0, 0, 0),
                leftShoulder: SIMD3<Float>(-0.5, 0, 0), rightShoulder: SIMD3<Float>(0.5, 0, 0),
                torsoAngle: 5, headForwardOffset: 0.01, shoulderTwist: 2,
                shoulderWidthRaw: shoulderWidth, trackingQuality: .good,
                headYaw: yaw, neckHeight: neckHeight)
        }
    }

    private func finalState(_ samples: [PoseSample]) async throws -> PostureState {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        try await provider.start()
        let done = XCTestExpectation(description: "every frame processed")
        let frames = pipeline.$latestMetrics.sink { m in
            if let t = m?.timestamp, t >= samples.last!.timestamp { done.fulfill() }
        }
        for s in samples {
            provider.emit(frame: InputFrame(timestamp: s.timestamp, pixelBuffer: nil, depthMap: nil,
                                            cameraIntrinsics: nil, precomputedSample: s))
        }
        await fulfillment(of: [done], timeout: 5)
        frames.cancel()
        return pipeline.postureState
    }

    func test_pipeline_aDroppedHeadFacingThePhone_drifts() async throws {
        let state = try await finalState(samples(yaw: 0, shoulderWidth: 0.2, neckHeight: 0.04, count: 6))
        XCTAssertTrue(isDrifting(state), "got \(state)")
    }

    func test_pipeline_aDroppedHeadWithTheChairTurned_staysGood() async throws {
        let state = try await finalState(samples(yaw: 66, shoulderWidth: 0.17, neckHeight: 0.04, count: 6))
        XCTAssertEqual(state, .good)
    }
}
