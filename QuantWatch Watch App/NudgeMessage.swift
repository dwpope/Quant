//
//  NudgeMessage.swift
//  QuantWatch Watch App
//
//  What a nudge says on the wrist.
//

import Foundation
import SwiftUI
import UserNotifications

/// The line a nudge shows. The phone sends its reason's coaching line, such as "Turn your chair
/// to face that screen" for a head held turned; a phone on an older build sends none, and the
/// Watch says what it always said.
enum NudgeMessage {
    static let fallbackBody = "Straighten up!"

    static func body(from message: [String: Any]) -> String {
        guard let body = message["body"] as? String, !body.isEmpty else { return fallbackBody }
        return body
    }

    /// The nudge's reason (the phone's `NudgeReason`), or nil from a phone build that doesn't
    /// say (2026-10-13).
    static func reason(from message: [String: Any]) -> String? {
        message["reason"] as? String
    }

    /// Which repeat it is: 0 for a slouch's first nudge, 1 for the next while it goes on.
    static func repeatCount(from message: [String: Any]) -> Int {
        (message["repeat"] as? NSNumber)?.intValue ?? 0
    }
}

// MARK: - The notification (2026-10-08)
//
// In Dave's second real-use hour a nudge buzzed with no message. The line goes out as a
// notification, and watchOS hides an app's own notifications while that app is open unless the
// app asks for them; Aware didn't ask. A nudge queued while the app was closed now wakes it to
// post the notification, which is then the buzz and the message both.

extension NudgeMessage {
    static let notificationTitle = "Posture Check"
    private static let identifierPrefix = "nudge-"

    static func notificationIdentifier() -> String { identifierPrefix + UUID().uuidString }

    /// `onScreen` when the app shows the nudge itself (2026-11-09), for `presentationOptions`.
    static func notificationContent(body: String, onScreen: Bool = false) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notificationTitle
        content.body = body
        content.sound = .default
        content.userInfo = [onScreenKey: onScreen]
        return content
    }

    private static let onScreenKey = "onScreen"

    /// With the app open: a nudge shows as a banner, without a sound because the app has already
    /// buzzed; only listed when the app is showing it already (2026-11-09). The app posts nothing
    /// else; anything else stays hidden, as before.
    static func presentationOptions(forIdentifier identifier: String,
                                    userInfo: [AnyHashable: Any] = [:]) -> UNNotificationPresentationOptions {
        guard identifier.hasPrefix(identifierPrefix) else { return [] }
        return userInfo[onScreenKey] as? Bool == true ? [.list] : [.banner, .list]
    }
}

// MARK: - The arrival report (2026-10-10)
//
// Session 3's nudges arrived late and nothing said how late. The phone stamps each nudge with when
// it was sent; the Watch reports when it arrived, how, and whether the app was being kept running.

extension NudgeMessage {
    /// When the phone sent it, or nil from a phone build that doesn't say.
    /// Whether a nudge's arrival report goes straight to the phone: only for a nudge that came
    /// straight, with the phone able to take it. A queued nudge's report is queued too.
    static func reportsArrivalStraightAway(nudgeWasQueued: Bool, phoneReachable: Bool) -> Bool {
        !nudgeWasQueued && phoneReachable
    }

    static func sentAt(from message: [String: Any]) -> Date? {
        (message["sentAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
    }

    /// `via` is "message" (straight to the running app) or "queued". `appState` is the app's
    /// state when it arrived (2026-11-09), from `appState(_:)`.
    static func arrivalReport(sentAt: Date, arrivedAt: Date, via: String,
                              wristSession: Bool, appState: String? = nil) -> [String: Any] {
        var report: [String: Any] = [
            "type": "nudgeArrived", "sentAt": sentAt.timeIntervalSince1970,
            "arrivedAt": arrivedAt.timeIntervalSince1970, "via": via, "wristSession": wristSession,
        ]
        if let appState { report["appState"] = appState }
        return report
    }
}

// MARK: - Where the banner goes (2026-11-09)
//
// With the app minimised Dave heard a tone and felt a buzz but saw no notification. The tone and
// buzz may be the app's own taps, played from its wrist session in the background, and not the
// notification at all. So each nudge reports whether the app was in front when it arrived, and
// what became of its notification: posted or not, and how this app's notifications are set.

extension NudgeMessage {
    /// "active" (in front), "inactive" or "background".
    static func appState(_ phase: ScenePhase) -> String {
        switch phase {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    /// What became of a nudge's notification, for the phone's posture log.
    /// `alert` is whether banners are allowed; `notificationCenter`, whether the notification
    /// is kept in Notification Center (watchOS has no alert style).
    static func bannerReport(sentAt: Date, posted: Bool, error: String?,
                             authorization: UNAuthorizationStatus, alert: UNNotificationSetting,
                             notificationCenter: UNNotificationSetting) -> [String: Any] {
        var report: [String: Any] = [
            "type": "nudgeBanner", "sentAt": sentAt.timeIntervalSince1970, "posted": posted,
            "authorization": name(authorization), "alert": name(alert),
            "notificationCenter": name(notificationCenter),
        ]
        if let error { report["error"] = error }
        return report
    }

    static func name(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }

    static func name(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .notSupported: return "notSupported"
        case .disabled: return "disabled"
        case .enabled: return "enabled"
        @unknown default: return "unknown"
        }
    }
}


// MARK: - On the app's screen (2026-11-09, session 7)
//
// "Buzz and tone when viewing watch app, no notification." Each nudge's notification was posted
// with notifications allowed, and none was seen: the buzz and the tone were the app's own taps.
// In front, the app shows the nudge itself.

extension NudgeMessage {
    /// Whether the app shows a nudge itself: when it's in front, wrist down ("inactive") or up.
    static func showsOnScreen(appState: String) -> Bool {
        appState == "active" || appState == "inactive"
    }
}

// MARK: - What watchOS did with the notification (2026-11-09)
//
// Posted, allowed, and not seen with the app minimised. A Watch app with its iPhone app installed
// may hold a notification about 13 s for the phone's copy of it, and watchOS may list it in
// Notification Center without alerting. So each nudge's notification is watched for half a
// minute: when watchOS first offered it to the app (`willPresent`, the app in front) and with
// what, and when it first appeared in Notification Center, with the date watchOS gave it there.
// Being listed is not being shown: a banner can't be seen from here.

extension NudgeMessage {
    static let deliveryWatchWindow: TimeInterval = 30
    static let deliveryWatchInterval: TimeInterval = 1
    /// A look this late means the app was paused (a background wake ended), and its times would
    /// be wrong: the watch stops and reports nothing.
    static let deliveryWatchLateBy: TimeInterval = 3

    enum DeliveryWatchStep: Equatable { case lookAgain, report, giveUp }

    /// After each look: `elapsed` since posting, `late` past when the look was due.
    static func deliveryWatchStep(listed: Bool, elapsed: TimeInterval, late: TimeInterval) -> DeliveryWatchStep {
        if late > deliveryWatchLateBy { return .giveUp }
        if listed || elapsed >= deliveryWatchWindow { return .report }
        return .lookAgain
    }

    /// What `willPresent` answered, for the report: "banner,list", "list" or "none".
    static func name(_ options: UNNotificationPresentationOptions) -> String {
        var names: [String] = []
        if options.contains(.banner) { names.append("banner") }
        if options.contains(.list) { names.append("list") }
        return names.isEmpty ? "none" : names.joined(separator: ",")
    }

    /// Seconds after posting; nil when it didn't happen within the half minute.
    static func notificationReport(sentAt: Date, onScreen: Bool, offeredAfter: TimeInterval?,
                                   offeredAs: String?, listedAfter: TimeInterval?,
                                   datedAfter: TimeInterval?) -> [String: Any] {
        var report: [String: Any] = [
            "type": "nudgeNotification", "sentAt": sentAt.timeIntervalSince1970, "onScreen": onScreen,
        ]
        if let offeredAfter { report["offeredAfter"] = offeredAfter }
        if let offeredAs { report["offeredAs"] = offeredAs }
        if let listedAfter { report["listedAfter"] = listedAfter }
        if let datedAfter { report["datedAfter"] = datedAfter }
        return report
    }
}
