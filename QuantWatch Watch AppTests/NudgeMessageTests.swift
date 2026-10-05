import Foundation
import Testing
@testable import QuantWatch_Watch_App

/// What the Watch shows for a nudge. The phone now sends its reason's coaching line; the
/// dictionaries here are the golden copies the phone's `HeadTurnNudgeTests` assert.
struct NudgeMessageTests {

    @Test func showsTheCoachingLineThePhoneSent() {
        let message: [String: Any] = [
            "type": "nudge", "haptic": "failure", "body": "Turn your chair to face that screen",
        ]
        #expect(NudgeMessage.body(from: message) == "Turn your chair to face that screen")
    }

    /// A phone on an older build sends no line.
    @Test func withoutALine_saysWhatItAlwaysSaid() {
        #expect(NudgeMessage.body(from: ["type": "nudge", "haptic": "failure"]) == "Straighten up!")
        #expect(NudgeMessage.body(from: ["type": "nudge", "body": ""]) == "Straighten up!")
    }
}
