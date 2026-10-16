import XCTest
@testable import PostureLogic

/// Sitting up is not slouching, even before the posture engine has called it good (2026-10-16).
///
/// The posture engine holds `.bad` for `recoveryGracePeriod` (5 s) after sitting up, so a brief
/// sit-up doesn't flicker the state. The nudge engine took those seconds for slouching, so a
/// repeat could fire up to 5 s after Dave had sat up. The one-minute repeat (2026-10-12) made
/// that about ten times likelier. Found by the 2026-10-16 audit.
final class SittingUpAfterANudgeTests: XCTestCase {

    private func sample(at t: TimeInterval, slouched: Bool) -> PoseSample {
        PoseSample(
            timestamp: t, depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0, 1.0, 0), shoulderMidpoint: SIMD3<Float>(0, 0, 0),
            leftShoulder: SIMD3<Float>(-0.5, 0, 0), rightShoulder: SIMD3<Float>(0.5, 0, 0),
            torsoAngle: 5, headForwardOffset: 0.01, shoulderTwist: 2,
            shoulderWidthRaw: slouched ? 0.24 : 0.2, trackingQuality: .good, headYaw: 0)
    }

    /// Slouched for the first nudge and most of the minute to its repeat, then sitting up 4 s
    /// before the repeat was due: no repeat.
    @MainActor
    func test_sittingUpJustBeforeTheRepeat_isNotNudged() {
        let pipeline = Pipeline(provider: MockPoseProvider())
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        let start: TimeInterval = 1_791_640_000
        var fires: [TimeInterval] = []
        let watch = pipeline.$nudgeDecision.sink { decision in
            guard case .fire = decision, let t = pipeline.latestMetrics?.timestamp else { return }
            fires.append(t - start)
            pipeline.recordNudgeFired()
        }
        for i in 0..<1600 {
            let t = start + Double(i) * 0.1
            pipeline.ingest(sample(at: t, slouched: t - start < 116), quality: .good, at: t)
        }
        watch.cancel()

        XCTAssertEqual(fires.count, 1, "the first nudge only, got \(fires)")
        XCTAssertEqual(fires.first ?? 0, 60, accuracy: 1)
    }

    /// The same in the nudge engine: frames still `.bad` while the sit-up is being confirmed
    /// count towards sitting well, not slouching.
    func test_aConfirmingSitUp_countsAsSittingWell() {
        let e = NudgeEngine()
        var fires: [TimeInterval] = []
        for t in stride(from: 0.0, to: 160, by: 1) {
            let recovering = t >= 116 && t < 121
            let state: PostureState = t < 121 ? .bad(since: 0) : .good
            let d = e.evaluate(state: state, trackingQuality: .good, movementLevel: 0, taskMode: .unknown,
                               currentTime: t, recovering: recovering)
            if case .fire = d { fires.append(t); e.recordNudgeFired(at: t) }
            if recovering { XCTAssertNil(e.nudgeDueIn, "nothing coming while sitting up, at \(t)") }
        }
        XCTAssertEqual(fires, [60])
    }

    /// Sitting up, then a shoulder hidden: what can't be seen isn't taken for sitting well. The
    /// decision says tracking is too poor and the countdown stays (review of the fix).
    func test_aSitUpThatCantBeSeen_isLowTracking() {
        let e = NudgeEngine()
        for t in stride(from: 0.0, to: 30, by: 1) {
            _ = e.evaluate(state: .bad(since: 0), trackingQuality: .good, movementLevel: 0,
                           taskMode: .unknown, currentTime: t)
        }
        let d = e.evaluate(state: .bad(since: 0), trackingQuality: .degraded, movementLevel: 0,
                           taskMode: .unknown, currentTime: 30, recovering: true)
        guard case .suppressed(.lowTrackingQuality) = d else { return XCTFail("got \(d)") }
        XCTAssertNotNil(e.nudgeDueIn)
    }
}
