import XCTest
import Combine
@testable import PostureLogic

/// Turning isn't slouching or leaning (2026-10-07).
///
/// The thresholds were built for someone facing the phone. Turning the head reads the shoulders
/// wider (head turns +0.01 to +0.16 forward creep), and turning the chair shifts the shoulder
/// midpoint sideways, so both head turns and both swivels in session 12 read as bad posture. That
/// includes turning the chair to face the side screen, the head-turn nudge's own advice.
/// Simulated over all 163 judged captures from sessions 2-12: false alarms 18 -> 6, one lean lost
/// (head turned 51° with the shoulders 4% narrower, which looks exactly like a swivel).
final class TurningExceptionsTests: XCTestCase {

    private func state(creep: Float = 0, lean: Float = 0, headDrop: Float = 0, sink: Float = 0,
                       neckTurned: Bool = false, chairTurned: Bool = false) -> PostureState {
        let engine = PostureEngine()
        engine.update(metrics: RawMetrics(timestamp: 0, forwardCreep: 0, headDrop: 0, shoulderRounding: 0,
                                          lateralLean: 0, twist: 0, movementLevel: 0, headMovementPattern: .still),
                      taskMode: .unknown, trackingQuality: .good)
        let m = RawMetrics(timestamp: 1, forwardCreep: creep, headDrop: headDrop, shoulderRounding: 0,
                           lateralLean: lean, twist: 0, movementLevel: 0, headMovementPattern: .still,
                           shoulderSink: sink)
        return engine.update(metrics: m, taskMode: .unknown, trackingQuality: .good,
                             chairTurned: chairTurned, neckTurned: neckTurned)
    }

    private func drifts(_ s: PostureState) -> Bool {
        if case .drifting = s { return true }
        return false
    }

    // MARK: - Neck turned: forward creep doesn't count

    func test_neckTurned_theWiderLookingShoulders_dontCount() {
        for creep: Float in [0.162, 0.139, 0.082, 0.064, 0.049] {
            XCTAssertEqual(state(creep: creep, neckTurned: true), .good, "\(creep)")
        }
    }

    func test_facingThePhone_forwardCreepStillCounts() {
        XCTAssertTrue(drifts(state(creep: 0.082)))
    }

    /// Session 5's slouch with the head turned 56°: still caught, by head drop.
    func test_neckTurned_aSlouchStillCounts_byItsHeadDrop() {
        XCTAssertTrue(drifts(state(creep: 0.214, headDrop: -0.156, neckTurned: true)))
    }

    /// Leaning sideways with the head turned and the shoulders square is still a lean.
    func test_neckTurned_aLeanStillCounts() {
        XCTAssertTrue(drifts(state(creep: 0.095, lean: 0.14, neckTurned: true)))
    }

    // MARK: - Chair turned: a sideways shift doesn't count

    func test_chairTurned_theSidewaysShift_doesntCount() {
        XCTAssertEqual(state(creep: -0.185, lean: 0.10, chairTurned: true), .good)
        XCTAssertEqual(state(creep: -0.038, lean: 0.146, chairTurned: true), .good)
    }

    func test_facingThePhone_aSidewaysShiftStillCounts() {
        XCTAssertTrue(drifts(state(lean: 0.10)))
    }

    func test_chairTurned_aSinkStillCounts() {
        XCTAssertTrue(drifts(state(creep: -0.1, sink: 0.1, chairTurned: true)))
    }

    // MARK: - Through the pipeline, from head yaw and shoulder width

    private func finalState(yaw: Float, shoulderWidth: Float, shoulderX: Float) async throws -> PostureState {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()   // shoulders at x 0, 0.2 wide
        try await provider.start()
        let samples = (0..<6).map { i in
            PoseSample(timestamp: 670_636 + Double(i) * 0.5, depthMode: .twoDOnly,
                       headPosition: SIMD3<Float>(0, 1.0, 0), shoulderMidpoint: SIMD3<Float>(shoulderX, 0, 0),
                       leftShoulder: SIMD3<Float>(-0.5, 0, 0), rightShoulder: SIMD3<Float>(0.5, 0, 0),
                       torsoAngle: 5, headForwardOffset: 0.01, shoulderTwist: 2,
                       shoulderWidthRaw: shoulderWidth, trackingQuality: .good, headYaw: yaw)
        }
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

    /// Looking at the side screen: head 70°, shoulders reading 8% wider.
    func test_pipeline_lookingAtTheSideScreen_staysGood() async throws {
        let s = try await finalState(yaw: 70, shoulderWidth: 0.216, shoulderX: 0)
        XCTAssertEqual(s, .good)
    }

    /// The chair turned to face it: head 70°, shoulders 10% narrower and shifted sideways.
    func test_pipeline_theChairTurnedToTheSideScreen_staysGood() async throws {
        let s = try await finalState(yaw: 70, shoulderWidth: 0.18, shoulderX: 0.1)
        XCTAssertEqual(s, .good)
    }

    /// The same sideways shift facing the phone is a lean.
    func test_pipeline_theSameShiftFacingThePhone_drifts() async throws {
        let s = try await finalState(yaw: 0, shoulderWidth: 0.2, shoulderX: 0.1)
        guard case .drifting = s else { return XCTFail("a sideways shift facing the phone should drift, got \(s)") }
    }
}
