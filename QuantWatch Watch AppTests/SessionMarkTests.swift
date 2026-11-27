import Foundation
import Testing
@testable import QuantWatch_Watch_App

/// Marking moments of a session from the wrist (2026-11-27): looking down, craning, a moved seat,
/// a yawn, feeling sluggish, or sitting well, so the log says when instead of Dave remembering.
/// The dictionaries are the golden copies the phone's `SessionMarkAppTests` assert.
struct SessionMarkTests {

    @Test func theMessageCarriesWhatAndTheTapTime() {
        let at = Date(timeIntervalSince1970: 1_795_770_000.25)
        #expect(SessionMark.message(.craning, at: at) as NSDictionary
                == ["type": "mark", "what": "craning", "at": 1_795_770_000.25] as NSDictionary)
    }

    @Test func sixMarks_withTheNamesThePhoneKnows() {
        #expect(SessionMark.allCases.map(\.rawValue)
                == ["lookingDown", "craning", "movedSeat", "yawning", "sluggish", "sittingWell"])
    }

    @Test func eachTileHasAShortWord_andAnIcon() {
        #expect(SessionMark.allCases.map(\.title) == ["Down", "Crane", "Seat", "Yawn", "Tired", "Good"])
        #expect(Set(SessionMark.allCases.map(\.symbol)).count == 6)
    }
}
