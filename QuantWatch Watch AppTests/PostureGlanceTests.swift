import Foundation
import Testing
@testable import QuantWatch_Watch_App

/// Slouching or not, at the top of the Watch screen (2026-10-11).
///
/// The dictionaries here are the golden copies the phone's `PostureGlanceTests` asserts.
struct PostureGlanceTests {

    private let start = Date(timeIntervalSince1970: 1_791_640_000)

    // MARK: - Reading the phone's message

    @Test func readsSittingWell() throws {
        let glance = try #require(PostureGlance(message: ["type": "posture", "state": "good"]))
        #expect(glance.state == .good)
        #expect(glance.since == nil)
        #expect(glance.headTurnedSince == nil)
    }

    @Test func readsASlouch_andSinceWhen() throws {
        let drifting = try #require(PostureGlance(
            message: ["type": "posture", "state": "drifting", "since": 1_791_640_000.0]))
        #expect(drifting.state == .drifting)
        #expect(drifting.since == start)
        let bad = try #require(PostureGlance(
            message: ["type": "posture", "state": "bad", "since": 1_791_640_000.0]))
        #expect(bad.state == .bad)
    }

    @Test func readsAHeadTurned() throws {
        let glance = try #require(PostureGlance(
            message: ["type": "posture", "state": "good", "headTurned": 1_791_640_000.0]))
        #expect(glance.headTurnedSince == start)
    }

    @Test func readsAwayAndCalibrating() {
        #expect(PostureGlance(message: ["type": "posture", "state": "absent"])?.state == .absent)
        #expect(PostureGlance(message: ["type": "posture", "state": "calibrating"])?.state == .calibrating)
    }

    @Test func ignoresAnythingElse() {
        #expect(PostureGlance(message: ["type": "nudge", "state": "good"]) == nil)
        #expect(PostureGlance(message: ["type": "posture", "state": "sideways"]) == nil)
        #expect(PostureGlance(message: ["type": "posture"]) == nil)
    }

    // MARK: - What the screen shows

    private func look(_ message: [String: Any]?, receivedSecondsAgo: TimeInterval = 1) -> PostureLook {
        let now = start.addingTimeInterval(100)
        return PostureLook(message.flatMap(PostureGlance.init(message:)),
                           receivedAt: now.addingTimeInterval(-receivedSecondsAgo), now: now)
    }

    @Test func sittingWell() {
        #expect(look(["type": "posture", "state": "good"]) == .sittingWell)
        #expect(PostureLook.sittingWell.headline == "Sitting well")
    }

    /// Drifting and bad are both slouching; bad is the one long enough to nudge.
    @Test func slouching() {
        #expect(look(["type": "posture", "state": "drifting", "since": 1_791_640_000.0])
                == .slouching(since: start, sustained: false))
        #expect(look(["type": "posture", "state": "bad", "since": 1_791_640_000.0])
                == .slouching(since: start, sustained: true))
        #expect(PostureLook.slouching(since: start, sustained: false).headline == "Slouching")
    }

    @Test func headTurned() {
        #expect(look(["type": "posture", "state": "good", "headTurned": 1_791_640_000.0])
                == .headTurned(since: start))
        #expect(PostureLook.headTurned(since: start).headline == "Head turned")
    }

    /// A slouch is what gets nudged first, so it's what's shown.
    @Test func aSlouch_outranksAHeadTurned() {
        #expect(look(["type": "posture", "state": "drifting", "since": 1_791_640_000.0,
                      "headTurned": 1_791_640_000.0])
                == .slouching(since: start, sustained: false))
    }

    @Test func notInView() {
        #expect(look(["type": "posture", "state": "absent", "headTurned": 1_791_640_000.0]) == .notInView)
        #expect(PostureLook.notInView.headline == "Not in view")
    }

    @Test func calibrating() {
        #expect(look(["type": "posture", "state": "calibrating"]) == .calibrating)
        #expect(PostureLook.calibrating.headline == "Calibrating")
    }

    @Test func beforeThePhoneSaysAnything() {
        #expect(PostureLook(nil, receivedAt: nil, now: start) == .waitingForPhone)
        #expect(PostureLook.waitingForPhone.headline == "Waiting for iPhone")
    }

    /// The phone resends every 15 s. Three missed and it has stopped (Aware closed on the phone,
    /// or out of range), so the last posture it sent isn't shown as if it were now.
    @Test func whenThePhoneHasGoneQuiet() {
        #expect(look(["type": "posture", "state": "good"], receivedSecondsAgo: 44) == .sittingWell)
        #expect(look(["type": "posture", "state": "good"], receivedSecondsAgo: 46) == .waitingForPhone)
        #expect(PostureGlance.staleAfter == 45)
    }

    // MARK: - The countdown to the nudge (2026-10-13)

    @Test func readsWhenTheNudgeIsDue() throws {
        let glance = try #require(PostureGlance(message: [
            "type": "posture", "state": "drifting", "since": 1_791_640_000.0, "nudgeAt": 1_791_640_060.0]))
        #expect(glance.nudgeAt == start.addingTimeInterval(60))
        #expect(look(["type": "posture", "state": "drifting", "since": 1_791_640_000.0,
                      "nudgeAt": 1_791_640_160.0])
                == .slouching(since: start, sustained: false, nudgeAt: start.addingTimeInterval(160)))
        #expect(look(["type": "posture", "state": "good", "headTurned": 1_791_640_000.0,
                      "nudgeAt": 1_791_640_300.0])
                == .headTurned(since: start, nudgeAt: start.addingTimeInterval(300)))
    }

    /// Counts down to the nudge; once it's due, says so rather than counting below zero; with
    /// nothing coming (silenced), says nothing.
    @Test func theCountdownLine() {
        let now = start.addingTimeInterval(100)
        let coming = PostureLook.slouching(since: start, sustained: false, nudgeAt: now.addingTimeInterval(42))
        #expect(coming.countdown(now: now) == .until(now.addingTimeInterval(42)))
        let due = PostureLook.slouching(since: start, sustained: true, nudgeAt: now)
        #expect(due.countdown(now: now) == .due)
        #expect(PostureLook.slouching(since: start, sustained: true).countdown(now: now) == nil)
        #expect(PostureLook.sittingWell.countdown(now: now) == nil)
    }
}
