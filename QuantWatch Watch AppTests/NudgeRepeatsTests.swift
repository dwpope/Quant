import Foundation
import Testing
import WatchConnectivity
@testable import QuantWatch_Watch_App

/// A nudge shows once, however many times it arrives (2026-11-17). At 10:56 that day the phone's
/// straight send reached the Watch, then reported an error, so the phone queued the nudge too
/// (its log: "sent", then "queuedAfterFailedSend"). The Watch took both: two runs of taps, two
/// notifications. Both copies carry when the phone sent it.
struct NudgeRepeatsTests {

    private let nudge: [String: Any] = [
        "type": "nudge", "haptic": "failure", "body": "Sit up — reset your posture",
        "reason": "sustainedSlouch", "repeat": 0, "sentAt": 1_800_000_000.0,
    ]

    private func mainQueueComesRound() async {
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
    }

    @MainActor @Test func aNudgeSentAndThenQueued_showsOnce() async throws {
        let delegate = WatchSessionDelegate(activatesSession: false)
        delegate.session(WCSession.default, didReceiveMessage: nudge)
        await mainQueueComesRound()
        let shown = try #require(delegate.lastNudgeTime)

        delegate.session(WCSession.default, didReceiveUserInfo: nudge)
        await mainQueueComesRound()
        #expect(delegate.lastNudgeTime == shown, "the queued copy isn't shown again")
    }

    private let sentAt = Date(timeIntervalSince1970: 1_800_000_000)

    // `#expect` can't take a mutating call, so each answer is taken first.

    @Test func aLaterNudge_isNew() {
        var repeats = NudgeRepeats()
        let first = repeats.isNew(sentAt: sentAt)
        let later = repeats.isNew(sentAt: sentAt.addingTimeInterval(90))
        #expect(first && later)
    }

    /// A phone on an older build doesn't say when it sent a nudge: each one shows, as before.
    @Test func withoutASendingTime_eachShows() {
        var repeats = NudgeRepeats()
        let first = repeats.isNew(sentAt: nil)
        let second = repeats.isNew(sentAt: nil)
        #expect(first && second)
    }

    /// A repeat comes within a second, so only the latest few are kept.
    @Test func keepsOnlyTheLatest() {
        var repeats = NudgeRepeats()
        for i in 0...NudgeRepeats.kept { _ = repeats.isNew(sentAt: sentAt.addingTimeInterval(Double(i))) }
        let newest = repeats.isNew(sentAt: sentAt.addingTimeInterval(Double(NudgeRepeats.kept)))
        let oldest = repeats.isNew(sentAt: sentAt)
        #expect(!newest, "still kept")
        #expect(oldest, "the oldest is forgotten")
    }
}
