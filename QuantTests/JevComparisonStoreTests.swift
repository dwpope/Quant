import XCTest
import PostureLogic
import simd
@testable import Quant

/// The dataset step 3c will measure from.
///
/// Each record has to answer "was Jev better than the thresholds here?" **without re-running
/// anything**, which is why it carries the exact payload that was sent AND the baseline it was
/// relative to. The metrics are all baseline-relative deltas and the live baseline is wiped on
/// recalibration and stale after an hour, so a record without it is uninterpretable later — the
/// same reason 3a put the baseline in `SessionMetadata`.
@MainActor
final class JevComparisonStoreTests: XCTestCase {

    private var fileURL: URL {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jev-comparisons-\(key).json")
    }

    override func setUpWithError() throws {
        JevComparisonStore.flushPendingWrites()
        try? FileManager.default.removeItem(at: fileURL)
    }

    override func tearDownWithError() throws {
        JevComparisonStore.flushPendingWrites()
        try? FileManager.default.removeItem(at: fileURL)
    }

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
            baseline: makeBaseline())!
    }

    private func makeBaseline() -> Baseline {
        Baseline(timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                 shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0), headPosition: SIMD3<Float>(0.5, 0.8, 0),
                 torsoAngle: 3, shoulderTwist: 1, shoulderWidth: 0.2, depthAvailable: false,
                 neckHeight: 0.35)
    }

    private func makeRecord(
        at date: Date = Date(),
        jev: JevVerdict? = JevVerdict(posture: "chair_swivel", confidence: 0.81,
                                      probabilities: ["chair_swivel": 0.81], model: "jev-1.13.0"),
        error: String? = nil
    ) -> JevComparisonRecord {
        JevComparisonRecord(
            id: UUID(), capturedAt: date, features: makeFeatures(), baseline: makeBaseline(),
            thresholdState: .bad(since: 12), jev: jev, jevError: error)
    }

    func test_add_exposesTheRecord() {
        let store = JevComparisonStore()
        store.add(makeRecord())

        XCTAssertEqual(store.comparisons.count, 1)
        XCTAssertEqual(store.comparisons.first?.jev?.posture, "chair_swivel")
    }

    func test_records_areSortedByCaptureTime() {
        let store = JevComparisonStore()
        let later = makeRecord(at: Date(timeIntervalSince1970: 200))
        let earlier = makeRecord(at: Date(timeIntervalSince1970: 100))

        store.add(later)
        store.add(earlier)

        XCTAssertEqual(store.comparisons.map(\.capturedAt),
                       [earlier.capturedAt, later.capturedAt])
    }

    /// The whole point of the one-tap control: the user's verdict lands on the record.
    func test_setUserVerdict_recordsWhoWasRight() {
        let store = JevComparisonStore()
        let record = makeRecord()
        store.add(record)

        store.setUserVerdict(id: record.id, verdict: .jevWasRight, trueClass: nil)

        XCTAssertEqual(store.comparisons.first?.userVerdict, .jevWasRight)
    }

    func test_setUserVerdict_canRecordWhatItActuallyWasWhenBothWereWrong() {
        let store = JevComparisonStore()
        let record = makeRecord()
        store.add(record)

        store.setUserVerdict(id: record.id, verdict: .bothWrong, trueClass: .stretching)

        XCTAssertEqual(store.comparisons.first?.userVerdict, .bothWrong)
        XCTAssertEqual(store.comparisons.first?.trueClass, .stretching)
    }

    func test_setUserVerdict_isANoOpForAnUnknownId() {
        let store = JevComparisonStore()
        store.add(makeRecord())

        store.setUserVerdict(id: UUID(), verdict: .jevWasRight, trueClass: nil)

        XCTAssertNil(store.comparisons.first?.userVerdict)
    }

    /// A failed classification is still evidence — it records that Jev was unavailable at a
    /// moment the thresholds had an opinion.
    func test_aFailedClassificationIsStillRecorded() {
        let store = JevComparisonStore()
        store.add(makeRecord(jev: nil, error: "busy(afterAttempts: 4)"))

        XCTAssertNil(store.comparisons.first?.jev)
        XCTAssertEqual(store.comparisons.first?.jevError, "busy(afterAttempts: 4)")
    }

    func test_recordsSurviveAReload_withTheBaselineIntact() throws {
        let store = JevComparisonStore()
        let record = makeRecord()
        store.add(record)
        store.setUserVerdict(id: record.id, verdict: .thresholdsWereRight, trueClass: nil)
        JevComparisonStore.flushPendingWrites()

        let reloaded = JevComparisonStore()

        XCTAssertEqual(reloaded.comparisons.count, 1)
        let first = try XCTUnwrap(reloaded.comparisons.first)
        XCTAssertEqual(first.userVerdict, .thresholdsWereRight)
        XCTAssertEqual(first.baseline.shoulderWidth, 0.2, "the baseline must survive or the deltas mean nothing")
        XCTAssertEqual(first.features.lateralLeanInShoulderWidths, 0.25, accuracy: 1e-5)
        XCTAssertEqual(first.thresholdState, .bad(since: 12))
    }
}
