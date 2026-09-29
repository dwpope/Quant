//
//  JevRemoteMessages.swift
//  QuantWatch Watch App
//
//  The Watch's side of the Jev capture remote.
//

import Foundation

/// A judgement on a capture. Raw values match the phone's `JevComparisonRecord.UserVerdict`.
enum JevRemoteVerdict: String, CaseIterable {
    case jevWasRight
    case thresholdsWereRight
    case bothWrong
}

/// Messages the Watch sends to the phone.
///
/// The phone's `Quant/Models/JevRemote.swift` documents the format. This target shares no code
/// with the phone, so `JevRemoteMessageTests` and the phone's `JevRemoteTests` assert the same
/// golden dictionaries from each side. Change both or neither.
enum JevRemoteMessage {
    static func classify() -> [String: Any] { ["type": "jevClassify"] }

    static func statusRequest() -> [String: Any] { ["type": "jevStatusRequest"] }

    static func judge(recordID: UUID, verdict: JevRemoteVerdict, trueClass: String?) -> [String: Any] {
        var m: [String: Any] = [
            "type": "jevJudge", "recordID": recordID.uuidString, "verdict": verdict.rawValue,
        ]
        if let trueClass { m["trueClass"] = trueClass }
        return m
    }
}

/// What the phone reports: enough to get into position before a capture, and to judge it after.
struct JevRemoteStatus: Equatable {

    /// The newest capture, as it was when captured.
    struct Record: Equatable {
        var id: UUID
        /// Nil when the call failed.
        var jevClass: String?
        var jevConfidence: Double?
        /// What the thresholds said at the moment of capture. This is what gets judged.
        var thresholdStateAtCapture: String
        var capturedAt: Date
        var judged: JevRemoteVerdict?
    }

    /// How a tap turned out, once its answer arrives.
    enum Outcome: Equatable {
        /// A new capture with Jev's answer.
        case captured
        /// A new capture, but the call to Jev failed.
        case failed
        /// Nothing captured. The phone refused, and `notice` says why.
        case refused
    }

    var enabled: Bool
    var calibrated: Bool
    var tracking: String
    /// Live, for getting into position.
    var thresholdState: String
    var thresholdSince: Date?
    var notice: String?
    var lastRecord: Record?
    var judgedCount: Int
    var total: Int
    var trueClassOptions: [String]
    var attempts: Int
    /// Seconds the phone waits after a tap before capturing. Zero from a phone build that
    /// predates the delay.
    var captureDelay: TimeInterval

    init?(message: [String: Any]) {
        guard message["type"] as? String == "jevStatus",
              let enabled = message["enabled"] as? Bool,
              let calibrated = message["calibrated"] as? Bool,
              let tracking = message["tracking"] as? String,
              let thr = message["thr"] as? String,
              let judgedCount = message["judgedCount"] as? Int,
              let total = message["total"] as? Int,
              let options = message["trueClassOptions"] as? [String],
              let attempts = message["attempts"] as? Int
        else { return nil }

        self.enabled = enabled
        self.calibrated = calibrated
        self.tracking = tracking
        self.thresholdState = thr
        self.thresholdSince = (message["thrSince"] as? Double).map(Date.init(timeIntervalSince1970:))
        self.notice = message["notice"] as? String
        self.judgedCount = judgedCount
        self.total = total
        self.trueClassOptions = options
        self.attempts = attempts
        self.captureDelay = message["captureDelay"] as? Double ?? 0

        if let idString = message["recordID"] as? String, let id = UUID(uuidString: idString),
           let thrAtCapture = message["thrAtCapture"] as? String,
           let capturedAt = message["capturedAt"] as? Double {
            self.lastRecord = Record(
                id: id,
                jevClass: message["jevClass"] as? String,
                jevConfidence: message["jevConfidence"] as? Double,
                thresholdStateAtCapture: thrAtCapture,
                capturedAt: Date(timeIntervalSince1970: capturedAt),
                judged: (message["judged"] as? String).flatMap(JevRemoteVerdict.init(rawValue:)))
        } else {
            self.lastRecord = nil
        }
    }

    /// Whether `status` answers a tap sent when the phone had counted `attemptsWhenSent`
    /// attempts and the newest record was `previousRecordID`. Nil while still waiting.
    ///
    /// The attempt count, not arrival order, decides it: a routine status sent once a second
    /// can land between the tap and its answer.
    static func outcome(of status: JevRemoteStatus, previousRecordID: UUID?,
                        attemptsWhenSent: Int) -> Outcome? {
        guard status.attempts > attemptsWhenSent else { return nil }
        guard let record = status.lastRecord, record.id != previousRecordID else { return .refused }
        return record.jevClass == nil ? .failed : .captured
    }

    /// Whole seconds left before the phone captures, counting down from the tap. Zero once due.
    static func secondsUntilCapture(tappedAt: Date, now: Date, delay: TimeInterval) -> Int {
        max(0, Int((delay - now.timeIntervalSince(tappedAt)).rounded(.up)))
    }

    /// `goodPosture` and `chair_swivel` as "good posture" and "chair swivel".
    static func displayName(_ raw: String) -> String {
        var out = ""
        for ch in raw {
            if ch == "_" {
                out.append(" ")
            } else if ch.isUppercase {
                out.append(" ")
                out.append(contentsOf: ch.lowercased())
            } else {
                out.append(ch)
            }
        }
        return out
    }
}
