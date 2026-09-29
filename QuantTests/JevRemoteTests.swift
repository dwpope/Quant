import XCTest
import PostureLogic
import simd
@testable import Quant

/// The Watch as a remote for Jev captures.
///
/// Classify now captures the pose at the instant it is tapped. With the phone out of reach,
/// tapping it meant leaning toward it, so the capture recorded the reach rather than the posture
/// being held. The Watch sends the tap instead, and the phone reports back what it captured.
///
/// The Watch and the phone are separate targets with no shared code, so the message format is a
/// contract. The dictionaries below are its golden copy; the Watch's own tests assert the same
/// dictionaries from the other side.
@MainActor
final class JevRemoteTests: XCTestCase {

    private let baselineKey = "com.quant.savedBaseline"

    /// Same isolation as `JevPacingTests`: every `AppModel()` loads today's comparison file.
    private var comparisonsFile: URL {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jev-comparisons-\(key).json")
    }

    override func setUpWithError() throws {
        UserDefaults.standard.removeObject(forKey: baselineKey)
        JevComparisonStore.flushPendingWrites()
        try? FileManager.default.removeItem(at: comparisonsFile)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: baselineKey)
        JevComparisonStore.flushPendingWrites()
        try? FileManager.default.removeItem(at: comparisonsFile)
    }

    // MARK: - Fixtures

    private func makeFeatures() -> JevFeatures {
        let sample = PoseSample(
            timestamp: 0, depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0.5, 0.8, 0), shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
            leftShoulder: SIMD3<Float>(0.4, 0.6, 0), rightShoulder: SIMD3<Float>(0.6, 0.6, 0),
            torsoAngle: 5, headForwardOffset: 0, shoulderTwist: 0,
            shoulderWidthRaw: 0.3, trackingQuality: .good)
        let metrics = RawMetrics(
            timestamp: 0, forwardCreep: -0.09, headDrop: 0.01, shoulderRounding: 1,
            lateralLean: 0.05, twist: 1, movementLevel: 0, headMovementPattern: .still,
            lateralLeanSigned: 0.05, twistSigned: 1)
        return JevFeatures.make(sample: sample, metrics: metrics, baseline: makeBaseline())!
    }

    private func makeBaseline() -> Baseline {
        Baseline(timestamp: Date(), shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
                 headPosition: SIMD3<Float>(0.5, 0.8, 0), torsoAngle: 3, shoulderTwist: 1,
                 shoulderWidth: 0.2, depthAvailable: false, neckHeight: 0.35)
    }

    private func swivelVerdict() -> JevVerdict {
        JevVerdict(posture: "chair_swivel", confidence: 0.81,
                   probabilities: ["chair_swivel": 0.81, "lean": 0.19], model: "jev-test")
    }

    // MARK: - Commands from the Watch (golden messages)

    func test_decodes_classify() {
        XCTAssertEqual(JevRemote.Command(message: ["type": "jevClassify"]), .classify)
    }

    func test_decodes_statusRequest() {
        XCTAssertEqual(JevRemote.Command(message: ["type": "jevStatusRequest"]), .statusRequest)
    }

    func test_decodes_judge_withoutTrueClass() throws {
        let id = UUID()
        let message: [String: Any] = [
            "type": "jevJudge", "recordID": id.uuidString, "verdict": "jevWasRight",
        ]
        XCTAssertEqual(JevRemote.Command(message: message),
                       .judge(recordID: id, verdict: .jevWasRight, trueClass: nil))
    }

    func test_decodes_judge_bothWrong_withTrueClass() throws {
        let id = UUID()
        let message: [String: Any] = [
            "type": "jevJudge", "recordID": id.uuidString, "verdict": "bothWrong",
            "trueClass": "chair_swivel",
        ]
        XCTAssertEqual(JevRemote.Command(message: message),
                       .judge(recordID: id, verdict: .bothWrong, trueClass: .chairSwivel))
    }

    /// A judgement with no readable record or verdict is dropped, never guessed at: it is
    /// ground truth.
    func test_rejects_malformedJudgements() {
        let id = UUID().uuidString
        let bad: [[String: Any]] = [
            ["type": "jevJudge", "verdict": "jevWasRight"],
            ["type": "jevJudge", "recordID": "not-a-uuid", "verdict": "jevWasRight"],
            ["type": "jevJudge", "recordID": id, "verdict": "maybe"],
        ]
        for message in bad {
            XCTAssertNil(JevRemote.Command(message: message), "\(message) should be rejected")
        }
    }

    /// An unknown true class, such as an old recording tag from a stale Watch screen, keeps the
    /// "both wrong" and drops only the class. Same rule the store applies to saved records.
    func test_unknownTrueClass_keepsTheJudgement_withoutAClass() {
        let id = UUID()
        for legacy in ["slouching", "reading", "flying"] {
            let message: [String: Any] = [
                "type": "jevJudge", "recordID": id.uuidString, "verdict": "bothWrong",
                "trueClass": legacy,
            ]
            XCTAssertEqual(JevRemote.Command(message: message),
                           .judge(recordID: id, verdict: .bothWrong, trueClass: nil))
        }
    }

    /// The Watch's older messages keep their existing handlers.
    func test_ignores_messagesThatAreNotForTheRemote() {
        for type in ["nudge", "calibrate", "settings", "jevStatus"] {
            XCTAssertNil(JevRemote.Command(message: ["type": type]))
        }
        XCTAssertNil(JevRemote.Command(message: [:]))
    }

    // MARK: - Status to the Watch (golden message)

    func test_encodes_status_withARecord() {
        let id = UUID()
        let status = JevRemote.Status(
            enabled: true, calibrated: true, tracking: "good",
            thresholdState: "drifting", thresholdSince: 1000, notice: nil,
            lastRecord: .init(id: id, jevClass: "chair_swivel", jevConfidence: 0.81,
                              thresholdStateAtCapture: "drifting", capturedAt: 2000, judged: nil),
            judgedCount: 1, total: 2, trueClassOptions: ["good_posture", "slouch"],
            attempts: 3)

        let expected: [String: Any] = [
            "type": "jevStatus", "enabled": true, "calibrated": true, "tracking": "good",
            "thr": "drifting", "thrSince": 1000.0,
            "recordID": id.uuidString, "jevClass": "chair_swivel", "jevConfidence": 0.81,
            "thrAtCapture": "drifting", "capturedAt": 2000.0,
            "judgedCount": 1, "total": 2, "trueClassOptions": ["good_posture", "slouch"],
            "attempts": 3,
        ]
        XCTAssertEqual(status.message as NSDictionary, expected as NSDictionary)
    }

    /// Absent values are left out rather than sent as placeholders, so the Watch can tell "no
    /// record yet" from a record with an empty class.
    func test_encodes_status_withoutARecord_omitsItsKeys() {
        let status = JevRemote.Status(
            enabled: false, calibrated: false, tracking: "lost",
            thresholdState: "absent", thresholdSince: nil, notice: "classifier is off",
            lastRecord: nil, judgedCount: 0, total: 0, trueClassOptions: [], attempts: 0)

        let expected: [String: Any] = [
            "type": "jevStatus", "enabled": false, "calibrated": false, "tracking": "lost",
            "thr": "absent", "notice": "classifier is off",
            "judgedCount": 0, "total": 0, "trueClassOptions": [String](), "attempts": 0,
        ]
        XCTAssertEqual(status.message as NSDictionary, expected as NSDictionary)
    }

    func test_stateNames() {
        XCTAssertTrue(JevRemote.stateName(.absent) == ("absent", nil))
        XCTAssertTrue(JevRemote.stateName(.calibrating) == ("calibrating", nil))
        XCTAssertTrue(JevRemote.stateName(.good) == ("good", nil))
        XCTAssertTrue(JevRemote.stateName(.drifting(since: 12)) == ("drifting", 12))
        XCTAssertTrue(JevRemote.stateName(.bad(since: 34)) == ("bad", 34))
    }

    // MARK: - What the phone reports

    func test_status_reportsTheLastRecordAsCaptured_notTheLiveState() {
        let model = AppModel()
        model.useJevClassifier = true
        model.postureState = .drifting(since: 500)
        model.recordJevComparison(features: makeFeatures(), verdict: swivelVerdict(), error: nil)
        model.postureState = .good

        let status = model.jevRemoteStatus()

        XCTAssertEqual(status.thresholdState, "good", "live state, for positioning")
        XCTAssertEqual(status.lastRecord?.thresholdStateAtCapture, "drifting",
                       "the state the judgement is about")
        XCTAssertEqual(status.lastRecord?.jevClass, "chair_swivel")
        XCTAssertEqual(status.lastRecord?.jevConfidence ?? 0, 0.81, accuracy: 1e-9)
        XCTAssertEqual(status.lastRecord?.id, model.jevComparisonStore.comparisons.last?.id)
        XCTAssertEqual(status.total, 1)
        XCTAssertEqual(status.judgedCount, 0)
        XCTAssertEqual(status.trueClassOptions,
                       ["good_posture", "slouch", "lean", "chair_swivel", "ambiguous"],
                       "Jev's classes, so a Watch judgement compares like with like")
    }

    func test_status_aFailedCall_isARecordWithNoClass() {
        let model = AppModel()
        model.recordJevComparison(features: makeFeatures(), verdict: nil, error: "unreachable")

        let status = model.jevRemoteStatus()

        XCTAssertNotNil(status.lastRecord)
        XCTAssertNil(status.lastRecord?.jevClass)
        XCTAssertEqual(status.notice, "unreachable")
    }

    // MARK: - Acting on commands

    /// The Watch cannot switch the classifier on. That switch is the privacy boundary, so it
    /// stays on the phone, and the Watch is told why nothing happened.
    func test_classify_whenOff_sendsNothing_andSaysWhy() async {
        let model = AppModel()
        XCTAssertFalse(model.useJevClassifier)

        await model.handleJevRemote(.classify)

        XCTAssertEqual(model.latestJevError, JevGate.disabled.message)
        XCTAssertTrue(model.jevComparisonStore.comparisons.isEmpty)
        XCTAssertEqual(model.jevRemoteStatus().notice, JevGate.disabled.message)
    }

    /// A refused tap still counts, so the Watch can tell its answer from a routine update.
    func test_everyClassifyAttempt_isCounted_refusedOnesToo() async {
        let model = AppModel()
        XCTAssertEqual(model.jevRemoteStatus().attempts, 0)

        await model.handleJevRemote(.classify)
        await model.handleJevRemote(.classify)

        XCTAssertEqual(model.jevRemoteStatus().attempts, 2)
    }

    func test_judgingAndStatusRequests_areNotAttempts() async {
        let model = AppModel()
        model.recordJevComparison(features: makeFeatures(), verdict: swivelVerdict(), error: nil)
        let id = model.jevComparisonStore.comparisons[0].id

        await model.handleJevRemote(.statusRequest)
        await model.handleJevRemote(.judge(recordID: id, verdict: .jevWasRight, trueClass: nil))

        XCTAssertEqual(model.jevRemoteStatus().attempts, 0)
    }

    /// The judgement names its record. If a second capture lands between the Watch showing a
    /// verdict and the tap, the judgement still goes to the verdict that was on screen.
    func test_judge_appliesToTheNamedRecord_notJustTheLatest() async throws {
        let model = AppModel()
        model.recordJevComparison(features: makeFeatures(), verdict: swivelVerdict(), error: nil)
        let first = try XCTUnwrap(model.jevComparisonStore.comparisons.first?.id)
        model.recordJevComparison(features: makeFeatures(), verdict: swivelVerdict(), error: nil)

        await model.handleJevRemote(.judge(recordID: first, verdict: .bothWrong, trueClass: .slouch))

        let records = model.jevComparisonStore.comparisons
        XCTAssertEqual(records[0].userVerdict, .bothWrong)
        XCTAssertEqual(records[0].trueClass, .slouch)
        XCTAssertNil(records[1].userVerdict)
        XCTAssertEqual(model.jevRemoteStatus().judgedCount, 1)
    }

    func test_judge_unknownRecord_changesNothing() async {
        let model = AppModel()
        model.recordJevComparison(features: makeFeatures(), verdict: swivelVerdict(), error: nil)

        await model.handleJevRemote(.judge(recordID: UUID(), verdict: .jevWasRight, trueClass: nil))

        XCTAssertNil(model.jevComparisonStore.comparisons[0].userVerdict)
    }

    func test_status_showsTheJudgementOnTheLastRecord() async throws {
        let model = AppModel()
        model.recordJevComparison(features: makeFeatures(), verdict: swivelVerdict(), error: nil)
        let id = try XCTUnwrap(model.jevComparisonStore.comparisons.last?.id)

        await model.handleJevRemote(.judge(recordID: id, verdict: .thresholdsWereRight, trueClass: nil))

        XCTAssertEqual(model.jevRemoteStatus().lastRecord?.judged, "thresholdsWereRight")
    }
}
