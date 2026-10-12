import XCTest
@testable import PostureLogic

/// A head-turn nudge waits out its cooldown while the head stays turned (2026-10-11).
///
/// Sitting well for 30 s ends a slouch, and with it the cooldown after a slouch nudge
/// (2026-10-08). It also ended the cooldown after a head-turn nudge, though a head held turned
/// isn't corrected by sitting well: the code review's probe, with default settings and the head
/// turned to a second screen for 20 minutes, nudged 31 times, every 30 s from minute five. Now
/// only the head turning back ends a head-turn nudge's cooldown.
final class HeadTurnCooldownTests: XCTestCase {

    private func run(_ e: NudgeEngine, from start: TimeInterval, to end: TimeInterval,
                     turnedSince: (TimeInterval) -> TimeInterval?, state: PostureState = .good,
                     fires: inout [TimeInterval]) {
        for t in stride(from: start, to: end, by: 1) {
            let d = e.evaluate(state: state, trackingQuality: .good, movementLevel: 0.1, taskMode: .unknown,
                               currentTime: t, metrics: nil, headTurnedSince: turnedSince(t), silenced: false)
            if case .fire = d { fires.append(t); e.recordNudgeFired(at: t) }
        }
    }

    /// The probe: twenty minutes turned, sitting well. Once at five minutes, again after the
    /// ten-minute cooldown.
    func test_aHeadHeldTurned_isNudgedOncePerCooldown_notEvery30Seconds() {
        let e = NudgeEngine()
        var fires: [TimeInterval] = []
        run(e, from: 0, to: 1201, turnedSince: { _ in 0 }, fires: &fires)
        XCTAssertEqual(fires, [300, 901])
    }

    /// Turning back ends it: the next turn gets its own five minutes.
    func test_turningBack_endsTheCooldown() {
        let e = NudgeEngine()
        var fires: [TimeInterval] = []
        run(e, from: 0, to: 320, turnedSince: { _ in 0 }, fires: &fires)
        run(e, from: 320, to: 330, turnedSince: { _ in nil }, fires: &fires)
        run(e, from: 330, to: 640, turnedSince: { _ in 330 }, fires: &fires)
        XCTAssertEqual(fires, [300, 630])
    }

    /// A slouch nudge is still ended by sitting well, as before.
    func test_aSlouchNudge_isStillEndedBySittingWell() {
        var thresholds = PostureThresholds()
        thresholds.slouchDurationBeforeNudge = 60
        let e = NudgeEngine(thresholds: thresholds)
        var fires: [TimeInterval] = []
        run(e, from: 0, to: 61, turnedSince: { _ in nil }, state: .bad(since: 0), fires: &fires)
        run(e, from: 61, to: 95, turnedSince: { _ in nil }, fires: &fires)
        run(e, from: 95, to: 160, turnedSince: { _ in nil }, state: .drifting(since: 95), fires: &fires)
        XCTAssertEqual(fires, [60, 155])
    }
}
