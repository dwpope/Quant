//
//  JevTestPlan.swift
//  QuantWatch Watch App
//
//  The guided test plan for a Jev device session: which posture to do next, how, and what
//  counts as a right answer, shown on the wrist while you hold the pose.
//

import Foundation

/// The protocol for a device session, revised 2026-10-04 to what matters for soreness and
/// 2026-10-05 for sinking: three uprights, two slouches leaning in, three sinking down in the
/// chair, two small slouches, two leans, two chair swivels, two leaning back (to check the sink
/// line doesn't flag reclining), then two optional head turns. Each step is one capture.
/// Session 7's slouches sank, and nothing measured saw them.
///
/// Only slouch and lean are worth a nudge. The swivel and the head turn are here as false-alarm
/// checks: a nudge for nothing teaches you to ignore nudges. The small swivel was dropped: it
/// isn't bad posture, and a 15-20° turn doesn't narrow the shoulders enough for the camera.
///
/// The camera never sees the spine, only how wide the shoulders look, where the head is and how
/// far the body has shifted sideways, so each instruction says how to change one of those.
enum JevTestPlan {

    enum Posture: Equatable {
        case upright, slouch, sink, smallSlouch, lean, chairSwivel, leanBack, headTurned

        /// Slouch and lean, the postures a nudge is for. For the others what matters is that
        /// nothing nudges.
        var worthANudge: Bool {
            switch self {
            case .slouch, .sink, .smallSlouch, .lean: return true
            case .upright, .chairSwivel, .leanBack, .headTurned: return false
            }
        }

        var name: String {
            switch self {
            case .upright: return "Upright"
            case .slouch: return "Slouch"
            case .sink: return "Sink"
            case .smallSlouch: return "Small slouch"
            case .lean: return "Lean"
            case .chairSwivel: return "Chair swivel"
            case .leanBack: return "Lean back"
            case .headTurned: return "Head turned"
            }
        }

        var instruction: String {
            switch self {
            case .upright:
                return "Sit as you did when calibrating, looking at the screen."
            case .slouch:
                return "Collapse forward so your shoulders move towards the phone, head dropping. Don't just sink."
            case .sink:
                return "Slide down in the chair so your head and shoulders drop together. Don't lean towards the phone."
            case .smallSlouch:
                return "Ease forward just a little, shoulders slightly towards the phone, head dropping a touch. The start of a slouch."
            case .lean:
                return "Shift your upper body sideways at the waist, shoulders still facing the phone. Keep looking at the screen."
            case .chairSwivel:
                return "Sit upright and turn the whole chair 30° or more. Not just your head."
            case .leanBack:
                return "Sit back against the backrest, reclined a little, head over your shoulders. Don't slide down."
            case .headTurned:
                return "Stay upright and look 30–40° to one side. Keep your shoulders still."
            }
        }

        /// Why the right answer is what it is, where the posture's name doesn't say. On
        /// 2026-10-03 a head turn called slouch couldn't be corrected: "Both wrong" had no
        /// "head turned", because looking away is good posture.
        var note: String? {
            switch self {
            case .headTurned:
                return "Jev judges posture: a straight back with your head turned is good posture. The phone times the turn itself: watch Head turned below count up."
            case .sink:
                return "Being recorded first: neither Jev nor the thresholds can see sinking yet, so a miss is expected. Judge it anyway."
            case .upright, .slouch, .smallSlouch, .lean, .chairSwivel, .leanBack:
                return nil
            }
        }

        /// The answer that counts as right for Jev, as the Watch displays class names.
        var jevShouldSay: String {
            switch self {
            case .upright: return "good posture"
            case .slouch, .sink, .smallSlouch: return "slouch"
            case .lean: return "lean"
            case .chairSwivel, .leanBack, .headTurned: return "not slouch or lean"
            }
        }

        /// The thresholds' state that counts as right. A swivel is fine posture, so "good" is
        /// right for it, and that's the false alarm Jev is meant to fix.
        var thresholdsShouldSay: String {
            switch self {
            case .upright, .chairSwivel, .leanBack, .headTurned: return "good"
            case .slouch, .sink, .smallSlouch, .lean: return "drifting or bad"
            }
        }

        /// The Jev class you were actually doing, the raw value "both wrong" records.
        var trueClass: String {
            switch self {
            case .upright, .leanBack, .headTurned: return "good_posture"
            case .slouch, .sink, .smallSlouch: return "slouch"
            case .lean: return "lean"
            case .chairSwivel: return "chair_swivel"
            }
        }

        /// Whether Jev's answer is right. A posture worth a nudge needs its own class, since that
        /// says what to fix; for the others any answer that wouldn't nudge is right. "ambiguous"
        /// is Jev declining to answer, and no answer is never right.
        func jevRight(_ jevClass: String?) -> Bool {
            if worthANudge { return jevClass == trueClass }
            return jevClass == "good_posture" || jevClass == "chair_swivel"
        }

        /// Whether the thresholds' state fits the posture: drifting or bad for a posture worth a
        /// nudge, "good" otherwise. Absent or calibrating isn't a judgement at all.
        func thresholdsRight(_ state: String) -> Bool {
            worthANudge ? (state == "drifting" || state == "bad") : state == "good"
        }
    }

    struct Step: Equatable {
        let posture: Posture
        let optional: Bool
    }

    /// Where you are in the plan, for display.
    struct Progress: Equatable {
        let step: Step
        /// 1-based position in the whole plan.
        let number: Int
        let total: Int
        /// Which capture of this posture it is, and how many there are.
        let repeatNumber: Int
        let repeatCount: Int
    }

    static let steps: [Step] =
        Array(repeating: Step(posture: .upright, optional: false), count: 3)
        + Array(repeating: Step(posture: .slouch, optional: false), count: 2)
        + Array(repeating: Step(posture: .sink, optional: false), count: 3)
        + Array(repeating: Step(posture: .smallSlouch, optional: false), count: 2)
        + Array(repeating: Step(posture: .lean, optional: false), count: 2)
        + Array(repeating: Step(posture: .chairSwivel, optional: false), count: 2)
        + Array(repeating: Step(posture: .leanBack, optional: false), count: 2)
        + Array(repeating: Step(posture: .headTurned, optional: true), count: 2)

    /// The step at `index`, or nil once the plan is finished (or for a nonsense index).
    static func progress(at index: Int) -> Progress? {
        guard steps.indices.contains(index) else { return nil }
        let step = steps[index]
        let samePosture = steps.indices.filter { steps[$0].posture == step.posture }
        return Progress(
            step: step,
            number: index + 1,
            total: steps.count,
            repeatNumber: (samePosture.firstIndex(of: index) ?? 0) + 1,
            repeatCount: samePosture.count)
    }

    /// A "Both wrong" entry. This step's class is marked, with the posture's name beside it
    /// where the class reads differently, so "Head turned" can be found under good posture.
    static func pickerLabel(_ option: String, thisStep: Posture?) -> String {
        let name = JevRemoteStatus.displayName(option)
        guard let thisStep, option == thisStep.trueClass else { return name }
        return thisStep.name.lowercased() == name
            ? "\(name) · this step"
            : "\(name) · this step (\(thisStep.name))"
    }

    /// The next index. One past the last step means finished, and it stays there.
    static func next(after index: Int) -> Int { min(index + 1, steps.count) }

    static func previous(before index: Int) -> Int { max(index - 1, 0) }

    /// The button the ticks point to. Jev if it's right, whatever the thresholds said (when both
    /// are right, "Jev ok" loses nothing: the record keeps the thresholds' state). Otherwise the
    /// thresholds if they're right, otherwise neither.
    static func suggestedVerdict(jevRight: Bool, thresholdsRight: Bool) -> JevRemoteVerdict {
        if jevRight { return .jevWasRight }
        return thresholdsRight ? .thresholdsWereRight : .bothWrong
    }

    /// How recent an unjudged capture must be to take over the top of the screen.
    static let judgeWindow: TimeInterval = 120

    /// Whether the top of the screen should ask you to judge the last capture rather than show
    /// the next posture. Only a fresh capture that has an answer: a failed call means classify
    /// again, and an old unjudged one (say from yesterday) mustn't block the plan.
    /// A discarded capture doesn't either: you retake the same posture.
    static func awaitsJudgement(capturedAt: Date, jevClass: String?, judged: Bool,
                                discarded: Bool = false, now: Date) -> Bool {
        jevClass != nil && !judged && !discarded && now.timeIntervalSince(capturedAt) < judgeWindow
    }
}
