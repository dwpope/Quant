import XCTest
@testable import PostureLogic

/// How long until the next nudge, for the Watch's countdown, and which repeat a nudge is, for its
/// haptic (2026-10-13).
///
/// Dave asked for a countdown to the nudge on the Watch, and for the nudge to feel different from
/// a notification. The engine already knows both: the countdown is its pending time, or the
/// repeat's wait after a nudge; the repeat is how many times in a row the same slouch was nudged.
final class NudgeCountdownTests: XCTestCase {

    private func evaluate(_ e: NudgeEngine, _ state: PostureState, at t: TimeInterval,
                          turnedSince: TimeInterval? = nil, silenced: Bool = false,
                          taskMode: TaskMode = .unknown) -> NudgeDecision {
        e.evaluate(state: state, trackingQuality: .good, movementLevel: 0.1, taskMode: taskMode,
                   currentTime: t, metrics: nil, headTurnedSince: turnedSince, silenced: silenced)
    }

    /// Runs one frame a second, recording each fire as the app does.
    private func run(_ e: NudgeEngine, from start: TimeInterval, to end: TimeInterval,
                     state: (TimeInterval) -> PostureState, repeats: inout [Int]) {
        for t in stride(from: start, to: end, by: 1) {
            if case .fire = evaluate(e, state(t), at: t) {
                repeats.append(e.repeatOfLastFire)
                e.recordNudgeFired(at: t)
            }
        }
    }

    // MARK: - The countdown

    func test_sittingWell_hasNoCountdown() {
        let e = NudgeEngine()
        _ = evaluate(e, .good, at: 0)
        XCTAssertNil(e.nudgeDueIn)
    }

    func test_aSlouch_countsDownToItsNudge() {
        let e = NudgeEngine()
        for t in stride(from: 0.0, through: 20, by: 1) { _ = evaluate(e, .drifting(since: 0), at: t) }
        XCTAssertEqual(try XCTUnwrap(e.nudgeDueIn), 40, accuracy: 0.001)
    }

    /// After a nudge, still slouched: the cooldown holds the decision back, and the countdown is
    /// to the repeat.
    func test_afterANudge_countsDownToTheRepeat() {
        let e = NudgeEngine()
        var repeats: [Int] = []
        run(e, from: 0, to: 61, state: { _ in .bad(since: 0) }, repeats: &repeats)
        run(e, from: 61, to: 81, state: { _ in .bad(since: 0) }, repeats: &repeats)
        XCTAssertEqual(try XCTUnwrap(e.nudgeDueIn), 40, accuracy: 1)
    }

    /// A head held turned counts down to its own nudge.
    func test_aHeadTurn_countsDownToItsNudge() {
        let e = NudgeEngine()
        _ = evaluate(e, .good, at: 100, turnedSince: 0)
        XCTAssertEqual(try XCTUnwrap(e.nudgeDueIn), 200, accuracy: 0.001)
    }

    /// Silenced, or stretching, nothing is coming.
    func test_silencedOrStretching_hasNoCountdown() {
        let e = NudgeEngine()
        _ = evaluate(e, .drifting(since: 0), at: 10, silenced: true)
        XCTAssertNil(e.nudgeDueIn)
        _ = evaluate(e, .drifting(since: 0), at: 11, taskMode: .stretching)
        XCTAssertNil(e.nudgeDueIn)
    }

    // MARK: - Which repeat

    func test_theFirstNudge_isRepeatZero_andEachRepeatCounts() {
        let e = NudgeEngine()
        var repeats: [Int] = []
        run(e, from: 0, to: 250, state: { _ in .bad(since: 0) }, repeats: &repeats)
        XCTAssertEqual(repeats, [0, 1, 2, 3])
    }

    /// Sitting well for 30 s ends the slouch: the next one's first nudge is repeat zero again.
    func test_sittingUp_startsTheCountAgain() {
        let e = NudgeEngine()
        var repeats: [Int] = []
        run(e, from: 0, to: 125, state: { _ in .bad(since: 0) }, repeats: &repeats)
        run(e, from: 125, to: 160, state: { _ in .good }, repeats: &repeats)
        run(e, from: 160, to: 225, state: { _ in .drifting(since: 160) }, repeats: &repeats)
        XCTAssertEqual(repeats, [0, 1, 0])
    }

    // MARK: - Through the pipeline

    /// While slouching, the pipeline says when the nudge is due on the frame clock, and the
    /// nudge it fires says which repeat it is, read before it's recorded as the app does.
    func test_thePipeline_publishesWhenTheNudgeIsDue_andWhichRepeat() async throws {
        var t = PostureThresholds()
        t.driftingToBadThreshold = 1
        t.slouchDurationBeforeNudge = 4
        t.nudgeCooldown = 3
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider, thresholds: t)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        try await provider.start()

        var dueAts: [TimeInterval?] = []
        var repeats: [Int] = []
        let subscription = pipeline.$nudgeDecision.sink { decision in
            dueAts.append(pipeline.nudgeDueAt)
            guard case .fire = decision else { return }
            repeats.append(pipeline.nudgeRepeat)
            pipeline.recordNudgeFired()
        }
        let start: TimeInterval = 1_791_640_000
        for i in 0..<24 {
            let sample = PoseSample(
                timestamp: start + Double(i) * 0.5, depthMode: .twoDOnly,
                headPosition: SIMD3<Float>(0, 0.85, 0), shoulderMidpoint: SIMD3<Float>(0, 0, 0),
                leftShoulder: SIMD3<Float>(-0.5, 0, 0), rightShoulder: SIMD3<Float>(0.5, 0, 0),
                torsoAngle: 20, headForwardOffset: 0.08, shoulderTwist: 20, shoulderWidthRaw: 0.24,
                trackingQuality: .good)
            provider.emit(frame: InputFrame(timestamp: sample.timestamp, pixelBuffer: nil, depthMap: nil,
                                            cameraIntrinsics: nil, precomputedSample: sample))
        }
        await pipeline.settled()
        subscription.cancel()

        XCTAssertEqual(repeats, [0, 1, 2], "a nudge, then a repeat every 3 s of slouching")
        let due = dueAts.compactMap { $0 }
        XCTAssertFalse(due.isEmpty, "a slouch counts down")
        XCTAssertTrue(due.allSatisfy { $0 >= start && $0 < start + 20 }, "on the frame clock")
    }
}
