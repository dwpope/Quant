import XCTest
import PostureLogic
import simd
@testable import Quant

/// What the thresholds were doing, and under which limits, at the instant of the pose Jev saw.
///
/// In the first device session the thresholds said "good" through three slouches, one at five
/// times the default forward-creep limit, and the records couldn't say why. Two reasons: the
/// state was read after Jev answered, up to half a second after the pose, and the limits and
/// task mode in force weren't stored at all. Stretching mode switches judgement off entirely.
@MainActor
final class JevCaptureContextTests: XCTestCase {

    private let baselineKey = "com.quant.savedBaseline"
    private let forwardCreepKey = "com.quant.posture.forwardCreep"

    private var comparisonsFile: URL {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jev-comparisons-\(key).json")
    }

    override func setUpWithError() throws {
        UserDefaults.standard.removeObject(forKey: baselineKey)
        UserDefaults.standard.removeObject(forKey: forwardCreepKey)
        JevComparisonStore.flushPendingWrites()
        try? FileManager.default.removeItem(at: comparisonsFile)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: baselineKey)
        UserDefaults.standard.removeObject(forKey: forwardCreepKey)
        JevComparisonStore.flushPendingWrites()
        try? FileManager.default.removeItem(at: comparisonsFile)
    }

    /// Answers like the Worker, after running `during` — the window in which the posture state
    /// used to be read.
    private struct SlowTransport: JevTransport {
        let during: @Sendable () async -> Void
        func post(_ body: Data, to url: URL) async throws -> (Data, Int) {
            await during()
            let verdict = #"{"posture":"lean","confidence":0.8,"probabilities":{"lean":0.8},"model":"jev-test"}"#
            return (Data(verdict.utf8), 200)
        }
    }

    private func readyModel() -> AppModel {
        let model = AppModel()
        model.useJevClassifier = true
        model.latestSample = PoseSample(
            timestamp: 0, depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0.5, 0.8, 0), shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
            leftShoulder: SIMD3<Float>(0.4, 0.6, 0), rightShoulder: SIMD3<Float>(0.6, 0.6, 0),
            torsoAngle: 5, headForwardOffset: 0, shoulderTwist: 0,
            shoulderWidthRaw: 0.3, trackingQuality: .good)
        model.latestMetrics = RawMetrics(
            timestamp: 0, forwardCreep: 0.157, headDrop: 0.01, shoulderRounding: 1,
            lateralLean: 0.05, twist: 1, movementLevel: 0, headMovementPattern: .still,
            lateralLeanSigned: 0.05, twistSigned: 1)
        model.baseline = Baseline(
            timestamp: Date(), shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
            headPosition: SIMD3<Float>(0.5, 0.8, 0), torsoAngle: 3, shoulderTwist: 1,
            shoulderWidth: 0.2, depthAvailable: false, neckHeight: 0.35)
        return model
    }

    func test_theThresholdState_isTheOneAtThePose_notAfterTheAnswer() async throws {
        let model = readyModel()
        model.postureState = .drifting(since: 100)
        model.jevTransport = SlowTransport { await MainActor.run { model.postureState = .good } }

        await model.classifyWithJevIfDue()

        let record = try XCTUnwrap(model.jevComparisonStore.comparisons.last)
        XCTAssertEqual(record.thresholdState, .drifting(since: 100))
        XCTAssertEqual(model.postureState, .good, "the state did change while Jev was answering")
    }

    func test_theLimitsInForce_areStoredWithTheRecord() async throws {
        let model = readyModel()
        model.forwardCreepThreshold = 0.2
        model.jevTransport = SlowTransport {}

        await model.classifyWithJevIfDue()

        let record = try XCTUnwrap(model.jevComparisonStore.comparisons.last)
        let limits = try XCTUnwrap(record.thresholds)
        XCTAssertEqual(limits.forwardCreepThreshold, 0.2, accuracy: 1e-6,
                       "a 0.157 forward creep is under this limit, which explains a 'good'")
        XCTAssertEqual(record.taskMode, .unknown, "no frames yet, so the pipeline's starting mode")
    }

    func test_theLimitsAndTaskMode_roundTripThroughTheFile() async throws {
        let model = readyModel()
        model.forwardCreepThreshold = 0.2
        model.jevTransport = SlowTransport {}
        await model.classifyWithJevIfDue()
        JevComparisonStore.flushPendingWrites()

        let reloaded = JevComparisonStore()

        let record = try XCTUnwrap(reloaded.comparisons.last)
        XCTAssertEqual(record.thresholds?.forwardCreepThreshold ?? 0, 0.2, accuracy: 1e-6)
        XCTAssertNotNil(record.taskMode)
    }
}
