import XCTest
import Combine
@testable import PostureLogic

/// Sinking down in the chair counts as a slouch (2026-10-05).
///
/// Session 8: every sink read shoulder sink +0.086 to +0.103; every upright +0.005 to +0.020,
/// every swivel and head turn +0.018 or below. A line at +0.05 has 2.5 times the margin over
/// sitting upright.
final class SinkCountsTests: XCTestCase {

    private func metrics(sink: Float, creep: Float = 0, headDrop: Float = 0, at t: TimeInterval) -> RawMetrics {
        RawMetrics(timestamp: t, forwardCreep: creep, headDrop: headDrop, shoulderRounding: 0,
                   lateralLean: 0, twist: 0, movementLevel: 0, headMovementPattern: .still,
                   shoulderSink: sink)
    }

    private func state(sink: Float) -> PostureState {
        let engine = PostureEngine()
        engine.update(metrics: metrics(sink: 0, at: 0), taskMode: .reading, trackingQuality: .good)
        return engine.update(metrics: metrics(sink: sink, at: 1), taskMode: .reading, trackingQuality: .good)
    }

    func test_theLine_isPlus0_05() {
        XCTAssertEqual(PostureThresholds().shoulderSinkThreshold, 0.05)
    }

    func test_aSink_isASlouch() {
        for sink: Float in [0.086, 0.096, 0.103] {
            guard case .drifting = state(sink: sink) else { return XCTFail("\(sink) should drift") }
        }
    }

    func test_sittingUpright_isNot() {
        for sink: Float in [0.005, 0.020, -0.011] {
            XCTAssertEqual(state(sink: sink), .good, "\(sink)")
        }
    }

    // MARK: - The nudge

    func test_aSink_isTheNudgesReason_whenItDominates() {
        var thresholds = PostureThresholds()
        thresholds.slouchDurationBeforeNudge = 0
        let engine = NudgeEngine(thresholds: thresholds)
        let decision = engine.evaluate(state: .bad(since: 0), trackingQuality: .good, movementLevel: 0,
                                       taskMode: .unknown, currentTime: 1,
                                       metrics: metrics(sink: 0.1, creep: -0.05, headDrop: 0.002, at: 1),
                                       headTurnedSince: nil, silenced: false)
        guard case .fire(let reason) = decision else { return XCTFail("expected a nudge") }
        XCTAssertEqual(reason, .sink)
        XCTAssertEqual(NudgeReason.sink.rawValue, "sink")
        XCTAssertTrue(NudgeReason.sink.coachingMessage.contains("slide back"))
    }

    /// Leaning in still names its own reason when it dominates.
    func test_leaningIn_stillDominates_whenItIsTheBigger() {
        var thresholds = PostureThresholds()
        thresholds.slouchDurationBeforeNudge = 0
        let engine = NudgeEngine(thresholds: thresholds)
        let decision = engine.evaluate(state: .bad(since: 0), trackingQuality: .good, movementLevel: 0,
                                       taskMode: .unknown, currentTime: 1,
                                       metrics: metrics(sink: 0.08, creep: 0.13, headDrop: -0.01, at: 1),
                                       headTurnedSince: nil, silenced: false)
        guard case .fire(let reason) = decision else { return XCTFail("expected a nudge") }
        XCTAssertEqual(reason, .forwardCreep)
    }

    // MARK: - Stored limits stay readable

    /// The limits are saved with every Jev record. A record saved before a limit existed must
    /// still read, with the new limit at its default and the others as saved.
    func test_limitsSavedBeforeANewOne_stillRead() throws {
        var older = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PostureThresholds()))
            as? [String: Any])
        older.removeValue(forKey: "shoulderSinkThreshold")
        older["forwardCreepThreshold"] = 0.04
        let decoded = try JSONDecoder().decode(PostureThresholds.self,
                                               from: JSONSerialization.data(withJSONObject: older))
        XCTAssertEqual(decoded.shoulderSinkThreshold, 0.05)
        XCTAssertEqual(decoded.forwardCreepThreshold, 0.04, accuracy: 1e-6)
    }

    // MARK: - Through the pipeline

    func test_pipeline_shouldersLowerInTheFrame_drift() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()   // shoulders at y 0, 0.2 wide
        try await provider.start()
        let samples = (0..<6).map { i in
            PoseSample(timestamp: 670_636 + Double(i) * 0.5, depthMode: .twoDOnly,
                       headPosition: SIMD3<Float>(0, 1.0, 0), shoulderMidpoint: SIMD3<Float>(0, 0.02, 0),
                       leftShoulder: SIMD3<Float>(-0.5, 0, 0), rightShoulder: SIMD3<Float>(0.5, 0, 0),
                       torsoAngle: 5, headForwardOffset: 0.01, shoulderTwist: 2,
                       shoulderWidthRaw: 0.2, trackingQuality: .good)
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
        guard case .drifting = pipeline.postureState else {
            return XCTFail("sinking 0.1 shoulder widths should drift, got \(pipeline.postureState)")
        }
    }
}
