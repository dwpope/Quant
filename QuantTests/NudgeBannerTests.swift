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

/// What watchOS did with the Watch's notification (2026-11-09, after session 7).
///
/// Every banner of session 7 was posted with notifications allowed, and Dave saw none. The Watch
/// now watches each one for half a minute: when watchOS first offered it to the app and what the
/// app answered, and when it first appeared in Notification Center. The dictionaries match the
/// Watch's `NudgeNotificationReportTests`.
@MainActor
final class NudgeNotificationTimesTests: XCTestCase {

    private let sentAt = Date(timeIntervalSince1970: 1_791_640_000)

    func test_theReport_isRead() throws {
        let times = try XCTUnwrap(WatchConnectivityService.nudgeNotificationTimes(from: [
            "type": "nudgeNotification", "sentAt": 1_791_640_000.0, "onScreen": false,
            "offeredAfter": 0.4, "offeredAs": "banner,list", "listedAfter": 13.6, "datedAfter": 13.2,
        ]))
        XCTAssertEqual(times, NudgeNotificationTimes(sentAt: sentAt, onScreen: false, offeredAfter: 0.4,
                                                     offeredAs: "banner,list", listedAfter: 13.6,
                                                     datedAfter: 13.2))
    }

    /// Neither within the half minute.
    func test_neither_readsAsNil() throws {
        let times = try XCTUnwrap(WatchConnectivityService.nudgeNotificationTimes(from: [
            "type": "nudgeNotification", "sentAt": 1_791_640_000.0, "onScreen": true,
        ]))
        XCTAssertNil(times.offeredAfter)
        XCTAssertNil(times.offeredAs)
        XCTAssertNil(times.listedAfter)
        XCTAssertNil(times.datedAfter)
    }

    func test_somethingElse_isNotThisReport() {
        XCTAssertNil(WatchConnectivityService.nudgeNotificationTimes(from: ["type": "nudgeBanner", "sentAt": 1.0]))
        XCTAssertNil(WatchConnectivityService.nudgeNotificationTimes(from: ["type": "nudgeNotification"]))
    }

    /// A line beside the banner's, at the nudge's sending time.
    func test_itIsALogLine() {
        let event = PostureLogRecorder.notificationEvent(NudgeNotificationTimes(
            sentAt: sentAt, onScreen: true, offeredAfter: 0.3, offeredAs: "list", listedAfter: 1.1,
            datedAfter: 0.3))
        XCTAssertEqual(event.kind, "watch")
        XCTAssertEqual(event.value, "notification")
        XCTAssertEqual(event.t, 1_791_640_000)
        XCTAssertEqual(event.onScreen, true)
        XCTAssertEqual(event.offeredAfter, 0.3)
        XCTAssertEqual(event.offeredAs, "list")
        XCTAssertEqual(event.listedAfter, 1.1)
        XCTAssertEqual(event.datedAfter, 0.3)
    }

    func test_theReport_isPassedOn_eitherWay() {
        let model = AppModel()
        let service = model.watchService
        var received: [NudgeNotificationTimes] = []
        let subscription = service.nudgeNotificationReported.sink { received.append($0) }
        defer { subscription.cancel() }
        let report: [String: Any] = ["type": "nudgeNotification", "sentAt": 1_791_640_000.0, "onScreen": false]
        service.handleReceivedMessage(report)
        XCTAssertEqual(received.count, 1)
        service.handleQueued(report)
        XCTAssertEqual(received.count, 2)
    }
}
