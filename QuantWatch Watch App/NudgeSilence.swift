//
//  NudgeSilence.swift
//  QuantWatch Watch App
//
//  Silencing nudges from the wrist.
//

import Foundation

/// Silencing nudges for a while. The phone decides every nudge, so the Watch asks it to, and the
/// phone answers with when the silence ends. The phone's `WatchConnectivityService` reads and
/// writes the other side of these messages.
enum NudgeSilence {

    struct Option: Equatable {
        let minutes: Int
        let label: String
    }

    static let options = [
        Option(minutes: 30, label: "30 min"),
        Option(minutes: 60, label: "1 hour"),
        Option(minutes: 120, label: "2 hours"),
    ]

    /// Asks the phone to silence nudges for `minutes`, or 0 to resume them.
    static func request(minutes: Int) -> [String: Any] {
        ["type": "silenceNudges", "minutes": minutes]
    }

    /// When the phone says the silence ends, or nil when nudges aren't silenced.
    static func until(from message: [String: Any]) -> Date? {
        guard message["type"] as? String == "nudgeSilence",
              let seconds = (message["until"] as? NSNumber)?.doubleValue, seconds > 0
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func isSilenced(until: Date?, now: Date) -> Bool {
        guard let until else { return false }
        return now < until
    }
}
