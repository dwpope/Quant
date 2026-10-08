import XCTest
@testable import PostureLogic

/// What the cooldown after a nudge holds back, and when the panel says "suppressed" (2026-10-08).
///
/// In Dave's second real-use hour the 10-minute cooldown held back every slouch after a nudge,
/// even one that began after he'd sat up, and the panel said "suppressed" while he sat well.
/// He expects a slouch after sitting up to be nudged like any other. So the cooldown only holds
/// back a slouch he hasn't corrected, and "suppressed" means a nudge is being held back: with
/// nothing to nudge for, the decision is `.none`.
final class NudgeCooldownTests: XCTestCase {

    /// One-minute slouches, the 10-minute cooldown and 30 s of sitting well, set here so the
    /// tests don't move with the defaults.
    private func engine() -> NudgeEngine {
        var thresholds = PostureThresholds()
        thresholds.slouchDurationBeforeNudge = 60
        thresholds.nudgeCooldown = 600
        return NudgeEngine(thresholds: thresholds)
    }

    /// Feeds one frame a second; records each fire as the app does.
    @discardableResult
    private func run(_ e: NudgeEngine, from start: TimeInterval, seconds: Int, state: PostureState,
                     quality: TrackingQuality = .good, taskMode: TaskMode = .unknown,
                     fires: inout [TimeInterval]) -> NudgeDecision {
        var last = NudgeDecision.none
        for i in 0..<seconds {
            let t = start + TimeInterval(i)
            last = e.evaluate(state: state, trackingQuality: quality, movementLevel: 0, taskMode: taskMode,
                              currentTime: t, metrics: nil, headTurnedSince: nil, silenced: false)
            if case .fire = last { fires.append(t); e.recordNudgeFired(at: t) }
        }
        return last
    }

    /// Nudged, sat up for 30 s, slouched again: nudged after that slouch's own minute, well
    /// inside the 10 minutes.
    func test_sittingWellFor30Seconds_letsTheNextSlouchNudge_beforeTheCooldownEnds() {
        let e = engine(); var fires: [TimeInterval] = []
        run(e, from: 0, seconds: 61, state: .bad(since: 0), fires: &fires)
        XCTAssertEqual(fires, [60])
        run(e, from: 61, seconds: 30, state: .good, fires: &fires)
        run(e, from: 91, seconds: 70, state: .bad(since: 91), fires: &fires)
        XCTAssertEqual(fires.count, 2)
        XCTAssertEqual(fires.last ?? 0, 151, accuracy: 1.5, "a minute into the new slouch")
    }

    /// Walking away ends the slouch too: back at the desk and slouching, it's a new one.
    func test_leavingTheDesk_endsTheSlouch_too() {
        let e = engine(); var fires: [TimeInterval] = []
        run(e, from: 0, seconds: 61, state: .bad(since: 0), fires: &fires)
        run(e, from: 61, seconds: 40, state: .absent, quality: .lost, fires: &fires)
        run(e, from: 101, seconds: 70, state: .bad(since: 101), fires: &fires)
        XCTAssertEqual(fires.count, 2)
        XCTAssertEqual(fires.last ?? 0, 161, accuracy: 1.5)
    }

    /// A sit-up shorter than 30 s isn't a correction: the slouch carries on, and so does the wait.
    func test_aBriefSitUp_keepsTheCooldown() {
        let e = engine(); var fires: [TimeInterval] = []
        run(e, from: 0, seconds: 61, state: .bad(since: 0), fires: &fires)
        run(e, from: 61, seconds: 10, state: .good, fires: &fires)
        let decision = run(e, from: 71, seconds: 120, state: .bad(since: 71), fires: &fires)
        XCTAssertEqual(fires, [60])
        guard case .suppressed(.cooldownActive) = decision else { return XCTFail("got \(decision)") }
    }

    /// A slouch never corrected is nudged again once the cooldown ends.
    func test_anUncorrectedSlouch_isNudgedAgain_whenTheCooldownEnds() {
        let e = engine(); var fires: [TimeInterval] = []
        run(e, from: 0, seconds: 700, state: .bad(since: 0), fires: &fires)
        XCTAssertEqual(fires.count, 2)
        XCTAssertEqual(fires.last ?? 0, 661, accuracy: 1.5, "the first frame past the 10 minutes")
    }

    /// Sitting well during the cooldown has nothing to hold back.
    func test_sittingWell_duringTheCooldown_isNotSuppressed() {
        let e = engine(); var fires: [TimeInterval] = []
        run(e, from: 0, seconds: 61, state: .bad(since: 0), fires: &fires)
        let decision = run(e, from: 61, seconds: 5, state: .good, fires: &fires)
        guard case .none = decision else { return XCTFail("got \(decision)") }
    }

    /// Nobody in view: nothing to nudge for, so nothing suppressed.
    func test_nobodyInView_isNotSuppressed() {
        let e = engine(); var fires: [TimeInterval] = []
        let decision = run(e, from: 0, seconds: 5, state: .absent, quality: .lost, fires: &fires)
        guard case .none = decision else { return XCTFail("got \(decision)") }
    }

    /// Stretching with good posture: nothing held back either.
    func test_stretching_withGoodPosture_isNotSuppressed() {
        let e = engine(); var fires: [TimeInterval] = []
        let decision = run(e, from: 0, seconds: 5, state: .good, taskMode: .stretching, fires: &fires)
        guard case .none = decision else { return XCTFail("got \(decision)") }
    }

    /// A slouch the camera can't see clearly is still held back, and says so.
    func test_aSlouch_withoutAClearView_isStillSuppressed() {
        let e = engine(); var fires: [TimeInterval] = []
        let decision = run(e, from: 0, seconds: 5, state: .bad(since: 0), quality: .degraded, fires: &fires)
        guard case .suppressed(.lowTrackingQuality) = decision else { return XCTFail("got \(decision)") }
    }

    /// The panel's cooldown readout ends when the correction does.
    func test_sittingWell_clearsTheCooldownReadout() {
        let e = engine(); var fires: [TimeInterval] = []
        run(e, from: 0, seconds: 61, state: .bad(since: 0), fires: &fires)
        run(e, from: 61, seconds: 31, state: .good, fires: &fires)
        XCTAssertEqual(e.debugState["cooldownRemaining"] as? TimeInterval, 0)
    }
}
