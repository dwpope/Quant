import XCTest
@testable import PostureLogic

/// Slouch, get nudged, sit up, slouch again: you get nudged again.
///
/// Sitting up within 30 s of a nudge used to mark it acknowledged and suppress slouch nudges.
/// Nothing ever cleared the mark, so one corrected nudge silenced slouch nudges until the app was
/// quit (found 2026-10-05). Dave's expectation is simpler: a slouch after correcting is timed like
/// any other and nudged when it's held long enough. The acknowledgement is still recorded (did
/// the nudge work?), but it no longer holds anything back. The gap between nudges and the hourly
/// cap still apply.
final class NudgeEngineAcknowledgementTests: XCTestCase {

    /// Bad for 10 s to nudge, and room for several nudges an hour.
    private func engine(cooldown: TimeInterval = 5) -> NudgeEngine {
        var thresholds = PostureThresholds()
        thresholds.slouchDurationBeforeNudge = 10
        thresholds.nudgeCooldown = cooldown
        thresholds.maxNudgesPerHour = 10
        return NudgeEngine(thresholds: thresholds)
    }

    private func evaluate(_ engine: NudgeEngine, _ state: PostureState, at time: TimeInterval) -> NudgeDecision {
        engine.evaluate(state: state, trackingQuality: .good, movementLevel: 0.1, taskMode: .unknown,
                        currentTime: time, metrics: nil, headTurnedSince: nil)
    }

    /// A nudge at 15, and sitting up at 20, acknowledged.
    private func nudgedAndCorrected(cooldown: TimeInterval = 5) -> NudgeEngine {
        let e = engine(cooldown: cooldown)
        _ = evaluate(e, .bad(since: 0), at: 15)
        e.recordNudgeFired(at: 15)
        e.recordAcknowledgement()
        _ = evaluate(e, .good, at: 20)
        return e
    }

    func test_slouchCorrectSlouchAgain_isNudgedAgain() {
        let e = nudgedAndCorrected()
        guard case .fire = evaluate(e, .bad(since: 30), at: 40) else {
            return XCTFail("the second slouch should be nudged")
        }
    }

    /// Even straight after sitting up: a re-slump held long enough is a slouch.
    func test_aQuickReSlump_heldLongEnough_isNudged() {
        let e = nudgedAndCorrected()
        guard case .fire = evaluate(e, .bad(since: 22), at: 32) else {
            return XCTFail("a held re-slump should be nudged")
        }
    }

    /// The second slouch is timed from its own start, not from the first.
    func test_theSecondSlouch_isTimedFromItsOwnStart() {
        let e = nudgedAndCorrected()
        guard case .pending(_, let remaining) = evaluate(e, .bad(since: 30), at: 34) else {
            return XCTFail("expected pending")
        }
        XCTAssertEqual(remaining, 6, accuracy: 0.001)
    }

    /// The gap between nudges still holds: the second waits for it, then comes.
    func test_theGapBetweenNudges_stillApplies() {
        let e = nudgedAndCorrected(cooldown: 30)
        guard case .suppressed(.cooldownActive) = evaluate(e, .bad(since: 22), at: 40) else {
            return XCTFail("expected the cooldown")
        }
        guard case .fire = evaluate(e, .bad(since: 22), at: 46) else {
            return XCTFail("the second slouch should be nudged once the gap is over")
        }
    }

    /// Still recorded, for whether nudges work.
    func test_theAcknowledgement_isStillRecorded() {
        let e = nudgedAndCorrected()
        XCTAssertEqual(e.debugState["acknowledged"] as? Bool, true)
    }
}
