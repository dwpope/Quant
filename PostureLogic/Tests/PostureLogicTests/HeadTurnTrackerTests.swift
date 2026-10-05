import XCTest
@testable import PostureLogic

/// Timing a head held turned to one side, such as towards a second screen.
///
/// Asked for on 2026-10-04: Dave turns to a second screen, and it gets uncomfortable after about
/// five minutes. A turned head isn't a slouch, and the two can happen together, so it's timed on
/// its own. What counts is the NECK turned: the head past 45° while the shoulders still face the
/// phone. Turning the chair to face the screen narrows the shoulders, and that's the fix.
final class HeadTurnTrackerTests: XCTestCase {

    private func tracker(grace: TimeInterval = 5) -> HeadTurnTracker {
        var thresholds = HeadTurnThresholds()
        thresholds.gracePeriod = grace
        return HeadTurnTracker(thresholds: thresholds)
    }

    @discardableResult
    private func update(_ t: HeadTurnTracker, yaw: Float, creep: Float = 0.05, quality: TrackingQuality = .good,
                        at time: TimeInterval) -> TimeInterval? {
        t.update(headYaw: yaw, forwardCreep: creep, trackingQuality: quality, timestamp: time)
    }

    // MARK: - The defaults

    func test_defaults_areFiveMinutesPast45Degrees() {
        let thresholds = HeadTurnThresholds()
        XCTAssertEqual(thresholds.durationBeforeNudge, 300, "Dave's five minutes")
        XCTAssertEqual(thresholds.turnedDegrees, 45)
        XCTAssertEqual(thresholds.swivelMaxForwardCreep, -0.03)
    }

    // MARK: - The rule, over every capture measured on device so far

    /// [head yaw, forward creep] from sessions 2 to 5.
    func test_everyMeasuredHeadTurn_isANeckTurned() {
        let headTurns: [(Float, Float)] = [
            (-75, 0.162), (60, 0.139), (78, 0.061), (-77, 0.008),
            (-75, 0.060), (77, 0.036), (77, 0.119), (-74, 0.082),
        ]
        for (yaw, creep) in headTurns {
            XCTAssertTrue(HeadTurnTracker.isNeckTurned(headYaw: yaw, forwardCreep: creep,
                                                       thresholds: HeadTurnThresholds()), "\(yaw) \(creep)")
        }
    }

    /// The chair turned with the head: the shoulders narrowed, so the neck isn't twisted.
    func test_noMeasuredChairSwivel_isANeckTurned() {
        let swivels: [(Float, Float)] = [
            (70, -0.399), (-77, -0.052), (60, -0.103), (-76, -0.161), (-76, -0.234),
            (60, -0.069), (-78, -0.146), (-66, -0.277), (60, -0.274), (-79, -0.171),
            (-60, -0.279), (60, -0.048),
        ]
        for (yaw, creep) in swivels {
            XCTAssertFalse(HeadTurnTracker.isNeckTurned(headYaw: yaw, forwardCreep: creep,
                                                        thresholds: HeadTurnThresholds()), "\(yaw) \(creep)")
        }
    }

    /// Looking at the main screen, or turning the head a little while leaning.
    func test_aSmallTurn_isNot() {
        for yaw: Float in [0, 24, -25, 39, 44.9] {
            XCTAssertFalse(HeadTurnTracker.isNeckTurned(headYaw: yaw, forwardCreep: 0.02,
                                                        thresholds: HeadTurnThresholds()), "\(yaw)")
        }
        XCTAssertTrue(HeadTurnTracker.isNeckTurned(headYaw: -45, forwardCreep: 0.02,
                                                   thresholds: HeadTurnThresholds()))
    }

    // MARK: - Timing an episode

    func test_anEpisode_startsAtTheFirstTurnedFrame_andKeepsItsStart() {
        let t = tracker()
        XCTAssertNil(update(t, yaw: 0, at: 100))
        XCTAssertEqual(update(t, yaw: 70, at: 101), 101)
        XCTAssertEqual(update(t, yaw: 72, at: 160), 101)
        XCTAssertEqual(update(t, yaw: -70, at: 400), 101, "either side")
    }

    /// A glance back at the main screen, or a frame the face tracker drops, isn't a rest.
    func test_aBriefLookBack_keepsTheEpisode() {
        let t = tracker(grace: 5)
        update(t, yaw: 70, at: 0)
        XCTAssertEqual(update(t, yaw: 0, at: 3), 0)
        XCTAssertEqual(update(t, yaw: 70, at: 4), 0)
    }

    /// Looking back for longer than the grace period rests the neck: the next turn starts over.
    func test_lookingBackForLonger_endsTheEpisode() {
        let t = tracker(grace: 5)
        update(t, yaw: 70, at: 0)
        update(t, yaw: 0, at: 1)
        XCTAssertNil(update(t, yaw: 0, at: 7))
        XCTAssertEqual(update(t, yaw: 70, at: 8), 8)
    }

    /// Turning the chair to face the screen ends it the same way.
    func test_turningTheChair_endsTheEpisode() {
        let t = tracker(grace: 5)
        update(t, yaw: 70, creep: 0.05, at: 0)
        update(t, yaw: 70, creep: -0.15, at: 1)
        XCTAssertNil(update(t, yaw: 70, creep: -0.15, at: 7))
    }

    /// Nothing is judged without a clear view: the posture engine's rule.
    func test_withoutAClearView_nothingIsTimed() {
        let t = tracker(grace: 5)
        XCTAssertNil(update(t, yaw: 70, quality: .lost, at: 0))
        update(t, yaw: 70, at: 1)
        XCTAssertNil(update(t, yaw: 70, quality: .lost, at: 10), "a lost view ends it after the grace")
    }

    func test_reset_forgetsTheEpisode() {
        let t = tracker()
        update(t, yaw: 70, at: 0)
        t.reset()
        XCTAssertEqual(update(t, yaw: 70, at: 50), 50)
    }
}
