import Foundation
import PostureLogic

/// Which slouch the posture card says how to fix, held steady (2026-11-09).
///
/// The reason is the nudge's: the one the engine counts down to, from the signals the posture
/// engine counted, so the card and the Watch use the same words. In session 7 it swapped between
/// head drop and forward creep every few seconds while one slouch went on (16:43:45 to 16:44:36),
/// and the engine names none while a cooldown or poor tracking holds the nudge back. So the line
/// keeps its reason while the engine names none, follows a different one only once the engine
/// has named nothing else for `takesOverAfter`, and takes a nudge's own reason at once, so it
/// says what the Watch just said. Sitting up briefly keeps it, as the engine keeps the slouch's
/// episode: in session 7 a two-second sit-up (16:51:46) was followed by a slouch the cooldown held
/// back, and the line would have fallen back to the general one. Pure.
nonisolated struct SlouchCoaching {

    /// How long a different reason must last before the line follows it.
    static let takesOverAfter: TimeInterval = 10

    /// How long sitting well keeps the last slouch's reason: the nudge engine's own slouch
    /// episode ends after this much good posture.
    static let keptThroughSittingUp: TimeInterval = 30

    /// The slouch to coach, or nil when none is going on.
    private(set) var reason: NudgeReason?

    /// A different reason, and since when it has been the engine's.
    private var contender: (reason: NudgeReason, since: TimeInterval)?

    /// When you sat up from the slouch, while you're sitting well.
    private var sittingUpSince: TimeInterval?

    /// Each frame's posture and nudge decision. `now` is in seconds, on any one clock.
    mutating func update(state: PostureState, decision: NudgeDecision, now: TimeInterval) {
        switch state {
        case .drifting, .bad:
            sittingUpSince = nil
        case .good:
            contender = nil
            let since = sittingUpSince ?? now
            sittingUpSince = since
            if now - since >= Self.keptThroughSittingUp { reason = nil }
            return
        case .absent, .calibrating:
            // Left the desk, or starting again: the slouch is over.
            reason = nil
            contender = nil
            sittingUpSince = nil
            return
        }
        switch decision {
        case .fire(let fired) where fired != .headTurned:
            reason = fired
            contender = nil
        case .pending(let pending, _) where pending != .headTurned:
            follow(pending, now: now)
        default:
            // Held back, or a head turn's countdown: no word on the slouch, so the line stays.
            break
        }
    }

    private mutating func follow(_ candidate: NudgeReason, now: TimeInterval) {
        guard let shown = reason else {
            reason = candidate
            return
        }
        if candidate == shown {
            contender = nil
        } else if let contender, contender.reason == candidate {
            if now - contender.since >= Self.takesOverAfter {
                reason = candidate
                self.contender = nil
            }
        } else {
            contender = (candidate, now)
        }
    }
}
