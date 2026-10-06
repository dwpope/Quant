import XCTest
import Combine
@testable import PostureLogic

/// Leaning back against the backrest isn't a slouch (2026-10-05).
///
/// Session 9: reclining lowered the shoulders in the frame like a sink (+0.078, +0.083) and read as
/// a head drop (-0.039, -0.100), so Jev and the thresholds both called it a slouch. It also moved
/// the shoulders a long way back: forward creep -0.232 and -0.233, against -0.03 to -0.10 for
/// every sink. Across all 134 captures nothing else moved them 10% back without the head turned.
/// Reclined, sink and head drop don't count.
final class ReclinedTests: XCTestCase {

    func test_theLine_isShoulders15PercentFurtherBack() {
        XCTAssertEqual(PostureThresholds().reclineMaxForwardCreep, -0.15)
    }

    func test_theRule_overEveryCaptureSoFar() {
        let t = PostureThresholds(), h = HeadTurnThresholds()
        // Lean back, session 9.
        XCTAssertTrue(PostureEngine.isReclined(forwardCreep: -0.232, headYawFromCalibration: -3, thresholds: t, headTurn: h))
        XCTAssertTrue(PostureEngine.isReclined(forwardCreep: -0.233, headYawFromCalibration: -1, thresholds: t, headTurn: h))
        // Sinks, sessions 8 and 9: shoulders only a little back.
        for fc: Float in [-0.033, -0.046, -0.052, -0.053, -0.057, -0.078, -0.08, -0.083, -0.101] {
            XCTAssertFalse(PostureEngine.isReclined(forwardCreep: fc, headYawFromCalibration: 1, thresholds: t, headTurn: h), "\(fc)")
        }
        // Swivels move the shoulders back too, with the head turned.
        XCTAssertFalse(PostureEngine.isReclined(forwardCreep: -0.329, headYawFromCalibration: -72, thresholds: t, headTurn: h))
    }

    private func metrics(sink: Float = 0, headDrop: Float = 0, creep: Float = 0, lean: Float = 0,
                         at time: TimeInterval) -> RawMetrics {
        RawMetrics(timestamp: time, forwardCreep: creep, headDrop: headDrop, shoulderRounding: 0,
                   lateralLean: lean, twist: 0, movementLevel: 0, headMovementPattern: .still,
                   shoulderSink: sink)
    }

    private func state(_ m: RawMetrics, reclined: Bool) -> PostureState {
        let engine = PostureEngine()
        engine.update(metrics: metrics(at: 0), taskMode: .unknown, trackingQuality: .good)
        return engine.update(metrics: m, taskMode: .unknown, trackingQuality: .good, reclined: reclined)
    }

    func test_reclined_aSinkAndAHeadDrop_areNotASlouch() {
        XCTAssertEqual(state(metrics(sink: 0.083, headDrop: -0.1, creep: -0.233, at: 1), reclined: true), .good)
    }

    func test_notReclined_theSameSinkIs() {
        guard case .drifting = state(metrics(sink: 0.083, creep: -0.06, at: 1), reclined: false) else {
            return XCTFail("a sink should drift")
        }
    }

    /// Leaning sideways while reclined is still a lean.
    func test_reclined_aSidewaysLeanStillCounts() {
        guard case .drifting = state(metrics(creep: -0.2, lean: 0.2, at: 1), reclined: true) else {
            return XCTFail("a lean should drift")
        }
    }

    // MARK: - Through the pipeline

    private func finalState(shoulderWidth: Float, shoulderY: Float, yaw: Float) async throws -> PostureState {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()   // shoulders at y 0, 0.2 wide
        try await provider.start()
        let samples = (0..<6).map { i in
            PoseSample(timestamp: 670_636 + Double(i) * 0.5, depthMode: .twoDOnly,
                       headPosition: SIMD3<Float>(0, 1.0, 0), shoulderMidpoint: SIMD3<Float>(0, shoulderY, 0),
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

    /// Shoulders 23% further back and 0.08 lower, facing the phone: leaning back.
    func test_pipeline_leaningBack_staysGood() async throws {
        let state = try await finalState(shoulderWidth: 0.154, shoulderY: 0.016, yaw: 0)
        XCTAssertEqual(state, .good)
    }

    /// The same drop with the shoulders only a little back: sinking.
    func test_pipeline_sinking_drifts() async throws {
        let state = try await finalState(shoulderWidth: 0.19, shoulderY: 0.016, yaw: 0)
        guard case .drifting = state else { return XCTFail("a sink should drift, got \(state)") }
    }
}
