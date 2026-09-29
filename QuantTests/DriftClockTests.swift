import XCTest
import PostureLogic
@testable import Quant

/// How long the thresholds have been drifting, measured on the right clock.
///
/// `PostureState.drifting(since:)` holds the camera frame's timestamp, which is seconds since the
/// device booted: 670,636 in the first device session. The phone's panel and the Watch both
/// subtracted it from the calendar clock, about 1.79 billion, so the timer read ~56 years.
final class DriftClockTests: XCTestCase {

    /// The frame timestamp from the first device session.
    private let since: TimeInterval = 670_636

    func test_elapsed_isMeasuredOnTheFrameClock() {
        XCTAssertEqual(DriftClock.elapsed(.drifting(since: since), frameNow: since + 12), 12)
        XCTAssertEqual(DriftClock.elapsed(.bad(since: since), frameNow: since + 75), 75)
    }

    func test_elapsed_isNil_forStatesWithoutAStart_orWithoutAFrame() {
        XCTAssertNil(DriftClock.elapsed(.good, frameNow: since))
        XCTAssertNil(DriftClock.elapsed(.absent, frameNow: since))
        XCTAssertNil(DriftClock.elapsed(.calibrating, frameNow: since))
        XCTAssertNil(DriftClock.elapsed(.drifting(since: since), frameNow: nil))
    }

    /// A replay or a restarted session can hand a frame time earlier than the state's start.
    func test_elapsed_neverGoesNegative() {
        XCTAssertEqual(DriftClock.elapsed(.drifting(since: since), frameNow: since - 5), 0)
    }

    /// The Watch shows a running timer from a calendar date, so the phone converts the start.
    func test_wallClockStart_isNowMinusTheElapsedTime() throws {
        let wallNow = Date(timeIntervalSince1970: 1_790_000_000)
        let start = try XCTUnwrap(DriftClock.wallClockStart(
            .drifting(since: since), frameNow: since + 12, wallNow: wallNow))
        XCTAssertEqual(start.timeIntervalSince1970, 1_790_000_000 - 12, accuracy: 0.001)
    }

    func test_wallClockStart_isNil_whenThereIsNoElapsedTime() {
        XCTAssertNil(DriftClock.wallClockStart(.good, frameNow: since, wallNow: Date()))
    }
}
