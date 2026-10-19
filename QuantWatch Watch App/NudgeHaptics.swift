//
//  NudgeHaptics.swift
//  QuantWatch Watch App
//
//  A nudge's own taps.
//

import Foundation
import WatchKit

/// A nudge's own taps, so it feels different from a notification (2026-10-13).
///
/// watchOS plays only its built-in taps (no custom haptics as on the iPhone), so a nudge is a
/// short run of them: rising taps for a slouch ("sit up"), one more each time it's repeated
/// uncorrected, up to four; three clicks for a head held turned. Played only while the app runs,
/// which the wrist session keeps it doing; a closed app's nudge arrives as a notification, which
/// plays the system's tap.
enum NudgeHaptics {

    /// Seconds between taps: closer, and watchOS runs them together or drops some.
    static let spacing: TimeInterval = 0.5

    /// The taps for a nudge, or nil when the phone didn't say why (an older phone build): then
    /// the single tap it names plays, as before.
    static func pattern(reason: String?, repeat repeatCount: Int) -> [WKHapticType]? {
        switch reason {
        case "forwardCreep", "headDrop", "sink", "sustainedSlouch":
            return Array(repeating: .directionUp, count: min(2 + max(0, repeatCount), 4))
        case "headTurned":
            return [.click, .click, .click]
        default:
            return nil
        }
    }

    /// A tap more than this late doesn't play, nor do the rest of its run (2026-10-16 audit).
    /// The app was suspended with taps still to come, as when a background wake ends, and
    /// resumed later: taps then would be for a nudge long gone, and a run cut short would
    /// say a different repeat.
    static let playsUpTo: TimeInterval = 1

    /// Plays the taps, `spacing` apart, from `start` (when the nudge arrived).
    static func play(_ pattern: [WKHapticType], from start: Date = Date(),
                     now: @escaping () -> Date = Date.init,
                     tap: @escaping (WKHapticType) -> Void = { WKInterfaceDevice.current().play($0) }) {
        guard let first = pattern.first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, start.timeIntervalSince(now()))) {
            let playedAt = now()
            guard playedAt.timeIntervalSince(start) <= playsUpTo else { return }
            play(Array(pattern.dropFirst()), from: playedAt.addingTimeInterval(spacing), now: now, tap: tap)
            tap(first)
        }
    }
}
