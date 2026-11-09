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

    static func notificationContent(body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notificationTitle
        content.body = body
        content.sound = .default
        return content
    }

    /// With the app open: a nudge shows as a banner, without a sound because the app has already
    /// buzzed. The app posts nothing else; anything else stays hidden, as before.
    static func presentationOptions(forIdentifier identifier: String) -> UNNotificationPresentationOptions {
        identifier.hasPrefix(identifierPrefix) ? [.banner, .list] : []
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
