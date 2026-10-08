import XCTest
@testable import PostureLogic

/// How long a slouch takes to earn a nudge, in real use (2026-10-07).
///
/// Dave worked for an hour and got no nudge: it took 5 minutes of unbroken slouching, and almost
/// any movement restarted the count (one good frame while drifting, 5 s of good once bad).
/// Reaching for the mouse or shifting in the seat was enough. Now slouched time adds up: brief
/// sit-ups pause it, sitting well for 30 s ends the episode, and 2 minutes of it earns a nudge.
final class SlouchTimeTests: XCTestCase {

    /// The 2-minute setting these were written for; the default is now 1 minute (2026-10-08).
    private func engine() -> NudgeEngine {
        var thresholds = PostureThresholds()
        thresholds.slouchDurationBeforeNudge = 120
        return NudgeEngine(thresholds: thresholds)
    }

    /// Feeds one frame a second; returns the times a nudge fired (each recorded, as the app does).
    @discardableResult
    private func run(_ e: NudgeEngine, from start: TimeInterval, seconds: Int, slouched: Bool,
                     quality: TrackingQuality = .good, fires: inout [TimeInterval]) -> NudgeDecision {
        var last = NudgeDecision.none
        for i in 0..<seconds {
            let t = start + TimeInterval(i)
            let state: PostureState = slouched ? .bad(since: start) : .good
            last = e.evaluate(state: state, trackingQuality: quality, movementLevel: 0, taskMode: .unknown,
                              currentTime: t, metrics: nil, headTurnedSince: nil, silenced: false)
            if case .fire = last { fires.append(t); e.recordNudgeFired(at: t) }
        }
        return last
    }

    /// Two minutes still felt too long in the second real-use hour (2026-10-08): one minute.
    func test_theDefaults() {
        let t = PostureThresholds()
        XCTAssertEqual(t.slouchDurationBeforeNudge, 60, "1 minute, after Dave's second hour")
        XCTAssertEqual(NudgeEngine().slouchEpisodeEndsAfterGood, 30)
    }

    func test_byDefault_aMinuteOfSlouching_earnsANudge() {
        let e = NudgeEngine(); var fires: [TimeInterval] = []
        run(e, from: 0, seconds: 70, slouched: true, fires: &fires)
        XCTAssertEqual(fires.first ?? -1, 60, accuracy: 1.5)
    }

    func test_twoMinutesOfSlouching_earnsANudge() {
        let e = engine(); var fires: [TimeInterval] = []
        run(e, from: 0, seconds: 130, slouched: true, fires: &fires)
        XCTAssertEqual(fires.first ?? -1, 120, accuracy: 1.5)
    }

    /// Slouch 40 s, sit up 10 s, three times over: 120 s slouched, nudged, though no stretch was
    /// longer than 40 s.
    func test_briefSitUps_pauseTheCount_butDontRestartIt() {
        let e = engine(); var fires: [TimeInterval] = []
        var t: TimeInterval = 0
        for _ in 0..<3 {
            run(e, from: t, seconds: 40, slouched: true, fires: &fires); t += 40
            run(e, from: t, seconds: 10, slouched: false, fires: &fires); t += 10
        }
        run(e, from: t, seconds: 5, slouched: true, fires: &fires)
        XCTAssertEqual(fires.count, 1)
        XCTAssertGreaterThanOrEqual(fires.first ?? 0, 119)
    }

    /// Sitting well for 30 s ends the episode: the next slouch starts from zero.
    func test_sittingWellFor30Seconds_endsTheEpisode() {
        let e = engine(); var fires: [TimeInterval] = []
        run(e, from: 0, seconds: 100, slouched: true, fires: &fires)
        run(e, from: 100, seconds: 31, slouched: false, fires: &fires)
        let decision = run(e, from: 131, seconds: 60, slouched: true, fires: &fires)
        XCTAssertEqual(fires, [], "100 s, a real break, then 60 s: not 2 minutes in one episode")
        guard case .pending(_, let remaining) = decision else { return XCTFail("expected pending") }
        XCTAssertEqual(remaining, 61, accuracy: 1.5)
    }

    /// The panel's countdown is slouched time still needed, not time since the episode began.
    func test_pending_countsDownTheSlouchedTimeStillNeeded() {
        let e = engine(); var fires: [TimeInterval] = []
        run(e, from: 0, seconds: 30, slouched: true, fires: &fires)
        run(e, from: 30, seconds: 20, slouched: false, fires: &fires)
        let decision = run(e, from: 50, seconds: 30, slouched: true, fires: &fires)
        guard case .pending(_, let remaining) = decision else { return XCTFail("expected pending") }
        XCTAssertEqual(remaining, 61, accuracy: 1.5, "59 s slouched so far")
    }

    /// Without a clear view nothing is counted either way.
    func test_withoutAClearView_nothingCounts() {
        let e = engine(); var fires: [TimeInterval] = []
        run(e, from: 0, seconds: 60, slouched: true, fires: &fires)
        run(e, from: 60, seconds: 120, slouched: true, quality: .lost, fires: &fires)
        let decision = run(e, from: 180, seconds: 30, slouched: true, fires: &fires)
        XCTAssertEqual(fires, [])
        guard case .pending(_, let remaining) = decision else { return XCTFail("expected pending") }
        XCTAssertEqual(remaining, 31, accuracy: 1.5)
    }

    /// A long gap between frames (the app paused) is a break, not slouching.
    func test_aLongGap_startsAgain() {
        let e = engine(); var fires: [TimeInterval] = []
        run(e, from: 0, seconds: 100, slouched: true, fires: &fires)
        let decision = run(e, from: 400, seconds: 10, slouched: true, fires: &fires)
        guard case .pending(_, let remaining) = decision else { return XCTFail("expected pending") }
        XCTAssertGreaterThan(remaining, 100)
    }

    /// After a nudge, the next one needs its own slouched time (and, uncorrected, the cooldown).
    func test_afterANudge_theCountStartsAgain() {
        var thresholds = PostureThresholds()
        thresholds.slouchDurationBeforeNudge = 120
        thresholds.nudgeCooldown = 1
        let e = NudgeEngine(thresholds: thresholds); var fires: [TimeInterval] = []
        run(e, from: 0, seconds: 250, slouched: true, fires: &fires)
        XCTAssertEqual(fires.count, 2)
        XCTAssertEqual((fires.last ?? 0) - (fires.first ?? 0), 120, accuracy: 2)
    }
}
