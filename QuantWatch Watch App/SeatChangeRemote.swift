//
//  SeatChangeRemote.swift
//  QuantWatch Watch App
//
//  The "Moved your seat?" question on the wrist, answered with Recalibrate or Dismiss.
//

import Foundation
import UserNotifications

/// The seat-change question from the phone, and the Watch's answer (2026-11-23). The phone's
/// `WatchConnectivityService` reads and writes the other side of these messages. `id` is the
/// phone's suggestion time, which says which question an answer is for.
enum SeatChangeRemote {

    static let categoryIdentifier = "seatChange"
    static let notificationIdentifier = "seat-question"
    static let title = "Moved your seat?"
    static let recalibrateAction = "recalibrate"
    static let dismissAction = "dismiss"

    /// The question's notification category, with its two buttons. Neither opens the app: the
    /// answer goes to the phone from the notification.
    static var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [
                UNNotificationAction(identifier: recalibrateAction, title: "Recalibrate", options: []),
                UNNotificationAction(identifier: dismissAction, title: "Dismiss", options: []),
            ],
            intentIdentifiers: [], options: [])
    }

    /// Whether the phone says the question is open (true) or closed, and which one, or nil when the
    /// message isn't the phone's question.
    static func question(from message: [String: Any]) -> (open: Bool, id: TimeInterval)? {
        guard message["type"] as? String == "seatQuestion",
              let open = message["open"] as? Bool,
              let id = (message["id"] as? NSNumber)?.doubleValue
        else { return nil }
        return (open, id)
    }

    /// The questions the phone has closed, so a queued open that arrives after its close (the
    /// queue and the live message don't keep order together) posts nothing. Only the recent
    /// ones are kept.
    struct ClosedQuestions {
        private var ids: [TimeInterval] = []
        private static let kept = 8

        mutating func noteClosed(_ id: TimeInterval) {
            guard !ids.contains(id) else { return }
            ids.append(id)
            if ids.count > Self.kept { ids.removeFirst(ids.count - Self.kept) }
        }

        func isClosed(_ id: TimeInterval) -> Bool { ids.contains(id) }
    }

    /// The answer to send for a notification action, or nil for any other (a plain tap sends
    /// nothing).
    static func seatAnswer(forAction identifier: String) -> String? {
        switch identifier {
        case recalibrateAction: return "recalibrate"
        case dismissAction: return "dismiss"
        default: return nil
        }
    }

    /// The answer to the phone.
    static func answerMessage(_ answer: String, id: TimeInterval) -> [String: Any] {
        ["type": "seatAnswer", "answer": answer, "id": id]
    }
}
