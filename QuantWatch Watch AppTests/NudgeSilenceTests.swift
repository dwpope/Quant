import Foundation
import Testing
@testable import QuantWatch_Watch_App

/// Silencing nudges from the wrist. The phone decides every nudge, so the Watch asks it, and the
/// phone says when the silence ends. The dictionaries are the golden copies the phone's
/// `NudgeSilenceAppTests` assert.
struct NudgeSilenceTests {

    @Test func asksThePhoneForASilence() {
        #expect(NudgeSilence.request(minutes: 30) as NSDictionary
                == ["type": "silenceNudges", "minutes": 30] as NSDictionary)
    }

    @Test func resumingIsASilenceOfZero() {
        #expect(NudgeSilence.request(minutes: 0) as NSDictionary
                == ["type": "silenceNudges", "minutes": 0] as NSDictionary)
    }

    @Test func readsWhenThePhoneSaysItEnds() {
        let until = NudgeSilence.until(from: ["type": "nudgeSilence", "until": 1_800_000_000.0])
        #expect(until == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func zeroMeansNotSilenced() {
        #expect(NudgeSilence.until(from: ["type": "nudgeSilence", "until": 0.0]) == nil)
    }

    @Test func offersHalfAnHourToTwoHours() {
        #expect(NudgeSilence.options.map(\.minutes) == [30, 60, 120])
        #expect(NudgeSilence.options.map(\.label) == ["30 min", "1 hour", "2 hours"])
    }

    /// The phone's answer may arrive after the silence ended; the screen shouldn't say silenced.
    @Test func isSilenced_onlyBeforeItEnds() {
        let now = Date()
        #expect(NudgeSilence.isSilenced(until: now.addingTimeInterval(60), now: now))
        #expect(!NudgeSilence.isSilenced(until: now.addingTimeInterval(-1), now: now))
        #expect(!NudgeSilence.isSilenced(until: nil, now: now))
    }
}
