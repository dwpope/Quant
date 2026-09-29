import Foundation
import Testing
@testable import QuantWatch_Watch_App

/// The Watch's side of the Jev remote contract.
///
/// The golden dictionaries here are the same ones `QuantTests/JevRemoteTests` asserts on the
/// phone. The two targets share no code, so these copies are what keep the two ends agreeing.
struct JevRemoteMessageTests {

    // MARK: - Commands the Watch sends

    @Test func classifyMessage() {
        #expect(JevRemoteMessage.classify() as NSDictionary == ["type": "jevClassify"] as NSDictionary)
    }

    @Test func statusRequestMessage() {
        #expect(JevRemoteMessage.statusRequest() as NSDictionary
                == ["type": "jevStatusRequest"] as NSDictionary)
    }

    @Test func judgeMessage_withoutTrueClass() {
        let id = UUID()
        let expected: [String: Any] = [
            "type": "jevJudge", "recordID": id.uuidString, "verdict": "jevWasRight",
        ]
        #expect(JevRemoteMessage.judge(recordID: id, verdict: .jevWasRight, trueClass: nil) as NSDictionary
                == expected as NSDictionary)
    }

    @Test func judgeMessage_bothWrong_withTrueClass() {
        let id = UUID()
        let expected: [String: Any] = [
            "type": "jevJudge", "recordID": id.uuidString, "verdict": "bothWrong",
            "trueClass": "chair_swivel",
        ]
        #expect(JevRemoteMessage.judge(recordID: id, verdict: .bothWrong, trueClass: "chair_swivel")
                as NSDictionary == expected as NSDictionary)
    }

    // MARK: - Status the phone sends

    @Test func decodesStatus_withARecord() throws {
        let id = UUID()
        let message: [String: Any] = [
            "type": "jevStatus", "enabled": true, "calibrated": true, "tracking": "good",
            "thr": "drifting", "thrSince": 1000.0,
            "recordID": id.uuidString, "jevClass": "chair_swivel", "jevConfidence": 0.81,
            "thrAtCapture": "drifting", "capturedAt": 2000.0,
            "judgedCount": 1, "total": 2, "trueClassOptions": ["good_posture", "slouch"],
            "attempts": 3,
        ]

        let status = try #require(JevRemoteStatus(message: message))

        #expect(status.enabled)
        #expect(status.calibrated)
        #expect(status.tracking == "good")
        #expect(status.thresholdState == "drifting")
        #expect(status.thresholdSince == Date(timeIntervalSince1970: 1000))
        #expect(status.notice == nil)
        #expect(status.judgedCount == 1)
        #expect(status.total == 2)
        #expect(status.trueClassOptions == ["good_posture", "slouch"])
        #expect(status.attempts == 3)
        let record = try #require(status.lastRecord)
        #expect(record.id == id)
        #expect(record.jevClass == "chair_swivel")
        #expect(record.jevConfidence == 0.81)
        #expect(record.thresholdStateAtCapture == "drifting")
        #expect(record.capturedAt == Date(timeIntervalSince1970: 2000))
        #expect(record.judged == nil)
    }

    @Test func decodesStatus_withoutARecord() throws {
        let message: [String: Any] = [
            "type": "jevStatus", "enabled": false, "calibrated": false, "tracking": "lost",
            "thr": "absent", "notice": "classifier is off",
            "judgedCount": 0, "total": 0, "trueClassOptions": [String](), "attempts": 0,
        ]

        let status = try #require(JevRemoteStatus(message: message))

        #expect(!status.enabled)
        #expect(status.notice == "classifier is off")
        #expect(status.lastRecord == nil)
        #expect(status.thresholdSince == nil)
    }

    @Test func decodesTheJudgement() throws {
        let message: [String: Any] = [
            "type": "jevStatus", "enabled": true, "calibrated": true, "tracking": "good",
            "thr": "good", "recordID": UUID().uuidString, "jevClass": "slouch",
            "jevConfidence": 0.7, "thrAtCapture": "good", "capturedAt": 5.0,
            "judged": "thresholdsWereRight",
            "judgedCount": 1, "total": 1, "trueClassOptions": [String](), "attempts": 1,
        ]
        let status = try #require(JevRemoteStatus(message: message))
        #expect(status.lastRecord?.judged == .thresholdsWereRight)
    }

    @Test func rejectsOtherMessages() {
        #expect(JevRemoteStatus(message: ["type": "nudge"]) == nil)
        #expect(JevRemoteStatus(message: ["type": "jevStatus"]) == nil, "required keys missing")
    }

    // MARK: - Which status answers a tap

    private func status(attempts: Int, recordID: UUID?, jevClass: String?,
                        notice: String? = nil) -> JevRemoteStatus {
        var m: [String: Any] = [
            "type": "jevStatus", "enabled": true, "calibrated": true, "tracking": "good",
            "thr": "good", "judgedCount": 0, "total": 1, "trueClassOptions": [String](),
            "attempts": attempts,
        ]
        if let recordID {
            m["recordID"] = recordID.uuidString
            m["thrAtCapture"] = "good"
            m["capturedAt"] = 1.0
            if let jevClass { m["jevClass"] = jevClass; m["jevConfidence"] = 0.9 }
        }
        if let notice { m["notice"] = notice }
        return JevRemoteStatus(message: m)!
    }

    /// A routine once-a-second status can arrive between the tap and its answer.
    @Test func aStatusWithoutANewAttempt_isNotTheAnswer() {
        let old = UUID()
        let routine = status(attempts: 4, recordID: old, jevClass: "slouch")
        #expect(JevRemoteStatus.outcome(of: routine, previousRecordID: old, attemptsWhenSent: 4) == nil)
    }

    @Test func aNewRecordWithAClass_isACapture() {
        let old = UUID(), new = UUID()
        let answer = status(attempts: 5, recordID: new, jevClass: "chair_swivel")
        #expect(JevRemoteStatus.outcome(of: answer, previousRecordID: old, attemptsWhenSent: 4) == .captured)
    }

    @Test func aNewRecordWithoutAClass_isAFailedCall() {
        let answer = status(attempts: 5, recordID: UUID(), jevClass: nil, notice: "unreachable")
        #expect(JevRemoteStatus.outcome(of: answer, previousRecordID: nil, attemptsWhenSent: 4) == .failed)
    }

    @Test func aNewAttemptWithNoNewRecord_wasRefused() {
        let old = UUID()
        let answer = status(attempts: 5, recordID: old, jevClass: "slouch", notice: "wait 3s")
        #expect(JevRemoteStatus.outcome(of: answer, previousRecordID: old, attemptsWhenSent: 4) == .refused)
    }

    // MARK: - Display

    @Test func labelsReadAsWords() {
        #expect(JevRemoteStatus.displayName("goodPosture") == "good posture")
        #expect(JevRemoteStatus.displayName("chair_swivel") == "chair swivel")
        #expect(JevRemoteStatus.displayName("slouching") == "slouching")
    }
}

/// The Watch's handling of a tap and its answer.
@MainActor
struct JevRemoteSessionTests {

    private func status(attempts: Int, recordID: UUID) -> JevRemoteStatus {
        JevRemoteStatus(message: [
            "type": "jevStatus", "enabled": true, "calibrated": true, "tracking": "good",
            "thr": "good", "judgedCount": 0, "total": 1, "trueClassOptions": [String](),
            "attempts": attempts, "recordID": recordID.uuidString, "thrAtCapture": "good",
            "capturedAt": 1.0, "jevClass": "slouch", "jevConfidence": 0.9,
        ])!
    }

    @Test func aTapStaysBusy_throughARoutineStatus_untilItsAnswer() {
        let delegate = WatchSessionDelegate()
        let old = UUID()
        delegate.receiveJevStatus(status(attempts: 4, recordID: old))

        delegate.beginJevTap()
        #expect(delegate.jevBusy)

        delegate.receiveJevStatus(status(attempts: 4, recordID: old))
        #expect(delegate.jevBusy, "a routine status is not the answer")

        let answer = status(attempts: 5, recordID: UUID())
        delegate.receiveJevStatus(answer)
        #expect(!delegate.jevBusy)
        #expect(delegate.jevStatus == answer)
    }

    @Test func aStatusWithoutATap_justUpdatesTheScreen() {
        let delegate = WatchSessionDelegate()
        let s = status(attempts: 1, recordID: UUID())
        delegate.receiveJevStatus(s)
        #expect(!delegate.jevBusy)
        #expect(delegate.jevStatus == s)
    }
}
