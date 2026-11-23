import XCTest
import Combine
@testable import PostureLogic

/// The pipeline asks whether the seat has moved, holds nudges while the question is open, and
/// forgets the slouch time it held when the question closes.
final class PipelineSeatChangeTests: XCTestCase {

    private let start: TimeInterval = 1_791_640_000

    /// A sample at `t`. `neck` is the ear-based neck height; the baseline's is 0 and head drop is
    /// baseline minus sample, so +0.024 reads as a head drop of -0.024 (past the 0.01875 line,
    /// within 1.5 lines); `slouched` is a forward lean far past the line.
    private func sample(at t: TimeInterval, neck: Float = 0, slouched: Bool = false) -> PoseSample {
        PoseSample(
            timestamp: t, depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0, 1.0, 0), shoulderMidpoint: SIMD3<Float>(0, 0, 0),
            leftShoulder: SIMD3<Float>(-0.5, 0, 0), rightShoulder: SIMD3<Float>(0.5, 0, 0),
            torsoAngle: 5, headForwardOffset: 0.01, shoulderTwist: 2,
            shoulderWidthRaw: slouched ? 0.24 : 0.2, trackingQuality: .good, headYaw: 0,
            neckHeight: neck)
    }

    @MainActor
    private func makePipeline(mode: SeatChangeMode = .ask) -> Pipeline {
        let pipeline = Pipeline(provider: MockPoseProvider())
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        pipeline.seatChangeMode = mode
        return pipeline
    }

    /// Frames at 10 fps from `from` for `seconds`, returning the time after the last frame and
    /// every decision seen.
    @MainActor
    @discardableResult
    private func run(_ pipeline: Pipeline, from: TimeInterval, for seconds: TimeInterval,
                     neck: Float = 0, slouched: Bool = false,
                     decisions: ((NudgeDecision) -> Void)? = nil) -> TimeInterval {
        let frames = Int((seconds * 10).rounded())
        for i in 0..<frames {
            let t = from + Double(i) / 10
            pipeline.ingest(sample(at: t, neck: neck, slouched: slouched), quality: .good, at: t)
            decisions?(pipeline.nudgeDecision)
        }
        return from + Double(frames) / 10
    }

    /// Frames with nobody in view.
    @MainActor
    @discardableResult
    private func runAway(_ pipeline: Pipeline, from: TimeInterval, for seconds: TimeInterval) -> TimeInterval {
        let frames = Int((seconds * 10).rounded())
        for i in 0..<frames {
            pipeline.ingest(nil, quality: .lost, at: from + Double(i) / 10)
        }
        return from + Double(frames) / 10
    }

    /// Sitting well, then `count` brief head-drop near-misses (4 s past the line, 6 s well).
    /// Returns the time after the last frame.
    @MainActor
    @discardableResult
    private func nearMisses(_ pipeline: Pipeline, count: Int = 5, from: TimeInterval) -> TimeInterval {
        var t = run(pipeline, from: from, for: 3)
        for _ in 0..<count {
            t = run(pipeline, from: t, for: 4, neck: 0.024)
            t = run(pipeline, from: t, for: 6)
        }
        return t
    }

    // MARK: - Tests

    /// The frame a sustained slouch first fires on, after five near-misses (their slouched seconds
    /// count toward the nudge, so the time is compared between modes, not against 60 s).
    @MainActor
    private func firstFire(mode: SeatChangeMode) -> (Pipeline, TimeInterval?) {
        let pipeline = makePipeline(mode: mode)
        let slouchFrom = nearMisses(pipeline, from: start)
        for i in 0..<900 {
            let t = slouchFrom + Double(i) / 10
            pipeline.ingest(sample(at: t, slouched: true), quality: .good, at: t)
            if case .fire = pipeline.nudgeDecision { return (pipeline, t - slouchFrom) }
        }
        return (pipeline, nil)
    }

    @MainActor
    func test_logOnly_publishesSuggestion_butNoQuestion_andNudgesUnchanged() throws {
        XCTAssertEqual(Pipeline(provider: MockPoseProvider()).seatChangeMode, .logOnly, "the default")
        let (logOnly, loggedFire) = firstFire(mode: .logOnly)
        let (off, offFire) = firstFire(mode: .off)
        XCTAssertNotNil(logOnly.seatChangeSuggestion)
        XCTAssertNil(logOnly.seatChangeQuestion)
        XCTAssertNil(off.seatChangeSuggestion)
        XCTAssertEqual(try XCTUnwrap(loggedFire), try XCTUnwrap(offFire), accuracy: 0.001,
                       "fires when it would without the seat-change check")
    }

    @MainActor
    func test_logOnly_countsEveryBurst() {
        let pipeline = makePipeline(mode: .logOnly)
        var t = nearMisses(pipeline, from: start)
        let first = pipeline.seatChangeSuggestion
        XCTAssertNotNil(first)
        t = nearMisses(pipeline, from: t)
        XCTAssertNotEqual(pipeline.seatChangeSuggestion, first, "a second burst is suggested again")
    }

    @MainActor
    func test_ask_opensQuestion_andHoldsNudges() {
        let pipeline = makePipeline()
        var t = nearMisses(pipeline, from: start)
        XCTAssertNotNil(pipeline.seatChangeQuestion)
        var fires = 0
        t = run(pipeline, from: t, for: 90, slouched: true) { decision in
            if case .fire = decision { fires += 1 }
        }
        XCTAssertEqual(fires, 0)
        XCTAssertNotNil(pipeline.seatChangeQuestion, "still open at 90 s")
    }

    @MainActor
    func test_question_timesOutAfter120s() throws {
        let pipeline = makePipeline()
        _ = nearMisses(pipeline, from: start)
        let opened = try XCTUnwrap(pipeline.seatChangeQuestion).suggestion.at
        // Frames resume from the first one after the question opened.
        var t = opened + 0.1
        while t < opened + 119.95 {
            pipeline.ingest(sample(at: t), quality: .good, at: t)
            t += 0.1
        }
        XCTAssertNil(pipeline.seatChangeClosed)
        XCTAssertNotNil(pipeline.seatChangeQuestion)
        while t < opened + 120.15 {
            pipeline.ingest(sample(at: t), quality: .good, at: t)
            t += 0.1
        }
        XCTAssertEqual(pipeline.seatChangeClosed, .timeout)
        XCTAssertNil(pipeline.seatChangeQuestion)
    }

    @MainActor
    func test_closing_forgetsSlouchTime() {
        let pipeline = makePipeline()
        var t = nearMisses(pipeline, from: start)
        t = run(pipeline, from: t, for: 90, slouched: true)
        pipeline.answerSeatChange(.dismiss)
        XCTAssertEqual(pipeline.seatChangeClosed, .dismiss)
        XCTAssertNil(pipeline.seatChangeQuestion)
        var fires = 0
        let limit = PostureThresholds().slouchDurationBeforeNudge - 1
        t = run(pipeline, from: t, for: limit, slouched: true) { decision in
            if case .fire = decision { fires += 1 }
        }
        XCTAssertEqual(fires, 0, "the 90 s held back is forgotten")
    }

    @MainActor
    func test_away_closesQuestion() {
        let pipeline = makePipeline()
        let t = nearMisses(pipeline, from: start)
        XCTAssertNotNil(pipeline.seatChangeQuestion)
        runAway(pipeline, from: t, for: 3)
        XCTAssertEqual(pipeline.postureState, .absent)
        XCTAssertEqual(pipeline.seatChangeClosed, .away)
        XCTAssertNil(pipeline.seatChangeQuestion)
    }

    @MainActor
    func test_recalibrating_closesQuestion_andResetsDetector() {
        let pipeline = makePipeline()
        var t = nearMisses(pipeline, from: start)
        XCTAssertNotNil(pipeline.seatChangeQuestion)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        XCTAssertEqual(pipeline.seatChangeClosed, .recalibrate)
        XCTAssertNil(pipeline.seatChangeQuestion)

        // Four near-misses don't make five: the count started again.
        let before = pipeline.seatChangeSuggestion
        t = nearMisses(pipeline, count: 4, from: t)
        XCTAssertNil(pipeline.seatChangeQuestion)
        XCTAssertEqual(pipeline.seatChangeSuggestion, before, "no new suggestion")
        // A fifth does: the detector listens again after the new baseline.
        t = run(pipeline, from: t, for: 4, neck: 0.024)
        t = run(pipeline, from: t, for: 6)
        XCTAssertNotNil(pipeline.seatChangeQuestion)
    }

    @MainActor
    func test_switchingModeOff_closesOpenQuestion() {
        let pipeline = makePipeline()
        var t = nearMisses(pipeline, from: start)
        XCTAssertNotNil(pipeline.seatChangeQuestion)
        pipeline.seatChangeMode = .off
        XCTAssertEqual(pipeline.seatChangeClosed, .modeChanged)
        XCTAssertNil(pipeline.seatChangeQuestion)
        var fires = 0
        t = run(pipeline, from: t, for: 90, slouched: true) { decision in
            if case .fire = decision { fires += 1 }
        }
        XCTAssertGreaterThan(fires, 0, "nudges are no longer held")
    }

    @MainActor
    func test_newTimeline_closesQuestion_asNewTimeline() {
        let pipeline = makePipeline()
        _ = nearMisses(pipeline, from: start)
        XCTAssertNotNil(pipeline.seatChangeQuestion)
        pipeline.resetTimeline()
        XCTAssertEqual(pipeline.seatChangeClosed, .newTimeline)
        XCTAssertNil(pipeline.seatChangeQuestion)
    }

    @MainActor
    func test_askToLogOnly_withOpenQuestion_keepsCounting() {
        let pipeline = makePipeline()
        let t = nearMisses(pipeline, from: start)
        let first = pipeline.seatChangeSuggestion
        XCTAssertNotNil(pipeline.seatChangeQuestion)
        pipeline.seatChangeMode = .logOnly
        XCTAssertEqual(pipeline.seatChangeClosed, .modeChanged)
        _ = nearMisses(pipeline, from: t)
        XCTAssertNotNil(pipeline.seatChangeSuggestion)
        XCTAssertNotEqual(pipeline.seatChangeSuggestion, first, "a new suggestion after the switch")
        XCTAssertNil(pipeline.seatChangeQuestion)
    }

    @MainActor
    func test_off_neverSuggests() {
        let pipeline = makePipeline(mode: .off)
        _ = nearMisses(pipeline, count: 8, from: start)
        XCTAssertNil(pipeline.seatChangeSuggestion)
        XCTAssertNil(pipeline.seatChangeQuestion)
        XCTAssertNil(pipeline.seatChangeClosed)
    }

    @MainActor
    func test_answer_withNoOpenQuestion_isIgnored() {
        let pipeline = makePipeline()
        pipeline.answerSeatChange(.dismiss)
        pipeline.answerSeatChange(.recalibrate)
        XCTAssertNil(pipeline.seatChangeClosed)
        XCTAssertNil(pipeline.seatChangeQuestion)
    }

    @MainActor
    func test_suggestionWhileQuestionOpen_isIgnored() {
        let pipeline = makePipeline()
        let t = nearMisses(pipeline, from: start)
        let open = pipeline.seatChangeQuestion
        XCTAssertNotNil(open)
        // A second burst while the question is open must not replace it.
        nearMisses(pipeline, from: t)
        XCTAssertEqual(pipeline.seatChangeQuestion, open)
        XCTAssertEqual(pipeline.seatChangeSuggestion, open?.suggestion)
    }
}
