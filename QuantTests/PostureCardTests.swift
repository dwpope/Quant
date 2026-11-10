import SwiftUI
import UIKit
import XCTest
import PostureLogic
@testable import Quant

/// The posture card says how to sit up again, and keeps its height (2026-11-09, session 7).
///
/// Dave: "the secondary text that appears on the slouching card causes the card to expand in
/// height causing the interface to jitter", and "No helpful text in the [posture] slouching card
/// on the iPhone on how to correct back to good posture". The camera's signal line came and went
/// with the tracking quality, and pushed every card under it up and down.
@MainActor
final class PostureCardTests: XCTestCase {

    private func height(_ card: PostureCard, size: DynamicTypeSize = .large) -> CGFloat {
        let host = UIHostingController(rootView: card.environment(\.dynamicTypeSize, size))
        return host.sizeThatFits(in: CGSize(width: 358, height: CGFloat.greatestFiniteMagnitude)).height
    }

    func test_theCameraSignal_doesNotChangeTheCardsHeight() {
        for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
            let heights = [TrackingQuality.good, .degraded, .lost].map {
                height(PostureCard(postureState: .drifting(since: 0), trackingQuality: $0,
                                   coaching: .forwardCreep), size: size)
            }
            XCTAssertEqual(Set(heights).count, 1, "\(size): \(heights)")
        }
    }

    func test_thePosture_doesNotChangeTheCardsHeight() {
        let cards = [
            PostureCard(postureState: .good, trackingQuality: .good, coaching: nil),
            PostureCard(postureState: .good, trackingQuality: .good, coaching: nil, headTurned: true),
            PostureCard(postureState: .drifting(since: 0), trackingQuality: .good, coaching: .headDrop),
            PostureCard(postureState: .bad(since: 0), trackingQuality: .degraded, coaching: .sustainedSlouch),
            PostureCard(postureState: .absent, trackingQuality: .lost, coaching: nil),
            PostureCard(postureState: .calibrating, trackingQuality: .good, coaching: nil),
        ]
        for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
            let heights = cards.map { height($0, size: size) }
            XCTAssertEqual(Set(heights).count, 1, "\(size): \(heights)")
        }
    }

    // MARK: - What it says

    /// The same words the Watch shows for the nudge.
    func test_slouching_saysHowToSitUp() {
        for reason in [NudgeReason.forwardCreep, .headDrop, .sink, .sustainedSlouch] {
            XCTAssertEqual(PostureCard.detail(for: .drifting(since: 0), coaching: reason), reason.coachingMessage)
            XCTAssertEqual(PostureCard.detail(for: .bad(since: 0), coaching: reason), reason.coachingMessage)
        }
    }

    /// Before the slouch's reason is known, the general line.
    func test_slouching_forNoReasonYet_saysSitUp() {
        XCTAssertEqual(PostureCard.detail(for: .drifting(since: 0), coaching: nil),
                       NudgeReason.sustainedSlouch.coachingMessage)
    }

    func test_otherwise_itSaysWhatToKeep_orWhy() {
        XCTAssertEqual(PostureCard.detail(for: .good, coaching: nil), "Head up, sitting back")
        XCTAssertEqual(PostureCard.detail(for: .good, coaching: .headDrop), "Head up, sitting back",
                       "a slouch's line is gone once you've sat up")
        XCTAssertEqual(PostureCard.detail(for: .absent, coaching: nil), "Out of the camera's view")
        XCTAssertEqual(PostureCard.detail(for: .calibrating, coaching: nil), "Sit as you usually do, and hold still")
    }

    // MARK: - A head turned

    /// Dave (2026-11-10): "When i turn my head i would like to see that registered on the device
    /// as a status in the same location it usually shows slouching". In the words, and by the
    /// rule, of the Watch and the calm view: from the moment it turns, while sitting well, with
    /// what its nudge will say.
    func test_aHeadTurned_whileSittingWell_isShownWhereASlouchIs() {
        XCTAssertEqual(PostureCard.label(for: .good, headTurned: true), "Head turned")
        XCTAssertEqual(PostureCard.label(for: .good, headTurned: true),
                       CalmLook.headTurned(since: Date(), nudgeAt: nil).headline)
        XCTAssertEqual(PostureCard.detail(for: .good, coaching: nil, headTurned: true),
                       NudgeReason.headTurned.coachingMessage)
    }

    /// Slouching as well, the slouch is said: it's the posture to fix, and the Watch and the
    /// calm view show a turn only while sitting well. Away or calibrating, nothing is judged.
    func test_otherwise_aHeadTurned_changesNothing() {
        XCTAssertEqual(PostureCard.label(for: .drifting(since: 0), headTurned: true), "Slouching")
        XCTAssertEqual(PostureCard.detail(for: .bad(since: 0), coaching: .headDrop, headTurned: true),
                       NudgeReason.headDrop.coachingMessage)
        XCTAssertEqual(PostureCard.label(for: .absent, headTurned: true), "Away")
        XCTAssertEqual(PostureCard.label(for: .calibrating, headTurned: true), "Calibrating…")
    }
}

/// Which slouch the card coaches, held steady (2026-11-09).
///
/// In session 7 the nudge's reason swapped between head drop and forward creep every few seconds
/// while one slouch went on (16:43:45 to 16:44:36), and is unknown while a cooldown holds the
/// nudge back. The line follows a new reason only once it has lasted, and a nudge's own reason at
/// once, so the card says what the Watch just said.
final class SlouchCoachingTests: XCTestCase {

    private let slouching = PostureState.drifting(since: 0)

    func test_theFirstReason_showsAtOnce() {
        var coaching = SlouchCoaching()
        coaching.update(state: slouching, decision: .pending(reason: .headDrop, timeRemaining: 60), now: 0)
        XCTAssertEqual(coaching.reason, .headDrop)
    }

    func test_itHolds_whileTheNudgeIsHeldBack() {
        var coaching = SlouchCoaching()
        coaching.update(state: slouching, decision: .pending(reason: .forwardCreep, timeRemaining: 60), now: 0)
        coaching.update(state: .bad(since: 0), decision: .suppressed(reason: .cooldownActive), now: 5)
        coaching.update(state: .bad(since: 0), decision: .suppressed(reason: .lowTrackingQuality), now: 6)
        XCTAssertEqual(coaching.reason, .forwardCreep)
    }

    func test_aNewReason_takesOver_onlyOnceItHasLasted() {
        var coaching = SlouchCoaching()
        coaching.update(state: slouching, decision: .pending(reason: .headDrop, timeRemaining: 60), now: 0)
        coaching.update(state: slouching, decision: .pending(reason: .forwardCreep, timeRemaining: 55), now: 5)
        coaching.update(state: slouching, decision: .pending(reason: .forwardCreep, timeRemaining: 50), now: 10)
        XCTAssertEqual(coaching.reason, .headDrop, "five seconds isn't long enough")
        coaching.update(state: slouching, decision: .pending(reason: .forwardCreep, timeRemaining: 45),
                        now: 5 + SlouchCoaching.takesOverAfter)
        XCTAssertEqual(coaching.reason, .forwardCreep)
    }

    /// Back to the first before the second had lasted: the second starts again from nothing.
    func test_aSwapBack_restartsTheWait() {
        var coaching = SlouchCoaching()
        coaching.update(state: slouching, decision: .pending(reason: .headDrop, timeRemaining: 60), now: 0)
        coaching.update(state: slouching, decision: .pending(reason: .forwardCreep, timeRemaining: 55), now: 1)
        coaching.update(state: slouching, decision: .pending(reason: .headDrop, timeRemaining: 54), now: 2)
        coaching.update(state: slouching, decision: .pending(reason: .forwardCreep, timeRemaining: 53), now: 3)
        coaching.update(state: slouching, decision: .pending(reason: .forwardCreep, timeRemaining: 50),
                        now: 1 + SlouchCoaching.takesOverAfter)
        XCTAssertEqual(coaching.reason, .headDrop)
    }

    func test_aNudge_showsItsReason_atOnce() {
        var coaching = SlouchCoaching()
        coaching.update(state: slouching, decision: .pending(reason: .forwardCreep, timeRemaining: 1), now: 0)
        coaching.update(state: slouching, decision: .fire(reason: .headDrop), now: 1)
        XCTAssertEqual(coaching.reason, .headDrop)
    }

    /// A sit-up of a few seconds is the same slouch, as the engine counts it: the line comes
    /// back with its reason though the cooldown names none.
    func test_aBriefSitUp_keepsIt() {
        var coaching = SlouchCoaching()
        coaching.update(state: slouching, decision: .pending(reason: .forwardCreep, timeRemaining: 60), now: 0)
        coaching.update(state: .good, decision: .none, now: 1)
        coaching.update(state: .good, decision: .none, now: 3)
        coaching.update(state: slouching, decision: .suppressed(reason: .cooldownActive), now: 4)
        XCTAssertEqual(coaching.reason, .forwardCreep)
    }

    func test_sittingWell_forHalfAMinute_endsIt() {
        var coaching = SlouchCoaching()
        coaching.update(state: slouching, decision: .pending(reason: .sink, timeRemaining: 60), now: 0)
        coaching.update(state: .good, decision: .none, now: 1)
        coaching.update(state: .good, decision: .none, now: 1 + SlouchCoaching.keptThroughSittingUp)
        XCTAssertNil(coaching.reason)
        coaching.update(state: slouching, decision: .pending(reason: .headDrop, timeRemaining: 60), now: 40)
        XCTAssertEqual(coaching.reason, .headDrop, "the next slouch starts afresh")
    }

    func test_leavingTheDesk_endsIt() {
        var coaching = SlouchCoaching()
        coaching.update(state: slouching, decision: .pending(reason: .sink, timeRemaining: 60), now: 0)
        coaching.update(state: .absent, decision: .none, now: 1)
        XCTAssertNil(coaching.reason)
    }

    /// A head held turned isn't a slouch: it has its own nudge and its own line.
    func test_aHeadTurn_isNotASlouchsReason() {
        var coaching = SlouchCoaching()
        coaching.update(state: slouching, decision: .pending(reason: .headTurned, timeRemaining: 100), now: 0)
        XCTAssertNil(coaching.reason)
    }

    /// The app keeps one for the card, fed with each frame's decision.
    @MainActor
    func test_theAppPublishesIt() {
        let model = AppModel()
        model.updateSlouchCoaching(state: slouching, decision: .pending(reason: .sink, timeRemaining: 60), now: 0)
        XCTAssertEqual(model.slouchCoaching, .sink)
    }
}
