import Foundation
import Testing
@testable import QuantWatch_Watch_App

/// The guided test plan on the Watch: which posture to do next, how, and what counts as right.
///
/// It's the protocol agreed for the second device session (2026-10-01): three captures each of
/// upright, slouch, lean and chair swivel, then two optional extras that probe the new swivel
/// wording.
struct JevTestPlanTests {

    @Test func runsTwelveCoreCapturesThenFourOptionalOnes() {
        let steps = JevTestPlan.steps
        #expect(steps.count == 16)
        #expect(steps.prefix(12).allSatisfy { !$0.optional })
        #expect(steps.suffix(4).allSatisfy { $0.optional })
    }

    @Test func goesThroughThePosturesInOrder_threeOfEach() {
        let names = JevTestPlan.steps.map(\.posture.name)
        #expect(names == [
            "Upright", "Upright", "Upright",
            "Slouch", "Slouch", "Slouch",
            "Lean", "Lean", "Lean",
            "Chair swivel", "Chair swivel", "Chair swivel",
            "Head turned", "Head turned",
            "Small swivel", "Small swivel",
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
        // The thresholds' known false alarm: a swivel is fine posture.
        #expect(JevTestPlan.Posture.chairSwivel.jevShouldSay == "chair swivel")
        #expect(JevTestPlan.Posture.chairSwivel.thresholdsShouldSay == "good")
        // The first session's main mistake: a turned head alone is not a swivel.
        #expect(JevTestPlan.Posture.headTurned.jevShouldSay == "good posture")
        #expect(JevTestPlan.Posture.smallSwivel.jevShouldSay == "chair swivel")
    }

    /// "Both wrong" asks what you were actually doing. The plan already knows.
    @Test func eachPostureNamesItsJevClass() {
        #expect(JevTestPlan.Posture.upright.trueClass == "good_posture")
        #expect(JevTestPlan.Posture.slouch.trueClass == "slouch")
        #expect(JevTestPlan.Posture.lean.trueClass == "lean")
        #expect(JevTestPlan.Posture.chairSwivel.trueClass == "chair_swivel")
        #expect(JevTestPlan.Posture.headTurned.trueClass == "good_posture")
        #expect(JevTestPlan.Posture.smallSwivel.trueClass == "chair_swivel")
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
        #expect(!JevTestPlan.Posture.headTurned.jevRight("chair_swivel"), "the first session's mistake")
        #expect(JevTestPlan.Posture.smallSwivel.jevRight("chair_swivel"))
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
        #expect(JevTestPlan.pickerLabel("chair_swivel", thisStep: .smallSwivel)
                == "chair swivel · this step (Small swivel)")
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
}
