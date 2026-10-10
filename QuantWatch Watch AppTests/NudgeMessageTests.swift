import Foundation
import Testing
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
