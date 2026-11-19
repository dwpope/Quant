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
        #expect(NudgeHaptics.pattern(reason: "sideLean", repeat: 0) == [.directionUp, .directionUp])
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

    /// The test's own clock: it holds the taps the player schedules and runs them in order,
    /// moving its time to each one's due time. Nothing waits on real time, so a slow test
    /// machine can't make a tap late (CI, 2026-11-19: `tapsOnTime_play` timed out on one).
    final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        private var jobs: [(due: Date, job: () -> Void)] = []

        func after(_ delay: TimeInterval, _ job: @escaping () -> Void) {
            jobs.append((now.addingTimeInterval(delay), job))
        }

        /// Runs every scheduled job, earliest first, including those the jobs schedule.
        func run() {
            while let next = jobs.indices.min(by: { jobs[$0].due < jobs[$1].due }) {
                let (due, job) = jobs.remove(at: next)
                now = max(now, due)
                job()
            }
        }
    }

    /// Plays `pattern` from `start` on the test's clock and returns the taps that played.
    /// `afterTap` runs after each tap, to move the clock as a suspension would.
    private func played(_ pattern: [WKHapticType], from start: Date? = nil, clock: Clock = Clock(),
                        afterTap: @escaping (Clock) -> Void = { _ in }) -> [WKHapticType] {
        var played: [WKHapticType] = []
        NudgeHaptics.play(pattern, from: start ?? clock.now, now: { clock.now }, after: clock.after,
                          tap: { played.append($0); afterTap(clock) })
        clock.run()
        return played
    }

    /// Taps late by more than `playsUpTo` don't play: the app was suspended with them still to
    /// come, as when a background wake ends, and was resumed later. A nudge's taps then would
    /// be for a nudge long gone.
    @Test func lateTaps_dontPlay() {
        let clock = Clock()
        #expect(played([.click, .click], from: clock.now.addingTimeInterval(-60), clock: clock).isEmpty)
    }

    /// A tap just inside `playsUpTo` still plays.
    @Test func slightlyLateTaps_play() {
        let clock = Clock()
        let start = clock.now.addingTimeInterval(-NudgeHaptics.playsUpTo)
        #expect(played([.click], from: start, clock: clock) == [.click])
    }

    /// On time, each tap plays when it's due, `spacing` apart.
    @Test func tapsOnTime_play() {
        let clock = Clock()
        let start = clock.now
        var times: [TimeInterval] = []
        let taps = played([.directionUp, .click], clock: clock) { times.append($0.now.timeIntervalSince(start)) }
        #expect(taps == [.directionUp, .click])
        #expect(times == [0, NudgeHaptics.spacing])
    }

    /// Suspended partway through, the rest of the run is dropped, not played late.
    @Test func suspendedPartway_theRestIsDropped() {
        let taps = played([.directionUp, .directionUp, .directionUp]) { clock in
            clock.now += 30  // suspended for half a minute after the first tap
        }
        #expect(taps == [.directionUp])
    }

    /// The screen's "last nudge" time is when it arrived, not when the main queue got to it.
    @MainActor @Test func theLastNudge_isWhenItArrived() {
        let delegate = WatchSessionDelegate(activatesSession: false)
        let arrived = Date().addingTimeInterval(-120)
        delegate.showNudge(.notification, body: "Sit up — reset your posture", arrivedAt: arrived)
        #expect(delegate.lastNudgeTime == arrived)
    }
}

