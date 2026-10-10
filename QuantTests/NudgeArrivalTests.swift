import XCTest
@testable import Quant

/// When each nudge reached the Watch, in the posture log (2026-10-10).
///
/// Session 3's four nudges were queued for a closed Watch app and arrived late, and the log
/// couldn't say how late. The phone now stamps each nudge with when it was sent; the Watch reports
/// back when it arrived, how (straight to the running app, or queued), and whether the app was
/// being kept running. The dictionaries match the Watch's `NudgeArrivalReportTests`.
@MainActor
final class NudgeArrivalTests: XCTestCase {

    func test_aNudge_carriesWhenItWasSent() {
        let sent = Date(timeIntervalSince1970: 1_791_640_000)
        let message = WatchConnectivityService.nudgeMessage(hapticType: "failure", body: "Sit back",
                                                            sentAt: sent)
        XCTAssertEqual(message["sentAt"] as? Double, 1_791_640_000)
    }

    func test_theWatchsReport_isRead() throws {
        let arrival = try XCTUnwrap(WatchConnectivityService.nudgeArrival(from: [
            "type": "nudgeArrived", "sentAt": 1_791_640_000.0, "arrivedAt": 1_791_640_002.5,
            "via": "message", "wristSession": true,
        ]))
        XCTAssertEqual(arrival.sentAt, Date(timeIntervalSince1970: 1_791_640_000))
        XCTAssertEqual(arrival.arrivedAt, Date(timeIntervalSince1970: 1_791_640_002.5))
        XCTAssertEqual(arrival.via, "message")
        XCTAssertTrue(arrival.wristSession)
    }

    func test_somethingElse_isNotAReport() {
        XCTAssertNil(WatchConnectivityService.nudgeArrival(from: ["type": "settings"]))
        XCTAssertNil(WatchConnectivityService.nudgeArrival(from: ["type": "nudgeArrived"]))
    }

    func test_theArrival_isALogLine_withHowLate() {
        let arrival = NudgeArrival(sentAt: Date(timeIntervalSince1970: 1_791_640_000),
                                   arrivedAt: Date(timeIntervalSince1970: 1_791_640_095),
                                   via: "queued", wristSession: false)
        let event = PostureLogRecorder.arrivalEvent(arrival)
        XCTAssertEqual(event.kind, "watch")
        XCTAssertEqual(event.value, "arrived")
        XCTAssertEqual(event.t, 1_791_640_095)
        XCTAssertEqual(event.delay, 95)
        XCTAssertEqual(event.via, "queued")
        XCTAssertEqual(event.wristSession, false)
    }
}
