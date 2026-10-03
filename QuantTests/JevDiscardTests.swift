import XCTest
import PostureLogic
import simd
@testable import Quant

/// Discarding a capture made by mistake.
///
/// Every capture that reaches Jev is saved and exported, including ones taken by accident, and
/// nothing could remove them. Discarding marks a record rather than deleting it: the export keeps
/// it, flagged, and the analysis leaves it out. A dropped record could hide a pattern; a flagged
/// one can still be counted or excluded on purpose.
@MainActor
final class JevDiscardTests: XCTestCase {

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func removeAllDayFiles() {
        JevComparisonStore.flushPendingWrites()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []
        for name in names where name.hasPrefix("jev-comparisons-") {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent(name))
        }
    }

    override func setUpWithError() throws { removeAllDayFiles() }
    override func tearDownWithError() throws { removeAllDayFiles() }

    private func makeFeatures() -> JevFeatures {
        JevFeatures.make(
            sample: PoseSample(
                timestamp: 0, depthMode: .twoDOnly,
                headPosition: SIMD3<Float>(0.5, 0.8, 0), shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
                leftShoulder: SIMD3<Float>(0.4, 0.6, 0), rightShoulder: SIMD3<Float>(0.6, 0.6, 0),
                torsoAngle: 5, headForwardOffset: 0, shoulderTwist: 0,
                shoulderWidthRaw: 0.3, trackingQuality: .good),
            metrics: RawMetrics(
                timestamp: 0, forwardCreep: -0.09, headDrop: 0.01, shoulderRounding: 1,
                lateralLean: 0.05, twist: 1, movementLevel: 0, headMovementPattern: .still,
                lateralLeanSigned: 0.05, twistSigned: 1),
            baseline: Baseline(
                timestamp: Date(), shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
                headPosition: SIMD3<Float>(0.5, 0.8, 0), torsoAngle: 3, shoulderTwist: 1,
                shoulderWidth: 0.2, depthAvailable: false, neckHeight: 0.35))!
    }

    private func verdict() -> JevVerdict {
        JevVerdict(posture: "lean", confidence: 0.8, probabilities: ["lean": 0.8], model: "jev-test")
    }

    // MARK: - The Watch's message (golden copy; the Watch's tests assert the same dictionary)

    func test_decodes_discard() {
        let id = UUID()
        XCTAssertEqual(JevRemote.Command(message: ["type": "jevDiscard", "recordID": id.uuidString]),
                       .discard(recordID: id))
    }

    func test_rejects_aDiscardWithoutAReadableRecord() {
        XCTAssertNil(JevRemote.Command(message: ["type": "jevDiscard"]))
        XCTAssertNil(JevRemote.Command(message: ["type": "jevDiscard", "recordID": "nope"]))
    }

    func test_status_saysWhenTheLastRecordIsDiscarded_andOtherwiseOmitsIt() {
        let id = UUID()
        func message(discarded: Bool) -> NSDictionary {
            JevRemote.Status(
                enabled: true, calibrated: true, tracking: "good", thresholdState: "good",
                thresholdSince: nil, notice: nil,
                lastRecord: .init(id: id, jevClass: "lean", jevConfidence: 0.8,
                                  thresholdStateAtCapture: "good", capturedAt: 1, judged: nil,
                                  discarded: discarded),
                judgedCount: 0, total: 1, trueClassOptions: [], attempts: 1, captureDelay: 3)
                .message as NSDictionary
        }
        XCTAssertEqual(message(discarded: true)["discarded"] as? Bool, true)
        XCTAssertNil(message(discarded: false)["discarded"])
    }

    // MARK: - The phone acting on it

    func test_discard_marksTheNamedRecord_andTheStatusSaysSo() async throws {
        let model = AppModel()
        model.recordJevComparison(features: makeFeatures(), verdict: verdict(), error: nil)
        let id = try XCTUnwrap(model.jevComparisonStore.comparisons.last?.id)

        await model.handleJevRemote(.discard(recordID: id))

        XCTAssertTrue(try XCTUnwrap(model.jevComparisonStore.comparisons.last).isDiscarded)
        XCTAssertEqual(model.jevRemoteStatus().lastRecord?.discarded, true)
    }

    func test_discard_ofAnUnknownRecord_changesNothing() async {
        let model = AppModel()
        model.recordJevComparison(features: makeFeatures(), verdict: verdict(), error: nil)

        await model.handleJevRemote(.discard(recordID: UUID()))

        XCTAssertFalse(model.jevComparisonStore.comparisons[0].isDiscarded)
    }

    /// A capture judged and then found to be a mistake keeps its judgement, flagged.
    func test_aJudgedRecordCanBeDiscarded_andKeepsItsJudgement() {
        let store = JevComparisonStore()
        let record = JevComparisonRecord(
            id: UUID(), capturedAt: Date(), features: makeFeatures(),
            baseline: Baseline(timestamp: Date(), shoulderMidpoint: .zero, headPosition: .zero,
                               torsoAngle: 0, shoulderWidth: 0.2, depthAvailable: false),
            thresholdState: .good, jev: verdict(), jevError: nil)
        store.add(record)
        store.setUserVerdict(id: record.id, verdict: .jevWasRight, trueClass: nil)

        store.setDiscarded(id: record.id)

        XCTAssertTrue(store.comparisons[0].isDiscarded)
        XCTAssertEqual(store.comparisons[0].userVerdict, .jevWasRight)
    }

    // MARK: - On disk and in the export

    func test_discarded_survivesTheFile_andIsFlaggedInTheExport() async throws {
        let model = AppModel()
        model.recordJevComparison(features: makeFeatures(), verdict: verdict(), error: nil)
        model.recordJevComparison(features: makeFeatures(), verdict: verdict(), error: nil)
        let firstID = model.jevComparisonStore.comparisons[0].id
        await model.handleJevRemote(.discard(recordID: firstID))
        JevComparisonStore.flushPendingWrites()

        let reloaded = JevComparisonStore()
        let match = reloaded.comparisons.first(where: { $0.id == firstID })
        XCTAssertTrue(try XCTUnwrap(match).isDiscarded)

        let lines = try String(contentsOf: reloaded.exportJSONL(), encoding: .utf8)
            .split(separator: "\n")
            .map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        XCTAssertEqual(lines.count, 2, "a discarded record stays in the export")
        XCTAssertEqual(lines.filter { $0["discarded"] as? Bool == true }.count, 1)
    }

    /// Records saved before discarding existed have no such field. They're not discarded.
    func test_aRecordWithoutTheField_isNotDiscarded() throws {
        let record = JevComparisonRecord(
            id: UUID(), capturedAt: Date(), features: makeFeatures(),
            baseline: Baseline(timestamp: Date(), shoulderMidpoint: .zero, headPosition: .zero,
                               torsoAngle: 0, shoulderWidth: 0.2, depthAvailable: false),
            thresholdState: .good, jev: verdict(), jevError: nil)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        XCTAssertNil(object["discarded"], "not written unless set")

        let decoded = try JSONDecoder().decode(
            JevComparisonRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(decoded.isDiscarded)
    }
}
