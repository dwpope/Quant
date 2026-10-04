import Foundation
import Testing
@testable import QuantWatch_Watch_App

/// The guided test plan on the Watch: which posture to do next, how, and what counts as right.
///
/// Revised 2026-10-04 to what matters for soreness: three captures each of upright, slouch, lean
/// and chair swivel, two small slouches, then two optional head turns. The small swivel is gone:
/// it isn't bad posture, and the camera can't see a 15-20° turn.
struct JevTestPlanTests {

    @Test func runsFourteenCoreCapturesThenTwoOptionalOnes() {
        let steps = JevTestPlan.steps
        #expect(steps.count == 16)
        #expect(steps.prefix(14).allSatisfy { !$0.optional })
        #expect(steps.suffix(2).allSatisfy { $0.optional })
    }

    @Test func goesThroughThePosturesInOrder_threeOfEach() {
        let names = JevTestPlan.steps.map(\.posture.name)
        #expect(names == [
            "Upright", "Upright", "Upright",
            "Slouch", "Slouch", "Slouch",
            "Small slouch", "Small slouch",
            "Lean", "Lean", "Lean",
            "Chair swivel", "Chair swivel", "Chair swivel",
            "Head turned", "Head turned",
        ])
    }

    /// What counts as right is part of the plan, so judging on the wrist is consistent.
    @Test func eachPostureSaysWhatARightAnswerIs() {
        #expect(JevTestPlan.Posture.upright.jevShouldSay == "good posture")
        #expect(JevTestPlan.Posture.upright.thresholdsShouldSay == "good")
        #expect(JevTestPlan.Posture.slouch.jevShouldSay == "slouch")
        #expect(JevTestPlan.Posture.slouch.thresholdsShouldSay == "drifting or bad")
        #expect(JevTestPlan.Posture.lean.jevShouldSay == "lean")
        #expect(JevTestPlan.Posture.lean.thresholdsShouldSay == "drifting or bad")
        #expect(JevTestPlan.Posture.smallSlouch.jevShouldSay == "slouch")
        #expect(JevTestPlan.Posture.smallSlouch.thresholdsShouldSay == "drifting or bad")
        // The thresholds' known false alarm: a swivel is fine posture. For a fine posture what
        // matters is no nudge, so any answer but slouch or lean is right.
        #expect(JevTestPlan.Posture.chairSwivel.jevShouldSay == "not slouch or lean")
        #expect(JevTestPlan.Posture.chairSwivel.thresholdsShouldSay == "good")
        #expect(JevTestPlan.Posture.headTurned.jevShouldSay == "not slouch or lean")
    }

    /// "Both wrong" asks what you were actually doing. The plan already knows.
    @Test func eachPostureNamesItsJevClass() {
        #expect(JevTestPlan.Posture.upright.trueClass == "good_posture")
        #expect(JevTestPlan.Posture.slouch.trueClass == "slouch")
        #expect(JevTestPlan.Posture.lean.trueClass == "lean")
        #expect(JevTestPlan.Posture.chairSwivel.trueClass == "chair_swivel")
        #expect(JevTestPlan.Posture.headTurned.trueClass == "good_posture")
        #expect(JevTestPlan.Posture.smallSlouch.trueClass == "slouch")
    }

    @Test func everyPostureHasAnInstruction() {
        for step in JevTestPlan.steps {
            #expect(!step.posture.instruction.isEmpty, "\(step.posture.name)")
        }
    }

    // MARK: - Moving through it

    @Test func numbersStepsFromOne_andCountsWithinAPosture() throws {
        let fourth = try #require(JevTestPlan.progress(at: 3))
        #expect(fourth.number == 4)
        #expect(fourth.total == 16)
        #expect(fourth.step.posture == .slouch)
        #expect(fourth.repeatNumber == 1)
        #expect(fourth.repeatCount == 3)
        #expect(try #require(JevTestPlan.progress(at: 5)).repeatNumber == 3)
    }

    @Test func nextAndPrevious_stayInsideThePlan() {
        #expect(JevTestPlan.next(after: 0) == 1)
        #expect(JevTestPlan.next(after: 15) == 16, "one past the end means finished")
        #expect(JevTestPlan.next(after: 16) == 16)
        #expect(JevTestPlan.previous(before: 1) == 0)
        #expect(JevTestPlan.previous(before: 0) == 0)
        #expect(JevTestPlan.previous(before: 16) == 15)
    }

    @Test func pastTheLastStep_isFinished() {
        #expect(JevTestPlan.progress(at: 16) == nil)
        #expect(JevTestPlan.progress(at: -1) == nil)
    }

    // MARK: - What the top of the screen shows

    /// The top of the screen is always the next action: judge a fresh capture, otherwise the
    /// next posture and Classify.
    @Test func aFreshUnjudgedCapture_isJudgedFirst() {
        let now = Date()
        #expect(JevTestPlan.awaitsJudgement(capturedAt: now - 10, jevClass: "slouch", judged: false, now: now))
        #expect(!JevTestPlan.awaitsJudgement(capturedAt: now - 10, jevClass: "slouch", judged: true, now: now))
    }

    /// A failed call has nothing to judge: the next action is to classify again.
    @Test func aFailedCapture_isNotJudged() {
        let now = Date()
        #expect(!JevTestPlan.awaitsJudgement(capturedAt: now - 10, jevClass: nil, judged: false, now: now))
    }

    /// An old unjudged capture, say from yesterday, mustn't block the plan.
    @Test func anOldCapture_doesNotBlockThePlan() {
        let now = Date()
        let old = now - JevTestPlan.judgeWindow - 1
        #expect(!JevTestPlan.awaitsJudgement(capturedAt: old, jevClass: "slouch", judged: false, now: now))
    }

    // MARK: - Ticks and the suggested button (2026-10-03)
    //
    // "Judge: Lean" read as an answer, not the posture you were doing. The screen now says
    // "You did", "Jev said" and "Thresholds said", with a tick or cross beside each answer and
    // the matching button highlighted, so judging doesn't depend on reading it right.

    @Test func jevIsRight_onlyWhenItNamesThePostureYouDid() {
        #expect(JevTestPlan.Posture.upright.jevRight("good_posture"))
        #expect(!JevTestPlan.Posture.upright.jevRight("slouch"))
        #expect(JevTestPlan.Posture.slouch.jevRight("slouch"))
        #expect(JevTestPlan.Posture.lean.jevRight("lean"))
        #expect(!JevTestPlan.Posture.lean.jevRight("chair_swivel"))
        #expect(JevTestPlan.Posture.chairSwivel.jevRight("chair_swivel"))
        #expect(JevTestPlan.Posture.headTurned.jevRight("good_posture"))
        #expect(JevTestPlan.Posture.smallSlouch.jevRight("slouch"))
        #expect(!JevTestPlan.Posture.smallSlouch.jevRight("good_posture"), "the miss that matters")
    }

    /// Ambiguous is Jev declining to answer, and no answer is never right.
    @Test func ambiguousOrNoAnswer_isNeverRight() {
        for step in JevTestPlan.steps {
            #expect(!step.posture.jevRight("ambiguous"))
            #expect(!step.posture.jevRight(nil))
        }
    }

    @Test func thresholdsAreRight_whenTheirStateFitsThePosture() {
        #expect(JevTestPlan.Posture.upright.thresholdsRight("good"))
        #expect(!JevTestPlan.Posture.upright.thresholdsRight("drifting"))
        #expect(JevTestPlan.Posture.slouch.thresholdsRight("drifting"))
        #expect(JevTestPlan.Posture.slouch.thresholdsRight("bad"))
        #expect(!JevTestPlan.Posture.slouch.thresholdsRight("good"))
        #expect(JevTestPlan.Posture.lean.thresholdsRight("bad"))
        // A swivel is fine posture: flagging it is the thresholds' known false alarm.
        #expect(JevTestPlan.Posture.chairSwivel.thresholdsRight("good"))
        #expect(!JevTestPlan.Posture.chairSwivel.thresholdsRight("drifting"))
    }

    /// Absent or calibrating isn't a judgement of the posture at all.
    @Test func thresholdsWithoutAJudgement_areNeverRight() {
        for step in JevTestPlan.steps {
            #expect(!step.posture.thresholdsRight("absent"))
            #expect(!step.posture.thresholdsRight("calibrating"))
        }
    }

    /// Who to trust: Jev if it's right, whatever the thresholds said; else the thresholds if
    /// they're right; else neither.
    @Test func theSuggestedButton() {
        #expect(JevTestPlan.suggestedVerdict(jevRight: true, thresholdsRight: true) == .jevWasRight)
        #expect(JevTestPlan.suggestedVerdict(jevRight: true, thresholdsRight: false) == .jevWasRight)
        #expect(JevTestPlan.suggestedVerdict(jevRight: false, thresholdsRight: true) == .thresholdsWereRight)
        #expect(JevTestPlan.suggestedVerdict(jevRight: false, thresholdsRight: false) == .bothWrong)
    }

    /// A discarded capture has nothing to judge: retake the same posture.
    @Test func aDiscardedCapture_isNotJudged() {
        let now = Date()
        #expect(!JevTestPlan.awaitsJudgement(capturedAt: now - 10, jevClass: "lean", judged: false,
                                             discarded: true, now: now))
    }

    // MARK: - Head turned (2026-10-03, session 3)
    //
    // When Jev called a head turn slouch, "Both wrong" had no "head turned" to choose: its right
    // answer is good posture, because looking away isn't bad posture. The step now says so, and
    // the list names the posture beside its class.

    @Test func headTurned_explainsWhyGoodPostureIsRight() throws {
        let note = try #require(JevTestPlan.Posture.headTurned.note)
        #expect(note.contains("good posture"))
    }

    /// Where the answer is the posture's own name, the screen stays short.
    @Test func theCorePostures_needNoNote() {
        for posture in [JevTestPlan.Posture.upright, .slouch, .lean, .chairSwivel] {
            #expect(posture.note == nil, "\(posture.name)")
        }
    }

    @Test func bothWrongList_namesThePostureWhenItsClassReadsDifferently() {
        #expect(JevTestPlan.pickerLabel("good_posture", thisStep: .headTurned)
                == "good posture · this step (Head turned)")
        #expect(JevTestPlan.pickerLabel("slouch", thisStep: .smallSlouch)
                == "slouch · this step (Small slouch)")
        #expect(JevTestPlan.pickerLabel("good_posture", thisStep: .upright)
                == "good posture · this step (Upright)")
    }

    @Test func bothWrongList_doesNotRepeatAPostureNamedLikeItsClass() {
        #expect(JevTestPlan.pickerLabel("lean", thisStep: .lean) == "lean · this step")
        #expect(JevTestPlan.pickerLabel("chair_swivel", thisStep: .chairSwivel)
                == "chair swivel · this step")
    }

    @Test func bothWrongList_leavesOtherClassesPlain() {
        #expect(JevTestPlan.pickerLabel("slouch", thisStep: .headTurned) == "slouch")
        #expect(JevTestPlan.pickerLabel("good_posture", thisStep: nil) == "good posture")
    }

    /// Session 4's lean miss had the head turned 57°, and its other two leans ±24–25°; session 3's
    /// leans, 0–10°. A turned head also makes the thresholds discount the lean.
    @Test func lean_asksYouToKeepLookingAtTheScreen() {
        #expect(JevTestPlan.Posture.lean.instruction.contains("Keep looking at the screen"))
    }

    // MARK: - Nudge or not (2026-10-04)
    //
    // Only slouch and lean are worth a nudge. For everything else what matters is no nudge, so
    // Jev saying good posture on a swivel, or swivel on a head turn, is right. Session 5's two
    // "Both wrong" taps on a swivel Jev called good posture are what this removes.

    @Test func onlySlouchAndLean_areWorthANudge() {
        #expect(JevTestPlan.Posture.slouch.worthANudge)
        #expect(JevTestPlan.Posture.smallSlouch.worthANudge)
        #expect(JevTestPlan.Posture.lean.worthANudge)
        #expect(!JevTestPlan.Posture.upright.worthANudge)
        #expect(!JevTestPlan.Posture.chairSwivel.worthANudge)
        #expect(!JevTestPlan.Posture.headTurned.worthANudge)
    }

    @Test func aFinePosture_isRightForAnyAnswerThatWouldNotNudge() {
        for posture in [JevTestPlan.Posture.upright, .chairSwivel, .headTurned] {
            #expect(posture.jevRight("good_posture"), "\(posture.name)")
            #expect(posture.jevRight("chair_swivel"), "\(posture.name)")
            #expect(!posture.jevRight("slouch"), "\(posture.name)")
            #expect(!posture.jevRight("lean"), "\(posture.name)")
        }
    }

    /// A posture worth a nudge still needs its own class: it says what to fix.
    @Test func aPostureWorthANudge_needsItsOwnClass() {
        #expect(!JevTestPlan.Posture.slouch.jevRight("lean"))
        #expect(!JevTestPlan.Posture.lean.jevRight("slouch"))
        #expect(!JevTestPlan.Posture.slouch.jevRight("chair_swivel"))
    }

    /// Session 3's two missed slouches came forward only 4-5%; every slouch since has come well
    /// forward, so the head-height rule for them is still untested on the device.
    @Test func smallSlouch_asksForJustTheStartOfOne() {
        let instruction = JevTestPlan.Posture.smallSlouch.instruction
        #expect(instruction.contains("a little"))
        #expect(instruction.contains("head"))
    }
}
