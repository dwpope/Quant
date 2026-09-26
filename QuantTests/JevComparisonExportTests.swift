import XCTest
import PostureLogic
import simd
@testable import Quant

/// Getting the dataset off the phone.
///
/// Without this the records accumulate in the app's private container and step 3c cannot
/// measure anything while Dave is testing remotely — the sip training path has had a ShareLink
/// export for months and the Jev path had none.
@MainActor
final class JevComparisonExportTests: XCTestCase {

    private var storeFile: URL {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jev-comparisons-\(key).json")
    }

    override func setUpWithError() throws {
        JevComparisonStore.flushPendingWrites()
        try? FileManager.default.removeItem(at: storeFile)
    }

    override func tearDownWithError() throws {
        JevComparisonStore.flushPendingWrites()
        try? FileManager.default.removeItem(at: storeFile)
    }

    private func makeRecord(adjudicated: Bool) -> JevComparisonRecord {
        let baseline = Baseline(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0), headPosition: SIMD3<Float>(0.5, 0.8, 0),
            torsoAngle: 3, shoulderTwist: 1, shoulderWidth: 0.2, depthAvailable: false,
            neckHeight: 0.35)
        let features = JevFeatures.make(
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
            baseline: baseline)!
        return JevComparisonRecord(
            id: UUID(), capturedAt: Date(), features: features, baseline: baseline,
            thresholdState: .bad(since: 12),
            jev: JevVerdict(posture: "chair_swivel", confidence: 0.81,
                            probabilities: ["chair_swivel": 0.81], model: "jev-1.13.0"),
            jevError: nil,
            userVerdict: adjudicated ? .jevWasRight : nil)
    }

    func test_export_writesOneLinePerRecord() throws {
        let store = JevComparisonStore()
        store.add(makeRecord(adjudicated: true))
        store.add(makeRecord(adjudicated: false))

        let url = try store.exportJSONL()
        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)

        XCTAssertEqual(lines.count, 2)
        for line in lines {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8)),
                             "every line must be independently parseable")
        }
    }

    /// Unadjudicated records are exported too. They lack ground truth, but they still record
    /// what both sides answered at the same moment, which measures agreement — and filtering
    /// them out here would silently discard evidence 3c might want.
    func test_export_includesRecordsWithNoAdjudication() throws {
        let store = JevComparisonStore()
        store.add(makeRecord(adjudicated: false))

        let url = try store.exportJSONL()
        let line = try XCTUnwrap(try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n").first)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])

        XCTAssertNil(json["userVerdict"])
        XCTAssertNotNil(json["jev"])
    }

    /// The payload and the baseline must survive the round trip, or the export is unusable:
    /// every metric is a delta from that baseline.
    func test_export_carriesTheFeaturesAndTheBaseline() throws {
        let store = JevComparisonStore()
        store.add(makeRecord(adjudicated: true))

        let url = try store.exportJSONL()
        let line = try XCTUnwrap(try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n").first)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])

        let features = try XCTUnwrap(json["features"] as? [String: Any])
        XCTAssertNotNil(features["lateral_lean_in_shoulder_widths"])
        XCTAssertNotNil(json["baseline"])
        XCTAssertEqual(json["userVerdict"] as? String, "jevWasRight")
    }

    func test_export_namesTheFileByDate() throws {
        let store = JevComparisonStore()
        store.add(makeRecord(adjudicated: true))

        let name = try store.exportJSONL().lastPathComponent

        XCTAssertTrue(name.hasPrefix("jev-comparisons-"), name)
        XCTAssertTrue(name.hasSuffix(".jsonl"), name)
    }

    func test_export_ofAnEmptyStoreProducesAnEmptyFile() throws {
        let url = try JevComparisonStore().exportJSONL()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "")
    }
}
