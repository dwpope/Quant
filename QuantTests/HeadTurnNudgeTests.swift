import XCTest
import PostureLogic
@testable import Quant

/// The head-turn nudge on the phone's side: what it sends the Watch and how it's counted.
///
/// Every nudge used to reach the Watch as a haptic and "Straighten up!", which is the wrong
/// advice for a head held turned to a second screen (2026-10-04). The nudge now carries its
/// reason's coaching line, and the Watch shows it.
@MainActor
final class HeadTurnNudgeTests: XCTestCase {

    // MARK: - The Watch's message (golden copy; the Watch's tests read the same dictionary)

    func test_aNudgeCarriesItsCoachingLine() {
        let message = WatchConnectivityService.nudgeMessage(
            hapticType: "failure", body: NudgeReason.headTurned.coachingMessage) as NSDictionary
        XCTAssertEqual(message, [
            "type": "nudge",
            "haptic": "failure",
            "body": "Turn your chair to face that screen",
        ] as NSDictionary)
    }

    func test_aSlouchNudge_saysWhatToFix() {
        let message = WatchConnectivityService.nudgeMessage(
            hapticType: "failure", body: NudgeReason.forwardCreep.coachingMessage)
        XCTAssertEqual(message["body"] as? String, "Sit back — you're leaning in")
    }

    // MARK: - Insights

    func test_insights_countHeadTurns() {
        let events = [
            NudgeEvent(timestamp: 1_000, reason: .headTurned),
            NudgeEvent(timestamp: 2_000, reason: .headTurned),
            NudgeEvent(timestamp: 3_000, reason: .forwardCreep),
        ]
        let insights = NudgeInsights(events: events)
        XCTAssertEqual(insights.headTurnedCount, 2)
        XCTAssertEqual(insights.dominantReason, .headTurned)
        XCTAssertEqual(insights.dominantReasonDescription, "Mostly head turned")
    }
}
