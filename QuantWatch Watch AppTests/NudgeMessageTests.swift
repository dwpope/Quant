import Foundation
import Testing
import SwiftUI
import UserNotifications
@testable import QuantWatch_Watch_App

/// What the Watch shows for a nudge. The phone now sends its reason's coaching line; the
/// dictionaries here are the golden copies the phone's `HeadTurnNudgeTests` assert.
struct NudgeMessageTests {

    @Test func showsTheCoachingLineThePhoneSent() {
        let message: [String: Any] = [
            "type": "nudge", "haptic": "failure", "body": "Turn your chair to face that screen",
        ]
        #expect(NudgeMessage.body(from: message) == "Turn your chair to face that screen")
    }

    /// A phone on an older build sends no line.
    @Test func withoutALine_saysWhatItAlwaysSaid() {
        #expect(NudgeMessage.body(from: ["type": "nudge", "haptic": "failure"]) == "Straighten up!")
        #expect(NudgeMessage.body(from: ["type": "nudge", "body": ""]) == "Straighten up!")
    }
}

/// A nudge on the wrist shows its line (2026-10-08). In Dave's second real-use hour a nudge
/// buzzed with no message: the line goes out as a notification, and watchOS hides an app's own
/// notifications while that app is open unless the app asks for them.
struct NudgeNotificationTests {

    @Test func theNotificationCarriesTheLine() {
        let content = NudgeMessage.notificationContent(body: "Sit back — you're leaning in")
        #expect(content.title == "Posture Check")
        #expect(content.body == "Sit back — you're leaning in")
        #expect(content.sound != nil, "closed, the notification is the buzz")
    }

    /// Open, it shows as a banner. No sound: the app has already buzzed.
    @Test func withTheAppOpen_aNudgeShowsAsABanner() {
        let id = NudgeMessage.notificationIdentifier()
        #expect(NudgeMessage.presentationOptions(forIdentifier: id) == [.banner, .list])
    }

    @Test func otherNotifications_stayAsTheyAre() {
        #expect(NudgeMessage.presentationOptions(forIdentifier: "something-else") == [])
    }

    /// The Watch screen shows the last nudge's line under its time.
    @MainActor @Test func theScreenShowsTheLastLine() {
        let delegate = WatchSessionDelegate(activatesSession: false)
        delegate.showNudge(.notification, body: "Lift your head — ease your neck back")
        #expect(delegate.lastNudgeBody == "Lift your head — ease your neck back")
        #expect(delegate.lastNudgeTime != nil)
    }
}

/// The Watch tells the phone when each nudge arrived, for the posture log (2026-10-10): session 3's
/// nudges arrived late and nothing said how late. The dictionaries are the golden copies the
/// phone's `NudgeArrivalTests` assert.
struct NudgeArrivalReportTests {

    @Test func readsWhenThePhoneSentIt() {
        #expect(NudgeMessage.sentAt(from: ["type": "nudge", "sentAt": 1_791_640_000.0])
                == Date(timeIntervalSince1970: 1_791_640_000))
        #expect(NudgeMessage.sentAt(from: ["type": "nudge"]) == nil, "an older phone build")
    }

    @Test func reportsWhenItArrived_andHow() {
        let report = NudgeMessage.arrivalReport(
            sentAt: Date(timeIntervalSince1970: 1_791_640_000),
            arrivedAt: Date(timeIntervalSince1970: 1_791_640_002.5),
            via: "message", wristSession: true)
        #expect(report as NSDictionary == [
            "type": "nudgeArrived", "sentAt": 1_791_640_000.0, "arrivedAt": 1_791_640_002.5,
            "via": "message", "wristSession": true,
        ] as NSDictionary)
    }
}

/// A queued nudge's arrival report is queued too (2026-10-11): it arrives in a background wake
/// that can end before a straight send gets through, and then the report was lost.
struct ArrivalReportRouteTests {

    @Test func aQueuedNudge_isReportedQueued_evenWithThePhoneReachable() {
        #expect(!NudgeMessage.reportsArrivalStraightAway(nudgeWasQueued: true, phoneReachable: true))
    }

    @Test func aNudgeThatCameStraight_isReportedStraight_whenThePhoneCanTakeIt() {
        #expect(NudgeMessage.reportsArrivalStraightAway(nudgeWasQueued: false, phoneReachable: true))
        #expect(!NudgeMessage.reportsArrivalStraightAway(nudgeWasQueued: false, phoneReachable: false))
    }
}

/// Where the banner goes (2026-11-09): with the app minimised Dave heard a tone and felt a buzz
/// but saw no notification. The tone and buzz may be the app's own taps, played from its wrist
/// session, not the notification. Each nudge now reports the app's state when it arrived, and
/// what became of its notification. Golden copies of the phone's `NudgeBannerTests`.
struct NudgeBannerReportTests {

    @Test func theArrival_saysWhetherTheAppWasInFront() {
        let report = NudgeMessage.arrivalReport(
            sentAt: Date(timeIntervalSince1970: 1_791_640_000),
            arrivedAt: Date(timeIntervalSince1970: 1_791_640_000.2),
            via: "queued", wristSession: true, appState: "background")
        #expect(report as NSDictionary == [
            "type": "nudgeArrived", "sentAt": 1_791_640_000.0, "arrivedAt": 1_791_640_000.2,
            "via": "queued", "wristSession": true, "appState": "background",
        ] as NSDictionary)
    }

    @Test func theAppsState_isNamed() {
        #expect(NudgeMessage.appState(.active) == "active")
        #expect(NudgeMessage.appState(.inactive) == "inactive")
        #expect(NudgeMessage.appState(.background) == "background")
    }

    @Test func theBanner_saysWhetherItWasPosted_andHowNotificationsAreSet() {
        let report = NudgeMessage.bannerReport(
            sentAt: Date(timeIntervalSince1970: 1_791_640_000), posted: true, error: nil,
            authorization: .authorized, alert: .enabled, notificationCenter: .enabled)
        #expect(report as NSDictionary == [
            "type": "nudgeBanner", "sentAt": 1_791_640_000.0, "posted": true,
            "authorization": "authorized", "alert": "enabled", "notificationCenter": "enabled",
        ] as NSDictionary)
    }

    @Test func aFailedPost_carriesItsError() {
        let report = NudgeMessage.bannerReport(
            sentAt: Date(timeIntervalSince1970: 1_791_640_000), posted: false, error: "not allowed",
            authorization: .denied, alert: .disabled, notificationCenter: .disabled)
        #expect(report["posted"] as? Bool == false)
        #expect(report["error"] as? String == "not allowed")
        #expect(report["authorization"] as? String == "denied")
        #expect(report["alert"] as? String == "disabled")
        #expect(report["notificationCenter"] as? String == "disabled")
    }

    @Test func everySetting_hasAName() {
        #expect(NudgeMessage.name(UNAuthorizationStatus.notDetermined) == "notDetermined")
        #expect(NudgeMessage.name(UNAuthorizationStatus.provisional) == "provisional")
        #expect(NudgeMessage.name(UNNotificationSetting.notSupported) == "notSupported")
    }
}

/// The app's state, kept where WatchConnectivity's queue can read it as a nudge arrives
/// (2026-11-09).
struct AppStateTrackingTests {

    @Test func theState_followsTheScenePhase_andStartsInTheBackground() {
        let delegate = WatchSessionDelegate(activatesSession: false)
        #expect(delegate.appState == "background", "a background launch, before any scene")
        delegate.appPhaseChanged(.active)
        #expect(delegate.appState == "active")
        delegate.appPhaseChanged(.background)
        #expect(delegate.appState == "background")
    }
}

/// A nudge on the app's own screen while the app is in front (2026-11-09, session 7).
///
/// Dave: "Buzz and tone when viewing watch app, no notification." Every nudge's notification was
/// posted, with notifications allowed, and none showed: the app's own taps were the buzz and the
/// tone. In front, the app now shows the nudge itself, and its notification only goes to the list.
struct NudgeOnScreenTests {

    @Test func inFront_theAppShowsTheNudgeItself() {
        #expect(NudgeMessage.showsOnScreen(appState: "active"))
        #expect(NudgeMessage.showsOnScreen(appState: "inactive"), "in front, the wrist down")
        #expect(!NudgeMessage.showsOnScreen(appState: "background"))
    }

    @MainActor @Test func aNudgeInFront_isPutOnScreen() {
        let delegate = WatchSessionDelegate(activatesSession: false)
        delegate.showNudge(.notification, body: "Sit back — you're leaning in", onScreen: true)
        #expect(delegate.nudgeOnScreen?.body == "Sit back — you're leaning in")
    }

    /// Minimised, the notification shows it; the app's screen isn't left holding an old one.
    @MainActor @Test func aNudgeInTheBackground_isLeftToItsNotification() {
        let delegate = WatchSessionDelegate(activatesSession: false)
        delegate.showNudge(.notification, body: "Lift your head — ease your neck back", onScreen: true)
        delegate.showNudge(.notification, body: "Sit back — you're leaning in", onScreen: false)
        #expect(delegate.nudgeOnScreen == nil, "the older one, cleared")
        #expect(delegate.lastNudgeBody == "Sit back — you're leaning in", "still the last nudge")
    }

    @MainActor @Test func aNewNudge_takesTheOldOnesPlace() {
        let delegate = WatchSessionDelegate(activatesSession: false)
        delegate.showNudge(.notification, body: "Sit back — you're leaning in", onScreen: true)
        let first = delegate.nudgeOnScreen
        delegate.showNudge(.notification, body: "Lift your head — ease your neck back", onScreen: true)
        #expect(delegate.nudgeOnScreen?.body == "Lift your head — ease your neck back")
        #expect(delegate.nudgeOnScreen?.id != first?.id, "shown afresh")
    }

    /// On the screen already: its notification is listed, not shown over it as well.
    @Test func onScreen_theNotificationIsOnlyListed() {
        let id = NudgeMessage.notificationIdentifier()
        let onScreen = NudgeMessage.notificationContent(body: "Sit back", onScreen: true)
        #expect(NudgeMessage.presentationOptions(forIdentifier: id, userInfo: onScreen.userInfo) == [.list])
        let minimised = NudgeMessage.notificationContent(body: "Sit back", onScreen: false)
        #expect(NudgeMessage.presentationOptions(forIdentifier: id, userInfo: minimised.userInfo)
                == [.banner, .list])
    }
}

/// What watchOS did with each nudge's notification (2026-11-09). Posted, allowed, and not seen
/// with the app minimised: so each one is watched for half a minute, for when watchOS first
/// offered it to the app and with what, and when it first appeared in Notification Center. A
/// Watch app with its iPhone app installed may hold a notification about 13 s for the phone's
/// copy. Golden copies of the phone's `NudgeNotificationTimesTests`.
struct NudgeNotificationReportTests {

    @Test func theReport_saysWhenItWasOffered_andListed() {
        let report = NudgeMessage.notificationReport(
            sentAt: Date(timeIntervalSince1970: 1_791_640_000), onScreen: false, offeredAfter: 0.4,
            offeredAs: "banner,list", listedAfter: 13.6, datedAfter: 13.2)
        #expect(report as NSDictionary == [
            "type": "nudgeNotification", "sentAt": 1_791_640_000.0, "onScreen": false,
            "offeredAfter": 0.4, "offeredAs": "banner,list", "listedAfter": 13.6, "datedAfter": 13.2,
        ] as NSDictionary)
    }

    /// Neither within the half minute: the report says only that it was watched.
    @Test func neither_isLeftOut() {
        let report = NudgeMessage.notificationReport(
            sentAt: Date(timeIntervalSince1970: 1_791_640_000), onScreen: true, offeredAfter: nil,
            offeredAs: nil, listedAfter: nil, datedAfter: nil)
        #expect(report as NSDictionary == [
            "type": "nudgeNotification", "sentAt": 1_791_640_000.0, "onScreen": true,
        ] as NSDictionary)
    }

    @Test func whatTheAppAnswered_isNamed() {
        #expect(NudgeMessage.name([.banner, .list] as UNNotificationPresentationOptions) == "banner,list")
        #expect(NudgeMessage.name([.list] as UNNotificationPresentationOptions) == "list")
        #expect(NudgeMessage.name([] as UNNotificationPresentationOptions) == "none")
    }

    /// Listed: report. Not yet: look again, up to half a minute, then report it wasn't.
    @Test func itsWatched_untilListed_orForHalfAMinute() {
        #expect(NudgeMessage.deliveryWatchStep(listed: true, elapsed: 2, late: 0) == .report)
        #expect(NudgeMessage.deliveryWatchStep(listed: false, elapsed: 2, late: 0) == .lookAgain)
        #expect(NudgeMessage.deliveryWatchStep(listed: false, elapsed: 29.9, late: 0.1) == .lookAgain)
        #expect(NudgeMessage.deliveryWatchStep(listed: false, elapsed: 30, late: 0) == .report)
    }

    /// A look that comes late: the app was paused, and the times would read minutes or hours.
    @Test func aLateLook_givesUp() {
        #expect(NudgeMessage.deliveryWatchStep(listed: true, elapsed: 600, late: 590) == .giveUp)
        #expect(NudgeMessage.deliveryWatchStep(listed: false, elapsed: 8, late: 4) == .giveUp)
    }
}
