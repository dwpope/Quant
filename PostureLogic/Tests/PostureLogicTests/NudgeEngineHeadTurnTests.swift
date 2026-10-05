import XCTest
@testable import PostureLogic

/// A head held turned gets its own nudge, with its own advice, sharing the slouch nudge's limits.
///
/// Dave turns to a second screen and it gets uncomfortable after about five minutes
/// (2026-10-04). It's not a slouch, and it can happen with one, so it's a second reason the same
/// engine can fire for: one cooldown and one hourly cap between them, so turning and slouching
/// together still means at most one nudge per cooldown.
final class NudgeEngineHeadTurnTests: XCTestCase {

    private func engine(slouchDuration: TimeInterval = 10, headTurnDuration: TimeInterval = 20,
                        cooldown: TimeInterval = 30, maxPerHour: Int = 5) -> NudgeEngine {
        var thresholds = PostureThresholds()
        thresholds.slouchDurationBeforeNudge = slouchDuration
        thresholds.nudgeCooldown = cooldown
        thresholds.maxNudgesPerHour = maxPerHour
        var headTurn = HeadTurnThresholds()
        headTurn.durationBeforeNudge = headTurnDuration
        return NudgeEngine(thresholds: thresholds, headTurnThresholds: headTurn)
    }

    private func evaluate(_ engine: NudgeEngine, state: PostureState = .good,
                          headTurnedSince: TimeInterval?, at time: TimeInterval,
                          taskMode: TaskMode = .unknown) -> NudgeDecision {
        engine.evaluate(state: state, trackingQuality: .good, movementLevel: 0.1, taskMode: taskMode,
                        currentTime: time, metrics: nil, headTurnedSince: headTurnedSince)
    }

    private func fired(_ decision: NudgeDecision) -> NudgeReason? {
        if case .fire(let reason) = decision { return reason }
        return nil
    }

    // MARK: - On its own

    func test_aHeadTurnedLongEnough_firesWithGoodPosture() {
        XCTAssertEqual(fired(evaluate(engine(), headTurnedSince: 0, at: 20)), .headTurned)
    }

    func test_aHeadTurnedNotYetLongEnough_isPending() {
        guard case .pending(let reason, let remaining) = evaluate(engine(), headTurnedSince: 0, at: 5) else {
            return XCTFail("expected pending")
        }
        XCTAssertEqual(reason, .headTurned)
        XCTAssertEqual(remaining, 15, accuracy: 0.001)
    }

    func test_noHeadTurnAndGoodPosture_isNothing() {
        guard case .none = evaluate(engine(), headTurnedSince: nil, at: 100) else {
            return XCTFail("expected none")
        }
    }

    /// The default is the five minutes Dave gave.
    func test_byDefault_firesAfterFiveMinutes() {
        let e = NudgeEngine()
        XCTAssertNil(fired(e.evaluate(state: .good, trackingQuality: .good, movementLevel: 0.1,
                                      taskMode: .unknown, currentTime: 299, metrics: nil,
                                      headTurnedSince: 0)))
        XCTAssertEqual(fired(e.evaluate(state: .good, trackingQuality: .good, movementLevel: 0.1,
                                        taskMode: .unknown, currentTime: 300, metrics: nil,
                                        headTurnedSince: 0)), .headTurned)
    }

    // MARK: - Sharing the slouch nudge's limits

    func test_sharesTheCooldown() {
        let e = engine()
        e.recordNudgeFired(at: 10)
        guard case .suppressed(.cooldownActive) = evaluate(e, headTurnedSince: 0, at: 25) else {
            return XCTFail("expected the cooldown")
        }
    }

    func test_sharesTheHourlyCap() {
        let e = engine(cooldown: 1, maxPerHour: 1)
        e.recordNudgeFired(at: 10)
        guard case .suppressed(.maxNudgesReached) = evaluate(e, headTurnedSince: 0, at: 40) else {
            return XCTFail("expected the hourly cap")
        }
    }

    func test_isQuietWhileStretching() {
        guard case .suppressed(.userStretching) = evaluate(engine(), headTurnedSince: 0, at: 100,
                                                           taskMode: .stretching) else {
            return XCTFail("expected stretching to suppress it")
        }
    }

    /// Correcting a slouch after its nudge quiets slouch nudges. It says nothing about the neck.
    func test_anAcknowledgedSlouchNudge_doesNotQuietAHeadTurn() {
        let e = engine(cooldown: 5)
        e.recordNudgeFired(at: 0)
        e.recordAcknowledgement()
        XCTAssertEqual(fired(evaluate(e, state: .bad(since: 10), headTurnedSince: 10, at: 40)), .headTurned)
    }

    // MARK: - Turned and slouching together

    /// A turned head reads the shoulders wider (6 of 8 head turns measured +0.06 to +0.16), which
    /// is what the slouch thresholds look for. While the head is turned, its nudge wins.
    func test_whenBothAreDue_theHeadTurnWins() {
        XCTAssertEqual(fired(evaluate(engine(), state: .bad(since: 0), headTurnedSince: 0, at: 30)), .headTurned)
    }

    func test_aSlouchDueBeforeTheHeadTurn_firesAsASlouch() {
        let reason = fired(evaluate(engine(), state: .bad(since: 0), headTurnedSince: 25, at: 30))
        XCTAssertEqual(reason, .sustainedSlouch)
    }

    func test_pending_reportsWhicheverIsSooner() {
        guard case .pending(let reason, let remaining) = evaluate(
            engine(slouchDuration: 10, headTurnDuration: 20), state: .bad(since: 0),
            headTurnedSince: -14, at: 2) else {
            return XCTFail("expected pending")
        }
        XCTAssertEqual(reason, .headTurned)
        XCTAssertEqual(remaining, 4, accuracy: 0.001)
    }

    // MARK: - What it says

    func test_theAdvice_isToTurnTheChair() {
        XCTAssertTrue(NudgeReason.headTurned.coachingMessage.contains("chair"))
        XCTAssertEqual(NudgeReason.headTurned.rawValue, "headTurned")
    }
}
