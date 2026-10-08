import XCTest
@testable import Quant

/// How each nudge left for the Watch, in the posture log (2026-10-08).
///
/// In Dave's second real-use hour the phone fired at 16:03:52 and 16:13:52, and he felt one buzz.
/// A nudge goes straight to the Watch app when it's open and is queued when it isn't, and nothing
/// recorded which. Now each nudge logs its route, so the next log says whether a quiet nudge was
/// queued.
@MainActor
final class NudgeDeliveryTests: XCTestCase {

    func test_theWatchAppOpen_sendsStraightToIt() {
        XCTAssertEqual(WatchConnectivityService.nudgeRoute(isSupported: true, isPaired: true, isReachable: true),
                       .sent)
    }

    func test_theWatchAppClosed_queuesIt() {
        XCTAssertEqual(WatchConnectivityService.nudgeRoute(isSupported: true, isPaired: true, isReachable: false),
                       .queued)
    }

    func test_noWatch_sendsNothing() {
        XCTAssertEqual(WatchConnectivityService.nudgeRoute(isSupported: true, isPaired: false, isReachable: false),
                       .noWatch)
        XCTAssertEqual(WatchConnectivityService.nudgeRoute(isSupported: false, isPaired: true, isReachable: true),
                       .noWatch)
    }

    func test_theRoute_isALogLine() {
        let now = Date(timeIntervalSince1970: 1_791_471_832)
        let event = PostureLogRecorder.watchEvent(.queued, now: now)
        XCTAssertEqual(event.kind, "watch")
        XCTAssertEqual(event.value, "queued")
        XCTAssertEqual(event.t, 1_791_471_832)
        XCTAssertEqual(PostureLogRecorder.watchEvent(.queuedAfterFailedSend, now: now).value,
                       "queuedAfterFailedSend")
    }
}
