//
//  JevTestPlan.swift
//  QuantWatch Watch App
//
//  The guided test plan for a Jev device session: which posture to do next, how, and what
//  counts as a right answer, shown on the wrist while you hold the pose.
//

import Foundation

/// The protocol agreed for the second device session (2026-10-01): three captures each of
/// upright, slouch, lean and chair swivel, then two optional extras that probe the new swivel
/// wording. Each step is one capture.
///
/// The camera never sees the spine, only how wide the shoulders look, where the head is and how
/// far the body has shifted sideways, so each instruction says how to change one of those.
enum JevTestPlan {

    enum Posture: Equatable {
        case upright, slouch, lean, chairSwivel, headTurned, smallSwivel

        var name: String {
            switch self {
            case .upright: return "Upright"
            case .slouch: return "Slouch"
            case .lean: return "Lean"
            case .chairSwivel: return "Chair swivel"
            case .headTurned: return "Head turned"
            case .smallSwivel: return "Small swivel"
            }
        }

        var instruction: String {
            switch self {
            case .upright:
                return "Sit as you did when calibrating, looking at the screen."
            case .slouch:
                return "Collapse forward so your shoulders move towards the phone, head dropping. Don't just sink."
            case .lean:
                return "Shift your upper body sideways at the waist, shoulders still facing the phone."
            case .chairSwivel:
                return "Sit upright and turn the whole chair 30° or more. Not just your head."
            case .headTurned:
                return "Stay upright and look 30–40° to one side. Keep your shoulders still."
            case .smallSwivel:
                return "Turn the chair only 15–20°. Jev may well say lean or good posture: that shows where the cut is."
            }
        }

        /// The answer that counts as right for Jev, as the Watch displays class names.
        var jevShouldSay: String {
            switch self {
            case .upright, .headTurned: return "good posture"
            case .slouch: return "slouch"
            case .lean: return "lean"
            case .chairSwivel, .smallSwivel: return "chair swivel"
            }
        }

        /// The thresholds' state that counts as right. A swivel is fine posture, so "good" is
        /// right for it, and that's the false alarm Jev is meant to fix.
        var thresholdsShouldSay: String {
            switch self {
            case .upright, .chairSwivel, .headTurned, .smallSwivel: return "good"
            case .slouch, .lean: return "drifting or bad"
            }
        }

        /// The Jev class you were actually doing, the raw value "both wrong" records.
        var trueClass: String {
            switch self {
            case .upright, .headTurned: return "good_posture"
            case .slouch: return "slouch"
            case .lean: return "lean"
            case .chairSwivel, .smallSwivel: return "chair_swivel"
            }
        }

        /// Whether Jev's answer is the posture you did. "ambiguous" is Jev declining to answer,
        /// and no answer is never right.
        func jevRight(_ jevClass: String?) -> Bool {
            jevClass == trueClass
        }

        /// Whether the thresholds' state fits the posture: "good" for upright and swivel,
        /// drifting or bad for slouch and lean. Absent or calibrating isn't a judgement at all.
        func thresholdsRight(_ state: String) -> Bool {
            switch self {
            case .upright, .chairSwivel, .headTurned, .smallSwivel:
                return state == "good"
            case .slouch, .lean:
                return state == "drifting" || state == "bad"
            }
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
        + Array(repeating: Step(posture: .slouch, optional: false), count: 3)
        + Array(repeating: Step(posture: .lean, optional: false), count: 3)
        + Array(repeating: Step(posture: .chairSwivel, optional: false), count: 3)
        + Array(repeating: Step(posture: .headTurned, optional: true), count: 2)
        + Array(repeating: Step(posture: .smallSwivel, optional: true), count: 2)

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
    static func awaitsJudgement(capturedAt: Date, jevClass: String?, judged: Bool, now: Date) -> Bool {
        jevClass != nil && !judged && now.timeIntervalSince(capturedAt) < judgeWindow
    }
}
