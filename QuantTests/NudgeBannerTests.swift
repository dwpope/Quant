import Combine
import XCTest
@testable import Quant

/// Where the Watch's banner goes (2026-11-09).
///
/// With the Watch app minimised Dave heard a tone and felt a buzz but saw no notification. The
/// tone and buzz may be the app's own taps, played from its wrist session, not the notification.
/// So the Watch reports whether it was in front when each nudge arrived, and what became of the
/// nudge's notification: posted or not, and how its notifications are set. The dictionaries
/// match the Watch's `NudgeBannerReportTests`.
@MainActor
final class NudgeBannerTests: XCTestCase {

    private let sentAt = Date(timeIntervalSince1970: 1_791_640_000)

    func test_theArrival_saysWhetherTheWatchAppWasInFront() throws {
        let arrival = try XCTUnwrap(WatchConnectivityService.nudgeArrival(from: [
            "type": "nudgeArrived", "sentAt": 1_791_640_000.0, "arrivedAt": 1_791_640_000.2,
            "via": "queued", "wristSession": true, "appState": "background",
        ]))
        XCTAssertEqual(arrival.appState, "background")
        XCTAssertEqual(PostureLogRecorder.arrivalEvent(arrival).appState, "background")
    }

    /// An older Watch build says nothing about it, and still reads.
    func test_anOlderWatchsArrival_hasNoState() throws {
        let arrival = try XCTUnwrap(WatchConnectivityService.nudgeArrival(from: [
            "type": "nudgeArrived", "sentAt": 1_791_640_000.0, "arrivedAt": 1_791_640_000.2,
            "via": "message", "wristSession": false,
        ]))
        XCTAssertNil(arrival.appState)
    }

    func test_theBannerReport_isRead() throws {
        let banner = try XCTUnwrap(WatchConnectivityService.nudgeBanner(from: [
            "type": "nudgeBanner", "sentAt": 1_791_640_000.0, "posted": true,
            "authorization": "authorized", "alert": "enabled", "notificationCenter": "enabled",
        ]))
        XCTAssertEqual(banner, NudgeBanner(sentAt: sentAt, posted: true, error: nil,
                                           authorization: "authorized", alert: "enabled",
                                           notificationCenter: "enabled"))
    }

    func test_somethingElse_isNotABannerReport() {
        XCTAssertNil(WatchConnectivityService.nudgeBanner(from: ["type": "nudgeArrived"]))
        XCTAssertNil(WatchConnectivityService.nudgeBanner(from: ["type": "nudgeBanner"]))
    }

    /// A line in the posture log beside the arrival, at the nudge's sending time.
    func test_theBanner_isALogLine() {
        let banner = NudgeBanner(sentAt: sentAt, posted: false, error: "not allowed",
                                 authorization: "denied", alert: "disabled", notificationCenter: "disabled")
        let event = PostureLogRecorder.bannerEvent(banner)
        XCTAssertEqual(event.kind, "watch")
        XCTAssertEqual(event.value, "banner")
        XCTAssertEqual(event.t, 1_791_640_000)
        XCTAssertEqual(event.posted, false)
        XCTAssertEqual(event.error, "not allowed")
        XCTAssertEqual(event.authorization, "denied")
        XCTAssertEqual(event.alert, "disabled")
        XCTAssertEqual(event.notificationCenter, "disabled")
    }

    /// Straight from the Watch, or queued: both reach the log.
    func test_theReport_isPassedOn_eitherWay() {
        let model = AppModel()
        let service = model.watchService
        var received: [NudgeBanner] = []
        let subscription = service.nudgeBannerReported.sink { received.append($0) }
        defer { subscription.cancel() }
        let report: [String: Any] = [
            "type": "nudgeBanner", "sentAt": 1_791_640_000.0, "posted": true,
            "authorization": "authorized", "alert": "enabled", "notificationCenter": "enabled",
        ]
        service.handleReceivedMessage(report)
        XCTAssertEqual(received.count, 1)
        service.handleQueued(report)
        XCTAssertEqual(received.count, 2)
    }
}
