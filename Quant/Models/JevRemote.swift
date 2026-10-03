import Foundation
import PostureLogic

/// The Apple Watch as a remote for Jev captures.
///
/// Classify now captures the pose at the instant it is tapped. With the phone out of reach,
/// tapping it meant leaning toward it, so the capture recorded the reach rather than the posture
/// being held. The Watch sends the tap instead, and the phone reports back what it captured.
///
/// ## Message format
///
/// The Watch and the phone are separate targets with no shared code, so this format is a
/// contract. `QuantTests/JevRemoteTests` holds the golden copy for the phone side and the Watch
/// tests assert the same dictionaries from the other side. Change both or neither.
///
/// Watch to phone:
/// - `["type": "jevClassify"]`: the phone captures `captureDelay` seconds later, so the pose
///   isn't recorded mid-glance at the wrist.
/// - `["type": "jevJudge", "recordID": <UUID string>, "verdict": <UserVerdict raw>,
///   "trueClass": <JevClass raw, optional>]`
/// - `["type": "jevStatusRequest"]`
/// - `["type": "jevDiscard", "recordID": <UUID string>]`: flag a capture made by mistake
///
/// Phone to Watch: `["type": "jevStatus", …]`, see ``Status/message``.
///
/// The Watch can trigger a capture but cannot switch the classifier on. That switch is the
/// privacy boundary and stays on the phone.
enum JevRemote {

    enum MessageType {
        static let classify = "jevClassify"
        static let judge = "jevJudge"
        static let discard = "jevDiscard"
        static let statusRequest = "jevStatusRequest"
        static let status = "jevStatus"
    }

    /// Something the Watch asked for.
    enum Command: Equatable {
        case classify
        case judge(recordID: UUID, verdict: JevComparisonRecord.UserVerdict, trueClass: JevClass?)
        case statusRequest
        /// The capture was a mistake: flag it, keep it.
        case discard(recordID: UUID)

        /// Nil for anything that is not a well-formed remote command, including the Watch's
        /// older message types, which keep their own handlers.
        ///
        /// A judgement without a readable record or verdict is rejected rather than guessed at,
        /// because it is the only ground truth the dataset has. An unknown true class is not a
        /// reason to lose the judgement: it is kept with `trueClass` nil, the same rule the
        /// store applies to old records, so the "both wrong" still flags the capture.
        init?(message: [String: Any]) {
            switch message["type"] as? String {
            case MessageType.classify:
                self = .classify
            case MessageType.statusRequest:
                self = .statusRequest
            case MessageType.discard:
                guard let idString = message["recordID"] as? String,
                      let id = UUID(uuidString: idString)
                else { return nil }
                self = .discard(recordID: id)
            case MessageType.judge:
                guard let idString = message["recordID"] as? String,
                      let id = UUID(uuidString: idString),
                      let verdictRaw = message["verdict"] as? String,
                      let verdict = JevComparisonRecord.UserVerdict(rawValue: verdictRaw)
                else { return nil }
                let trueClass = (message["trueClass"] as? String).flatMap(JevClass.init(rawValue:))
                self = .judge(recordID: id, verdict: verdict, trueClass: trueClass)
            default:
                return nil
            }
        }
    }

    /// What the Watch shows: enough to position yourself before a capture, and to judge it after.
    struct Status: Equatable {

        /// The newest comparison record, as it was captured.
        struct Record: Equatable {
            var id: UUID
            /// Nil when the call failed. A failure is still a record.
            var jevClass: String?
            var jevConfidence: Double?
            /// The thresholds' state when the record was captured. This, not the live state,
            /// is what a judgement is about.
            var thresholdStateAtCapture: String
            var capturedAt: TimeInterval
            /// The `UserVerdict` raw value, once judged.
            var judged: String?
            /// Flagged as a mistake. Sent only when true.
            var discarded: Bool = false
        }

        var enabled: Bool
        var calibrated: Bool
        var tracking: String
        /// Live, for getting into position.
        var thresholdState: String
        /// Seconds since 1970 that the live drifting or bad state began.
        var thresholdSince: TimeInterval?
        /// Why the last attempt did nothing, or why it failed.
        var notice: String?
        var lastRecord: Record?
        var judgedCount: Int
        var total: Int
        /// The labels "both wrong" offers, so the Watch never keeps its own copy.
        var trueClassOptions: [String]
        /// Classification attempts so far, refused ones included. The Watch notes this when it
        /// sends a tap, and the first status with a higher count is the answer to that tap.
        /// Without it, a routine once-a-second status arriving first would look like the answer.
        var attempts: Int
        /// Seconds between a Watch tap and the capture, so the Watch can count down.
        var captureDelay: TimeInterval

        /// Property-list types only, as `WCSession` requires. Absent values are left out rather
        /// than sent as placeholders.
        var message: [String: Any] {
            var m: [String: Any] = [
                "type": MessageType.status,
                "enabled": enabled,
                "calibrated": calibrated,
                "tracking": tracking,
                "thr": thresholdState,
                "judgedCount": judgedCount,
                "total": total,
                "trueClassOptions": trueClassOptions,
                "attempts": attempts,
                "captureDelay": captureDelay,
            ]
            if let thresholdSince { m["thrSince"] = thresholdSince }
            if let notice { m["notice"] = notice }
            if let r = lastRecord {
                m["recordID"] = r.id.uuidString
                m["thrAtCapture"] = r.thresholdStateAtCapture
                m["capturedAt"] = r.capturedAt
                if let c = r.jevClass { m["jevClass"] = c }
                if let c = r.jevConfidence { m["jevConfidence"] = c }
                if let j = r.judged { m["judged"] = j }
                if r.discarded { m["discarded"] = true }
            }
            return m
        }
    }

    /// A posture state as a name, plus when it began for the two states that have a start.
    static func stateName(_ state: PostureState) -> (String, TimeInterval?) {
        switch state {
        case .absent:              return ("absent", nil)
        case .calibrating:         return ("calibrating", nil)
        case .good:                return ("good", nil)
        case .drifting(let since): return ("drifting", since)
        case .bad(let since):      return ("bad", since)
        }
    }
}
