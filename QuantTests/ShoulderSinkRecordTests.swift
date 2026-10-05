import XCTest
import PostureLogic
import simd
@testable import Quant

/// Each Jev capture keeps the shoulder sink at the pose (2026-10-05), so the next session can show
/// whether it separates a sinking slouch from sitting upright. Recorded locally only: it isn't
/// part of what Jev is sent.
@MainActor
final class ShoulderSinkRecordTests: XCTestCase {

    private var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    private func clean() {
        JevComparisonStore.flushPendingWrites()
        for name in (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []
        where name.hasPrefix("jev-comparisons-") {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent(name))
        }
    }
    override func setUpWithError() throws { clean() }
    override func tearDownWithError() throws { clean() }

    private func features() -> JevFeatures {
        JevFeatures.make(
            sample: PoseSample(timestamp: 0, depthMode: .twoDOnly, headPosition: SIMD3<Float>(0.5, 0.8, 0),
                               shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0), leftShoulder: SIMD3<Float>(0.4, 0.6, 0),
                               rightShoulder: SIMD3<Float>(0.6, 0.6, 0), torsoAngle: 5, headForwardOffset: 0,
                               shoulderTwist: 0, shoulderWidthRaw: 0.3, trackingQuality: .good),
            metrics: RawMetrics(timestamp: 0, forwardCreep: 0.01, headDrop: 0.01, shoulderRounding: 0,
                                lateralLean: 0, twist: 0, movementLevel: 0, headMovementPattern: .still),
            baseline: Baseline(timestamp: Date(), shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
                               headPosition: SIMD3<Float>(0.5, 0.8, 0), torsoAngle: 3,
                               shoulderWidth: 0.3, depthAvailable: false))!
    }

    func test_aCapture_keepsTheSinkAtThePose_andExportsIt() throws {
        let model = AppModel()
        let atPose = JevCaptureContext(thresholdState: .good, thresholds: PostureThresholds(),
                                       taskMode: .reading, shoulderSink: 0.12)
        model.recordJevComparison(features: features(), verdict: nil, error: "test", atPose: atPose)
        XCTAssertEqual(try XCTUnwrap(model.jevComparisonStore.comparisons.last?.shoulderSink), 0.12, accuracy: 1e-6)

        let line = try XCTUnwrap(try String(contentsOf: model.jevComparisonStore.exportJSONL(), encoding: .utf8)
            .split(separator: "\n").last)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual((object["shoulderSink"] as? Double) ?? .nan, 0.12, accuracy: 1e-6)
        XCTAssertNil((object["features"] as? [String: Any])?["shoulder_sink"], "not sent to Jev")
    }

    func test_aRecordSavedBeforeThis_hasNoSink() throws {
        let record = JevComparisonRecord(
            id: UUID(), capturedAt: Date(), features: features(),
            baseline: Baseline(timestamp: Date(), shoulderMidpoint: .zero, headPosition: .zero,
                               torsoAngle: 0, shoulderWidth: 0.3, depthAvailable: false),
            thresholdState: .good, jev: nil, jevError: "x")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object.removeValue(forKey: "shoulderSink")
        let decoded = try JSONDecoder().decode(JevComparisonRecord.self,
                                               from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.shoulderSink)
    }
}
