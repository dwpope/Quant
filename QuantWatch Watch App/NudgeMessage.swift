//
//  NudgeMessage.swift
//  QuantWatch Watch App
//
//  What a nudge says on the wrist.
//

import Foundation
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
