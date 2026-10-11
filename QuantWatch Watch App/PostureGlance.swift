//
//  PostureGlance.swift
//  QuantWatch Watch App
//
//  Slouching or not, at the top of the screen.
//

import Foundation

/// Your posture as the phone last reported it (2026-10-11).
///
/// The phone's `PostureGlance` writes the message while this app is open: when the posture
/// changes, and every 15 s while it doesn't. The two targets share no code, so each side's
/// `PostureGlanceTests` asserts the same dictionaries.
struct PostureGlance: Equatable {

    /// The phone's posture states.
    enum State: String {
        case good, drifting, bad, absent, calibrating
    }

    let state: State
    /// When the slouch began: drifting and bad only.
    let since: Date?
    /// When the head turned, or nil when it isn't turned.
    let headTurnedSince: Date?

    init?(message: [String: Any]) {
        guard message["type"] as? String == "posture",
              let raw = message["state"] as? String, let state = State(rawValue: raw)
        else { return nil }
        self.state = state
        since = (message["since"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        headTurnedSince = (message["headTurned"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue) }
    }

    /// The phone resends every 15 s. With nothing for three of those it has stopped (Aware closed
    /// on the phone, or the phone out of range), and its last word is no longer now.
    static let staleAfter: TimeInterval = 45
}

/// What the top of the screen shows.
enum PostureLook: Equatable {
    case sittingWell
    /// `sustained` once it has gone on long enough to be nudged (the phone's "bad").
    case slouching(since: Date?, sustained: Bool)
    case headTurned(since: Date)
    case notInView
    case calibrating
    /// Nothing from the phone yet, or nothing lately.
    case waitingForPhone

    init(_ glance: PostureGlance?, receivedAt: Date?, now: Date) {
        guard let glance, let receivedAt,
              now.timeIntervalSince(receivedAt) <= PostureGlance.staleAfter
        else { self = .waitingForPhone; return }
        switch glance.state {
        case .calibrating: self = .calibrating
        case .absent: self = .notInView
        case .drifting: self = .slouching(since: glance.since, sustained: false)
        case .bad: self = .slouching(since: glance.since, sustained: true)
        case .good:
            if let turned = glance.headTurnedSince {
                self = .headTurned(since: turned)
            } else {
                self = .sittingWell
            }
        }
    }

    var headline: String {
        switch self {
        case .sittingWell: return "Sitting well"
        case .slouching: return "Slouching"
        case .headTurned: return "Head turned"
        case .notInView: return "Not in view"
        case .calibrating: return "Calibrating"
        case .waitingForPhone: return "Waiting for iPhone"
        }
    }
}
