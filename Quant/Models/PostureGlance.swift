import Foundation
import PostureLogic

/// Your posture on the Watch: slouching or not, and for how long (2026-10-11).
///
/// Sent while the Watch app is open: when the posture changes, and every 15 s while it doesn't,
/// so the Watch can tell a phone that has stopped sending (Aware closed, or out of range) from a
/// posture that's held. The Watch's `PostureGlance` reads it. The two targets share no code, so
/// the dictionaries in `PostureGlanceTests` are golden copies, asserted from each side.
struct PostureGlance: Equatable {
    /// "good", "drifting", "bad", "absent", "calibrating", or "paused" with the camera stopped.
    let state: String
    /// When the slouch began, calendar seconds: drifting and bad only.
    let since: Double?
    /// When the head turned, calendar seconds, or nil when it isn't turned.
    let headTurnedSince: Double?
    /// When the next nudge is due, calendar seconds, for the Watch's countdown (2026-10-13):
    /// while slouching or with the head turned, and only when one is coming.
    let nudgeAt: Double?

    /// Times in whole seconds, so a glance checked once a second doesn't differ only by frame
    /// jitter.
    init(state: PostureState, since: Date?, headTurnedSince: Date?, nudgeAt: Date? = nil) {
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
        // Only what the Watch counts down beside: a slouch, or a head turned while sitting well.
        let countsDown: Bool
        switch state {
        case .drifting, .bad: countsDown = true
        case .good: countsDown = headTurnedSince != nil
        case .absent, .calibrating: countsDown = false
        }
        self.nudgeAt = countsDown ? nudgeAt?.timeIntervalSince1970.rounded() : nil
    }

    private init(state: String, since: Double?, headTurnedSince: Double?, nudgeAt: Double?) {
        self.state = state
        self.since = since
        self.headTurnedSince = headTurnedSince
        self.nudgeAt = nudgeAt
    }

    /// This glance with the last sent one's times where they differ by a second or less
    /// (2026-10-11). A start is worked out afresh each second from the frame clock, and its
    /// rounding can flip between neighbouring seconds, which sent a glance every second and
    /// made the Watch's timer jump back and forth. The Watch only shows the head turn while
    /// sitting well, so it isn't sent while slouching either. The nudge's due time is held the
    /// same way (2026-10-13); a pause in the slouch moves it further, and that is sent.
    func steadied(against last: PostureGlance?) -> PostureGlance {
        func hold(_ new: Double?, _ old: Double?) -> Double? {
            guard let new, let old, abs(new - old) <= 1 else { return new }
            return old
        }
        let sameState = last?.state == state
        let turned = state == "good" ? headTurnedSince : nil
        return PostureGlance(
            state: state,
            since: sameState ? hold(since, last?.since) : since,
            headTurnedSince: hold(turned, last?.headTurnedSince),
            nudgeAt: hold(nudgeAt, last?.nudgeAt))
    }

    var message: [String: Any] {
        var m: [String: Any] = ["type": "posture", "state": state]
        if let since { m["since"] = since }
        if let headTurnedSince { m["headTurned"] = headTurnedSince }
        if let nudgeAt { m["nudgeAt"] = nudgeAt }
        return m
    }

    /// The camera has stopped: no frame for `framesStopAfter` (2026-10-16).
    static let paused = PostureGlance(state: "paused", since: nil, headTurnedSince: nil, nudgeAt: nil)

    /// No frame judged for this long and the camera has stopped. Frames are judged about ten
    /// times a second, and a few a second when the phone is hot.
    static let framesStopAfter: TimeInterval = 5

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
