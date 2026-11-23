import Foundation
import Testing
import UserNotifications
@testable import QuantWatch_Watch_App

/// The "Moved your seat?" question on the wrist (2026-11-23). The dictionaries are the golden
/// copies the phone's `SeatChangeWatchTests` assert.
struct SeatQuestionWatchTests {

    @Test func test_seatQuestionContent_hasCategoryAndTitle() {
        let content = NudgeMessage.seatQuestionContent(id: 1_791_640_030.5)
        #expect(content.categoryIdentifier == "seatChange")
        #expect(content.title == "Moved your seat?")
        #expect(content.userInfo["id"] as? Double == 1_791_640_030.5)
    }

    @Test func test_actionIdentifiers_mapToAnswers() {
        #expect(SeatChangeRemote.seatAnswer(forAction: "recalibrate") == "recalibrate")
        #expect(SeatChangeRemote.seatAnswer(forAction: "dismiss") == "dismiss")
        #expect(SeatChangeRemote.seatAnswer(forAction: UNNotificationDefaultActionIdentifier) == nil)
        #expect(SeatChangeRemote.seatAnswer(forAction: UNNotificationDismissActionIdentifier) == nil)
    }

    @Test func test_readsTheQuestion() {
        let open = SeatChangeRemote.question(from: ["type": "seatQuestion", "open": true, "id": 5.5])
        #expect(open?.open == true)
        #expect(open?.id == 5.5)
        #expect(SeatChangeRemote.question(from: ["type": "seatQuestion", "open": false, "id": 5.5])?.open == false)
        #expect(SeatChangeRemote.question(from: ["type": "seatQuestion", "open": true]) == nil)
        #expect(SeatChangeRemote.question(from: ["type": "nudge", "open": true, "id": 1.0]) == nil)
    }

    @Test func test_answerMessage_shape() {
        #expect(SeatChangeRemote.answerMessage("dismiss", id: 5.5) as NSDictionary
                == ["type": "seatAnswer", "answer": "dismiss", "id": 5.5] as NSDictionary)
    }

    @Test func test_categoryHasTwoBackgroundActions() {
        let category = SeatChangeRemote.category
        #expect(category.identifier == "seatChange")
        #expect(category.actions.map(\.identifier) == ["recalibrate", "dismiss"])
        #expect(category.actions.map(\.title) == ["Recalibrate", "Dismiss"])
        #expect(category.actions.allSatisfy { !$0.options.contains(.foreground) })
    }

    @Test func test_theQuestionShowsAsABannerWithTheAppOpen() {
        #expect(NudgeMessage.presentationOptions(forIdentifier: SeatChangeRemote.notificationIdentifier)
                == [.banner, .list])
    }

    @Test func test_aQueuedOpen_isIgnoredAfterItsClose() {
        var closed = SeatChangeRemote.ClosedQuestions()
        #expect(!closed.isClosed(5.5))
        closed.noteClosed(5.5)
        #expect(closed.isClosed(5.5), "the open for 5.5 that arrives late posts nothing")
        #expect(!closed.isClosed(9.0), "another question is unaffected")
    }

    @Test func test_closedQuestions_keepOnlyTheRecentOnes() {
        var closed = SeatChangeRemote.ClosedQuestions()
        for id in 1...20 { closed.noteClosed(Double(id)) }
        #expect(closed.isClosed(20))
        #expect(!closed.isClosed(1))
    }
}
