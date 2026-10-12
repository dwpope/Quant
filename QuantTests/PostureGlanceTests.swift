import XCTest
import PostureLogic
@testable import Quant

/// Your posture on the Watch: slouching or not, and for how long (2026-10-11).
///
/// The Watch and the phone are separate targets with no shared code, so the message is a
/// contract. The dictionaries below are its golden copy; the Watch's `PostureGlanceTests` reads
/// the same ones.
@MainActor
final class PostureGlanceTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_791_640_000)

    // MARK: - The message (golden)

    func test_sittingWell() {
        let glance = PostureGlance(state: .good, since: nil, headTurnedSince: nil)
        XCTAssertEqual(glance.message as NSDictionary,
                       ["type": "posture", "state": "good"] as NSDictionary)
    }

    func test_slouching_saysSinceWhen() {
        let drifting = PostureGlance(state: .drifting(since: 5), since: start, headTurnedSince: nil)
        XCTAssertEqual(drifting.message as NSDictionary,
                       ["type": "posture", "state": "drifting", "since": 1_791_640_000.0] as NSDictionary)
        let bad = PostureGlance(state: .bad(since: 5), since: start, headTurnedSince: nil)
        XCTAssertEqual(bad.message as NSDictionary,
                       ["type": "posture", "state": "bad", "since": 1_791_640_000.0] as NSDictionary)
    }

    func test_headTurned_saysSinceWhen() {
        let glance = PostureGlance(state: .good, since: nil, headTurnedSince: start)
        XCTAssertEqual(glance.message as NSDictionary,
                       ["type": "posture", "state": "good", "headTurned": 1_791_640_000.0] as NSDictionary)
    }

    func test_awayAndCalibrating() {
        XCTAssertEqual(PostureGlance(state: .absent, since: nil, headTurnedSince: nil).message as NSDictionary,
                       ["type": "posture", "state": "absent"] as NSDictionary)
        XCTAssertEqual(PostureGlance(state: .calibrating, since: nil, headTurnedSince: nil).message as NSDictionary,
                       ["type": "posture", "state": "calibrating"] as NSDictionary)
    }

    /// Whole seconds, so a glance checked once a second doesn't differ only by frame jitter.
    func test_timesAreWholeSeconds() {
        let glance = PostureGlance(state: .drifting(since: 5), since: start.addingTimeInterval(0.4),
                                   headTurnedSince: start.addingTimeInterval(7.6))
        XCTAssertEqual(glance.since, 1_791_640_000)
        XCTAssertEqual(glance.headTurnedSince, 1_791_640_008)
    }

    /// Only a slouch has a start.
    func test_sittingWell_sendsNoStart() {
        XCTAssertNil(PostureGlance(state: .good, since: start, headTurnedSince: nil).since)
    }

    // MARK: - When it's sent

    func test_theFirstIsSent() {
        let glance = PostureGlance(state: .good, since: nil, headTurnedSince: nil)
        XCTAssertTrue(PostureGlance.isDue(glance, lastSent: nil, sentAt: nil, now: start))
    }

    func test_aChange_isSentStraightAway() {
        let good = PostureGlance(state: .good, since: nil, headTurnedSince: nil)
        let slouching = PostureGlance(state: .drifting(since: 5), since: start, headTurnedSince: nil)
        XCTAssertTrue(PostureGlance.isDue(slouching, lastSent: good, sentAt: start,
                                          now: start.addingTimeInterval(1)))
    }

    /// Resent every 15 s while nothing changes, so the Watch can tell a phone that has stopped
    /// sending from a posture that's held.
    func test_noChange_isResentEvery15Seconds() {
        let good = PostureGlance(state: .good, since: nil, headTurnedSince: nil)
        XCTAssertFalse(PostureGlance.isDue(good, lastSent: good, sentAt: start,
                                           now: start.addingTimeInterval(14)))
        XCTAssertTrue(PostureGlance.isDue(good, lastSent: good, sentAt: start,
                                          now: start.addingTimeInterval(15)))
    }

    // MARK: - From the app's state

    /// The slouch's start is a frame time; the Watch counts up from a calendar time.
    func test_theApp_sendsTheSlouchStart_asACalendarTime() throws {
        let model = AppModel()
        model.postureState = .drifting(since: 670_636)
        model.latestMetrics = RawMetrics(
            timestamp: 670_648, forwardCreep: 0, headDrop: 0, shoulderRounding: 0,
            lateralLean: 0, twist: 0, movementLevel: 0, headMovementPattern: .still)

        let glance = model.postureGlance(wallNow: start)

        XCTAssertEqual(glance.state, "drifting")
        XCTAssertEqual(try XCTUnwrap(glance.since), start.timeIntervalSince1970 - 12, accuracy: 0.5)
        XCTAssertNil(glance.headTurnedSince)
    }

    // MARK: - Steady times (2026-10-11)

    /// The start is worked out each second and its rounding can flip a second either way:
    /// that sent a glance every second and made the Watch's timer jump.
    func test_aStartThatJitters_byASecond_keepsTheOneSent() {
        let sent = PostureGlance(state: .drifting(since: 5), since: start, headTurnedSince: nil)
        let now = PostureGlance(state: .drifting(since: 5), since: start.addingTimeInterval(1), headTurnedSince: nil)
            .steadied(against: sent)
        XCTAssertEqual(now, sent)
        XCTAssertFalse(PostureGlance.isDue(now, lastSent: sent, sentAt: start, now: start.addingTimeInterval(2)))
    }

    func test_aNewSlouch_sendsItsOwnStart() {
        let sent = PostureGlance(state: .drifting(since: 5), since: start, headTurnedSince: nil)
        let later = PostureGlance(state: .drifting(since: 5), since: start.addingTimeInterval(30), headTurnedSince: nil)
        XCTAssertEqual(later.steadied(against: sent).since, start.timeIntervalSince1970 + 30)
        let fromGood = PostureGlance(state: .bad(since: 5), since: start.addingTimeInterval(1), headTurnedSince: nil)
            .steadied(against: PostureGlance(state: .good, since: nil, headTurnedSince: nil))
        XCTAssertEqual(fromGood.since, start.timeIntervalSince1970 + 1)
    }

    /// The Watch shows a head turn only while sitting well, so it isn't sent otherwise.
    func test_aHeadTurn_isOnlySentWhileSittingWell() {
        let slouching = PostureGlance(state: .drifting(since: 5), since: start, headTurnedSince: start)
        XCTAssertNil(slouching.steadied(against: nil).headTurnedSince)
        let sittingWell = PostureGlance(state: .good, since: nil, headTurnedSince: start)
        XCTAssertEqual(sittingWell.steadied(against: nil).headTurnedSince, start.timeIntervalSince1970)
    }
}
