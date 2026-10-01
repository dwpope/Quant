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
}
