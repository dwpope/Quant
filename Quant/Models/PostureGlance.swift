import Foundation
import PostureLogic

/// Your posture on the Watch: slouching or not, and for how long (2026-10-11).
///
/// Sent while the Watch app is open: when the posture changes, and every 15 s while it doesn't,
/// so the Watch can tell a phone that has stopped sending (Aware closed, or out of range) from a
/// posture that's held. The Watch's `PostureGlance` reads it. The two targets share no code, so
/// the dictionaries in `PostureGlanceTests` are golden copies, asserted from each side.
struct PostureGlance: Equatable {
    /// "good", "drifting", "bad", "absent" or "calibrating".
    let state: String
    /// When the slouch began, calendar seconds: drifting and bad only.
    let since: Double?
    /// When the head turned, calendar seconds, or nil when it isn't turned.
    let headTurnedSince: Double?

    /// Times in whole seconds, so a glance checked once a second doesn't differ only by frame
    /// jitter.
    init(state: PostureState, since: Date?, headTurnedSince: Date?) {
        switch state {
        case .absent: self.state = "absent"
        case .calibrating: self.state = "calibrating"
        case .good: self.state = "good"
        case .drifting: self.state = "drifting"
        case .bad: self.state = "bad"
        }
        switch state {
        case .drifting, .bad: self.since = since?.timeIntervalSince1970.rounded()
        case .absent, .calibrating, .good: self.since = nil
        }
        self.headTurnedSince = headTurnedSince?.timeIntervalSince1970.rounded()
    }

    var message: [String: Any] {
        var m: [String: Any] = ["type": "posture", "state": state]
        if let since { m["since"] = since }
        if let headTurnedSince { m["headTurned"] = headTurnedSince }
        return m
    }

    /// Sent again this often while nothing changes. The Watch takes three missed to mean the
    /// phone has stopped.
    static let resendEvery: TimeInterval = 15

    /// Whether `glance` should go, given the last one sent and when.
    static func isDue(_ glance: PostureGlance, lastSent: PostureGlance?, sentAt: Date?,
                      now: Date) -> Bool {
        guard let lastSent, let sentAt else { return true }
        return glance != lastSent || now.timeIntervalSince(sentAt) >= resendEvery
    }
}
