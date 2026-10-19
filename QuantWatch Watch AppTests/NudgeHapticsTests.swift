import Foundation
import Testing
import WatchKit
@testable import QuantWatch_Watch_App

/// A nudge's own taps, not a notification's (2026-10-13).
///
/// Dave asked for the nudge to feel different from a regular notification. The Watch can only
/// play Apple's built-in taps, so a nudge is a short run of them: rising taps for a slouch, more
/// of them each time it's repeated uncorrected, and clicks for a head held turned. Only while
/// the app is running (the wrist session keeps it so); closed, the notification's own tap plays.
struct NudgeHapticsTests {

    @Test func aSlouch_risingTaps_moreAsItRepeats() {
        #expect(NudgeHaptics.pattern(reason: "headDrop", repeat: 0) == [.directionUp, .directionUp])
        #expect(NudgeHaptics.pattern(reason: "forwardCreep", repeat: 1)
                == [.directionUp, .directionUp, .directionUp])
        #expect(NudgeHaptics.pattern(reason: "sink", repeat: 2)?.count == 4)
        #expect(NudgeHaptics.pattern(reason: "sustainedSlouch", repeat: 9)?.count == 4, "capped")
    }

    @Test func aHeadTurn_clicks() {
        #expect(NudgeHaptics.pattern(reason: "headTurned", repeat: 0) == [.click, .click, .click])
    }

    /// A phone on an older build sends no reason: the single tap it names plays, as before.
    @Test func noReason_noPattern() {
        #expect(NudgeHaptics.pattern(reason: nil, repeat: 0) == nil)
        #expect(NudgeHaptics.pattern(reason: "somethingNew", repeat: 0) == nil)
    }

    /// The phone's message (golden copy of the phone's `HeadTurnNudgeTests`).
    @Test func readsTheReasonAndRepeat() {
        let message: [String: Any] = ["type": "nudge", "haptic": "failure",
                                      "body": "Lift your head — ease your neck back",
                                      "reason": "headDrop", "repeat": 2]
        #expect(NudgeMessage.reason(from: message) == "headDrop")
        #expect(NudgeMessage.repeatCount(from: message) == 2)
        #expect(NudgeMessage.repeatCount(from: ["type": "nudge"]) == 0)
    }

    /// Taps closer than this run together.
    @Test func spacing() {
        #expect(NudgeHaptics.spacing >= 0.4)
    }

    // MARK: - Late taps (2026-10-16 audit)

    /// A clock the test moves, standing in for time passing while the app is suspended.
    final class Clock {
        var now = Date()
    }

    /// Taps late by more than `playsUpTo` don't play: the app was suspended with them still to
    /// come, as when a background wake ends, and was resumed later. A nudge's taps then would
    /// be for a nudge long gone.
    @MainActor @Test func lateTaps_dontPlay() async throws {
        var played: [WKHapticType] = []
        NudgeHaptics.play([.click, .click], from: Date().addingTimeInterval(-60), tap: { played.append($0) })
        try await Task.sleep(for: .seconds(1))
        #expect(played.isEmpty)
    }

    @MainActor @Test func tapsOnTime_play() async throws {
        var played: [WKHapticType] = []
        NudgeHaptics.play([.directionUp, .click], tap: { played.append($0) })
        try await Task.sleep(for: .seconds(1.5))
        #expect(played == [.directionUp, .click])
    }

    /// Suspended partway through, the rest of the run is dropped, not played late.
    @MainActor @Test func suspendedPartway_theRestIsDropped() async throws {
        let clock = Clock()
        var played: [WKHapticType] = []
        NudgeHaptics.play([.directionUp, .directionUp, .directionUp], from: clock.now,
                          now: { clock.now }, tap: { tap in
            played.append(tap)
            clock.now += 30  // suspended for half a minute after the first tap
        })
        try await Task.sleep(for: .seconds(1.5))
        #expect(played == [.directionUp])
    }

    /// The screen's "last nudge" time is when it arrived, not when the main queue got to it.
    @MainActor @Test func theLastNudge_isWhenItArrived() {
        let delegate = WatchSessionDelegate(activatesSession: false)
        let arrived = Date().addingTimeInterval(-120)
        delegate.showNudge(.notification, body: "Sit up — reset your posture", arrivedAt: arrived)
        #expect(delegate.lastNudgeTime == arrived)
    }
}

