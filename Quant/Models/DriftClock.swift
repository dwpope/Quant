import Foundation
import PostureLogic

/// How long the thresholds have been drifting or bad, on the clock the state was stamped with.
///
/// `PostureState.drifting(since:)` and `.bad(since:)` hold the camera frame's timestamp. Until
/// 2026-10-05 that counted seconds since the device booted, not since 1970. The phone's panel
/// and the Watch subtracted it from the calendar clock, so in the first device session
/// (2026-09-29) the drift timer read about 56 years. Live frames are on the calendar clock now
/// (`FrameClock`), but a replayed recording keeps its own clock, so elapsed time still comes from
/// another frame timestamp.
enum DriftClock {

    /// Seconds in the current drifting or bad state, or nil for states without a start or when
    /// there is no frame to measure against. Never negative: a replay or a restarted session can
    /// hand a frame time earlier than the state's start.
    static func elapsed(_ state: PostureState, frameNow: TimeInterval?) -> TimeInterval? {
        guard let frameNow else { return nil }
        switch state {
        case .drifting(let since), .bad(let since):
            return max(0, frameNow - since)
        case .absent, .calibrating, .good:
            return nil
        }
    }

    /// When the current drifting or bad state began, as a calendar time, for a display that
    /// counts up from a date, such as the Watch's.
    static func wallClockStart(_ state: PostureState, frameNow: TimeInterval?,
                               wallNow: Date = Date()) -> Date? {
        elapsed(state, frameNow: frameNow).map { wallNow.addingTimeInterval(-$0) }
    }
}
