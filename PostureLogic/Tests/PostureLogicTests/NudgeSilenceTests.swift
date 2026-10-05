import XCTest
import Combine
@testable import PostureLogic

/// Silencing nudges for a while, and no hourly cap (Dave, 2026-10-05).
///
/// "Don't worry about limiting the number of nudges in an hour yet. Give the ability to silence
/// the nudges for a period of time on the watch and app." The gap between nudges stays; the
/// hourly cap is off unless set; and a silence holds back every nudge, slouch or head turn.
final class NudgeSilenceTests: XCTestCase {

    private func engine(maxPerHour: Int = 0) -> NudgeEngine {
        var thresholds = PostureThresholds()
        thresholds.slouchDurationBeforeNudge = 10
        thresholds.nudgeCooldown = 5
        thresholds.maxNudgesPerHour = maxPerHour
        var headTurn = HeadTurnThresholds()
        headTurn.durationBeforeNudge = 10
        return NudgeEngine(thresholds: thresholds, headTurnThresholds: headTurn)
    }

    private func evaluate(_ engine: NudgeEngine, _ state: PostureState, at time: TimeInterval,
                          headTurnedSince: TimeInterval? = nil, silenced: Bool = false) -> NudgeDecision {
        engine.evaluate(state: state, trackingQuality: .good, movementLevel: 0.1, taskMode: .unknown,
                        currentTime: time, metrics: nil, headTurnedSince: headTurnedSince,
                        silenced: silenced)
    }

    // MARK: - No hourly cap

    func test_byDefault_thereIsNoHourlyCap() {
        XCTAssertEqual(PostureThresholds().maxNudgesPerHour, 0, "0 means no cap")
    }

    /// Without a cap, the gap between nudges is the only limit: six in a minute here.
    func test_withNoCap_everySlouchAfterTheGapIsNudged() {
        let e = engine(maxPerHour: 0)
        var fired = 0
        for t in stride(from: 10.0, through: 70, by: 1) {
            if case .fire = evaluate(e, .bad(since: 0), at: t) {
                fired += 1
                e.recordNudgeFired(at: t)
            }
        }
        XCTAssertGreaterThanOrEqual(fired, 6)
    }

    func test_aCapStillApplies_whenSet() {
        let e = engine(maxPerHour: 1)
        e.recordNudgeFired(at: 10)
        guard case .suppressed(.maxNudgesReached) = evaluate(e, .bad(since: 0), at: 30) else {
            return XCTFail("expected the cap")
        }
    }

    // MARK: - Silenced

    func test_silenced_holdsBackASlouchNudge() {
        guard case .suppressed(.silenced) = evaluate(engine(), .bad(since: 0), at: 30, silenced: true) else {
            return XCTFail("expected silence")
        }
    }

    func test_silenced_holdsBackAHeadTurnNudge() {
        guard case .suppressed(.silenced) = evaluate(engine(), .good, at: 30, headTurnedSince: 0,
                                                    silenced: true) else {
            return XCTFail("expected silence")
        }
    }

    /// When the silence ends, a slouch still going is nudged straight away.
    func test_afterTheSilence_aSlouchStillGoingIsNudged() {
        let e = engine()
        _ = evaluate(e, .bad(since: 0), at: 30, silenced: true)
        guard case .fire = evaluate(e, .bad(since: 0), at: 31) else {
            return XCTFail("expected a nudge once the silence is over")
        }
    }

    func test_silencedReason_isStable() {
        XCTAssertEqual(SuppressionReason.silenced.rawValue, "silenced")
    }

    // MARK: - Through the pipeline, on the wall clock the app sets it with

    private func slouchSamples(count: Int) -> [PoseSample] {
        (0..<count).map { i in
            PoseSample(
                timestamp: 670_636 + Double(i) * 0.5, depthMode: .twoDOnly,
                headPosition: SIMD3<Float>(0, 0.85, 0), shoulderMidpoint: SIMD3<Float>(0, 0, 0),
                leftShoulder: SIMD3<Float>(-0.5, 0, 0), rightShoulder: SIMD3<Float>(0.5, 0, 0),
                torsoAngle: 20, headForwardOffset: 0.08, shoulderTwist: 20,
                shoulderWidthRaw: 0.24, trackingQuality: .good)
        }
    }

    private func fires(silencedUntil: Date?) async throws -> Int {
        let provider = MockPoseProvider()
        var t = PostureThresholds()
        t.driftingToBadThreshold = 1
        t.slouchDurationBeforeNudge = 2
        t.nudgeCooldown = 5
        let pipeline = Pipeline(provider: provider, thresholds: t)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        pipeline.nudgesSilencedUntil = silencedUntil
        try await provider.start()

        var count = 0
        let samples = slouchSamples(count: 20)
        let done = XCTestExpectation(description: "every frame processed")
        let fires = pipeline.$nudgeDecision.sink { decision in
            if case .fire = decision { count += 1; pipeline.recordNudgeFired() }
        }
        let frames = pipeline.$latestMetrics.sink { metrics in
            if let ts = metrics?.timestamp, ts >= samples.last!.timestamp { done.fulfill() }
        }
        for sample in samples {
            provider.emit(frame: InputFrame(timestamp: sample.timestamp, pixelBuffer: nil, depthMap: nil,
                                            cameraIntrinsics: nil, precomputedSample: sample))
        }
        await fulfillment(of: [done], timeout: 5)
        fires.cancel(); frames.cancel()
        return count
    }

    func test_pipeline_silencedUntilLater_nudgesNothing() async throws {
        let count = try await fires(silencedUntil: Date().addingTimeInterval(3600))
        XCTAssertEqual(count, 0)
    }

    func test_pipeline_aSilenceThatHasEnded_nudgesAsUsual() async throws {
        let count = try await fires(silencedUntil: Date().addingTimeInterval(-60))
        XCTAssertGreaterThan(count, 0)
    }
}
