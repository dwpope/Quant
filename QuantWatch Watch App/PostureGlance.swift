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

    /// The phone's posture states, and `paused` when its camera has stopped (2026-10-16).
    enum State: String {
        case good, drifting, bad, absent, calibrating, paused
    }

    let state: State
    /// When the slouch began: drifting and bad only.
    let since: Date?
    /// When the head turned, or nil when it isn't turned.
    let headTurnedSince: Date?
    /// When the next nudge is due, or nil when none is coming (2026-10-13).
    let nudgeAt: Date?

    init?(message: [String: Any]) {
        guard message["type"] as? String == "posture",
              let raw = message["state"] as? String, let state = State(rawValue: raw)
        else { return nil }
        self.state = state
        since = (message["since"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        headTurnedSince = (message["headTurned"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue) }
        nudgeAt = (message["nudgeAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
    }

    /// The phone resends every 15 s. With nothing for three of those it has stopped (Aware closed
    /// on the phone, or the phone out of range), and its last word is no longer now.
    static let staleAfter: TimeInterval = 45
}

/// What the top of the screen shows.
enum PostureLook: Equatable {
    case sittingWell
    /// `sustained` once it has gone on long enough to be nudged (the phone's "bad"). `nudgeAt`,
    /// when the nudge is due, if one is coming.
    case slouching(since: Date?, sustained: Bool, nudgeAt: Date? = nil)
    case headTurned(since: Date, nudgeAt: Date? = nil)
    case notInView
    case calibrating
    /// The phone's camera has stopped: too hot, interrupted, or a replay over (2026-10-16).
    case cameraPaused
    /// Nothing from the phone yet, or nothing lately.
    case waitingForPhone

    init(_ glance: PostureGlance?, receivedAt: Date?, now: Date) {
        guard let glance, let receivedAt,
              now.timeIntervalSince(receivedAt) <= PostureGlance.staleAfter
        else { self = .waitingForPhone; return }
        switch glance.state {
        case .calibrating: self = .calibrating
        case .paused: self = .cameraPaused
        case .absent: self = .notInView
        case .drifting: self = .slouching(since: glance.since, sustained: false, nudgeAt: glance.nudgeAt)
        case .bad: self = .slouching(since: glance.since, sustained: true, nudgeAt: glance.nudgeAt)
        case .good:
            if let turned = glance.headTurnedSince {
                self = .headTurned(since: turned, nudgeAt: glance.nudgeAt)
            } else {
                self = .sittingWell
            }
        }
    }

    /// In the phone's words, the same on its card and timeline (2026-10-16).
    var headline: String {
        switch self {
        case .sittingWell: return "Sitting well"
        case .slouching(_, let sustained, _): return sustained ? "Still slouching" : "Slouching"
        case .headTurned: return "Head turned"
        case .notInView: return "Away"
        case .calibrating: return "Calibrating"
        case .cameraPaused: return "Camera paused"
        case .waitingForPhone: return "Waiting for iPhone"
        }
    }

    /// The countdown under the headline (2026-10-13).
    enum Countdown: Equatable {
        /// Counting down to the nudge.
        case until(Date)
        /// Due now: the phone fires on its next frame.
        case due
    }

    /// The countdown to the nudge, or nil with none coming (sitting well, away, silenced).
    func countdown(now: Date) -> Countdown? {
        let nudgeAt: Date?
        switch self {
        case .slouching(_, _, let at): nudgeAt = at
        case .headTurned(_, let at): nudgeAt = at
        default: nudgeAt = nil
        }
        guard let nudgeAt else { return nil }
        return nudgeAt > now ? .until(nudgeAt) : .due
    }
}
