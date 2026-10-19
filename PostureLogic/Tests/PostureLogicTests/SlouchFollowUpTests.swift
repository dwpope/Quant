import XCTest
@testable import PostureLogic

/// A slouch left uncorrected after its nudge is nudged again every minute (2026-10-12).
///
/// In Dave's fourth real-use hour he stayed slouched, writing, for 80 s after a head-drop nudge
/// and heard nothing more: the cooldown held an uncorrected slouch back for 10 minutes. He asked
/// for faster nudges after the first, and chose a repeat every 60 s until he sits up. Sitting
/// well for 30 s still ends it, and a head held turned still repeats only every 10 minutes.
final class SlouchFollowUpTests: XCTestCase {

    private func run(_ e: NudgeEngine, from start: TimeInterval, to end: TimeInterval,
                     state: (TimeInterval) -> PostureState, turnedSince: TimeInterval? = nil,
                     fires: inout [TimeInterval]) {
        for t in stride(from: start, to: end, by: 1) {
            let d = e.evaluate(state: state(t), trackingQuality: .good, movementLevel: 0.1, taskMode: .unknown,
                               currentTime: t, metrics: nil, headTurnedSince: turnedSince, silenced: false)
            if case .fire = d { fires.append(t); e.recordNudgeFired(at: t) }
        }
    }

    func test_theDefaultRepeat_isAMinute() {
        XCTAssertEqual(PostureThresholds().nudgeCooldown, 60)
    }

    /// The default settings, slouched throughout: the first nudge after a minute, then one a
    /// minute (the cooldown ends the second after it's run out).
    func test_stillSlouched_isNudgedAgainEveryMinute() {
        let e = NudgeEngine()
        var fires: [TimeInterval] = []
        run(e, from: 0, to: 250, state: { _ in .bad(since: 0) }, fires: &fires)
        XCTAssertEqual(fires, [60, 121, 182, 243])
    }

    /// The repeat follows its own setting, not the slouch duration: with five minutes to the
    /// first nudge, the next still comes a minute later.
    func test_theRepeat_doesNotWaitTheFirstNudgesDuration() {
        var t = PostureThresholds()
        t.slouchDurationBeforeNudge = 300
        let e = NudgeEngine(thresholds: t)
        var fires: [TimeInterval] = []
        run(e, from: 0, to: 370, state: { _ in .bad(since: 0) }, fires: &fires)
        XCTAssertEqual(fires, [300, 361])
    }

    /// Sitting well for 30 s ends the repeats; the next slouch waits its own full duration.
    func test_sittingUp_endsTheRepeats() {
        var t = PostureThresholds()
        t.slouchDurationBeforeNudge = 120
        let e = NudgeEngine(thresholds: t)
        var fires: [TimeInterval] = []
        run(e, from: 0, to: 121, state: { _ in .bad(since: 0) }, fires: &fires)
        run(e, from: 121, to: 160, state: { _ in .good }, fires: &fires)
        run(e, from: 160, to: 300, state: { _ in .drifting(since: 160) }, fires: &fires)
        XCTAssertEqual(fires, [120, 280])
    }

    /// A moment of sitting up (under 30 s) pauses the count; the repeat needs a minute of
    /// slouching since the nudge.
    func test_aBriefSitUp_pausesTheRepeat() {
        let e = NudgeEngine()
        var fires: [TimeInterval] = []
        run(e, from: 0, to: 61, state: { _ in .bad(since: 0) }, fires: &fires)
        run(e, from: 61, to: 71, state: { _ in .good }, fires: &fires)
        run(e, from: 71, to: 140, state: { _ in .drifting(since: 71) }, fires: &fires)
        XCTAssertEqual(fires, [60, 131])
    }

    /// The pending countdown after a nudge counts down the repeat.
    func test_afterANudge_pendingCountsDownTheRepeat() {
        var t = PostureThresholds()
        t.slouchDurationBeforeNudge = 300
        let e = NudgeEngine(thresholds: t)
        var fires: [TimeInterval] = []
        run(e, from: 0, to: 341, state: { _ in .bad(since: 0) }, fires: &fires)
        // The cooldown is still on at 340, so it reads suppressed; the readout shows the repeat.
        XCTAssertEqual(fires, [300])
        XCTAssertEqual(e.debugState["cooldownRemaining"] as? TimeInterval ?? -1, 20, accuracy: 1)
    }

    /// A break of over a minute between frames (the app paused, the camera stopped) ends the
    /// slouch's follow-up, as sitting well does (2026-10-16 audit): the next nudge waits its own
    /// full time and is a first, not a repeat. It used to come after the repeat's minute, with
    /// the repeat's firmer taps.
    func test_aBreak_endsTheFollowUp() {
        var t = PostureThresholds()
        t.slouchDurationBeforeNudge = 120
        let e = NudgeEngine(thresholds: t)
        var fires: [TimeInterval] = []
        run(e, from: 0, to: 121, state: { _ in .bad(since: 0) }, fires: &fires)
        // No frames from 121 to 300.
        run(e, from: 300, to: 430, state: { _ in .bad(since: 0) }, fires: &fires)
        XCTAssertEqual(fires, [120, 420])
        XCTAssertEqual(e.repeatOfLastFire, 0)
    }

    /// A head-turn nudge in the middle of a slouch's repeats leaves the slouch's follow-up alone
    /// (2026-10-16 audit): once the head turns back, the slouch still going on is nudged again
    /// after a minute, as the next repeat with one more tap. It used to start again as a first
    /// nudge: the first nudge's wait, and two taps.
    func test_aHeadTurnNudge_keepsTheSlouchsRepeats() {
        var t = PostureThresholds()
        t.slouchDurationBeforeNudge = 120
        let e = NudgeEngine(thresholds: t)
        var fires: [TimeInterval] = []
        var repeats: [Int] = []
        for now in stride(from: 0.0, to: 370, by: 1) {
            let turnedSince: TimeInterval? = now < 310 ? 0 : nil
            let d = e.evaluate(state: .bad(since: 0), trackingQuality: .good, movementLevel: 0.1,
                               taskMode: .unknown, currentTime: now, headTurnedSince: turnedSince)
            if case .fire = d {
                fires.append(now)
                repeats.append(e.repeatOfLastFire)
                e.recordNudgeFired(at: now)
            }
        }
        XCTAssertEqual(fires, [120, 181, 242, 303, 363], "slouch, two repeats, the head turn, the next repeat")
        XCTAssertEqual(repeats, [0, 1, 2, 0, 3])
    }

    /// Sitting well through a head-turn nudge still ends the slouch after 30 s (review of the
    /// fix above): the head-turn nudge restarted those 30 s, so a slouch begun 22 s after it,
    /// 45 s into sitting well, was taken for the old one and nudged as its repeat.
    func test_aHeadTurnNudge_doesNotRestartTheSitUp() {
        var t = PostureThresholds()
        t.slouchDurationBeforeNudge = 120
        let e = NudgeEngine(thresholds: t)
        var fires: [TimeInterval] = []
        var repeats: [Int] = []
        for now in stride(from: 0.0, to: 450, by: 1) {
            let turnedSince: TimeInterval? = now < 305 ? 0 : nil
            let state: PostureState = now < 280 ? .bad(since: 0) : now < 325 ? .good : .drifting(since: 325)
            let d = e.evaluate(state: state, trackingQuality: .good, movementLevel: 0.1,
                               taskMode: .unknown, currentTime: now, headTurnedSince: turnedSince)
            if case .fire = d {
                fires.append(now)
                repeats.append(e.repeatOfLastFire)
                e.recordNudgeFired(at: now)
            }
        }
        XCTAssertEqual(fires, [120, 181, 242, 303, 445], "the new slouch waits its own two minutes")
        XCTAssertEqual(repeats, [0, 1, 2, 0, 0])
    }

    /// A head held turned keeps its 10-minute repeat: the minute is for slouches.
    func test_aHeadHeldTurned_stillRepeatsEvery10Minutes() {
        XCTAssertEqual(HeadTurnThresholds().repeatAfter, 600)
        let e = NudgeEngine()
        var fires: [TimeInterval] = []
        run(e, from: 0, to: 1000, state: { _ in .good }, turnedSince: 0, fires: &fires)
        XCTAssertEqual(fires, [300, 901])
    }
}
