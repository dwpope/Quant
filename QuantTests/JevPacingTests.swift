import XCTest
import PostureLogic
import simd
@testable import Quant

/// When a Jev classification is allowed to happen.
///
/// Four refusals, each for a concrete reason found by reading the pipeline rather than the plan:
///
/// - **Off by default.** `useJevClassifier` ships false; the threshold engine stays the shipping
///   classifier. A cloud call must never happen because someone forgot a flag.
/// - **No baseline, no call.** `MetricsEngine` returns all-zero metrics rather than `nil` before
///   calibration, so a payload built from `latestMetrics` alone would pass the proxy's
///   finite-number validation and be meaningless. Optionality cannot be the gate; the baseline
///   has to be.
/// - **No sample, no call.** `latestSample` goes nil whenever fusion fails, while `latestMetrics`
///   keeps its last value — so the two can disagree in time. The payload takes both as one
///   snapshot and refuses on a nil sample rather than pairing fresh metrics with a stale pose.
/// - **Not too often.** 130-475ms per call, so this is interval-driven, never per frame.
@MainActor
final class JevPacingTests: XCTestCase {

    private let baselineKey = "com.quant.savedBaseline"

    override func setUpWithError() throws { UserDefaults.standard.removeObject(forKey: baselineKey) }
    override func tearDownWithError() throws { UserDefaults.standard.removeObject(forKey: baselineKey) }

    private func makeSample() -> PoseSample {
        PoseSample(
            timestamp: 0, depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0.5, 0.8, 0), shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
            leftShoulder: SIMD3<Float>(0.4, 0.6, 0), rightShoulder: SIMD3<Float>(0.6, 0.6, 0),
            torsoAngle: 5, headForwardOffset: 0, shoulderTwist: 0,
            shoulderWidthRaw: 0.3, trackingQuality: .good)
    }

    private func makeMetrics() -> RawMetrics {
        RawMetrics(timestamp: 0, forwardCreep: -0.09, headDrop: 0.01, shoulderRounding: 1,
                   lateralLean: 0.05, twist: 1, movementLevel: 0, headMovementPattern: .still,
                   lateralLeanSigned: 0.05, twistSigned: 1)
    }

    private func makeBaseline() -> Baseline {
        Baseline(timestamp: Date(), shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
                 headPosition: SIMD3<Float>(0.5, 0.8, 0), torsoAngle: 3, shoulderTwist: 1,
                 shoulderWidth: 0.2, depthAvailable: false, neckHeight: 0.35)
    }

    /// A model with everything in place for a call to be due.
    private func readyModel() -> AppModel {
        let model = AppModel()
        model.useJevClassifier = true
        model.latestSample = makeSample()
        model.latestMetrics = makeMetrics()
        model.baseline = makeBaseline()
        return model
    }

    func test_noPayload_whenTheFlagIsOff() {
        let model = readyModel()
        model.useJevClassifier = false

        XCTAssertNil(model.jevPayloadIfDue(now: Date()))
    }

    func test_noPayload_beforeCalibration_evenThoughMetricsAreNonNil() {
        let model = readyModel()
        model.baseline = nil

        XCTAssertNotNil(model.latestMetrics, "metrics are all-zero, not nil, pre-calibration")
        XCTAssertNil(model.jevPayloadIfDue(now: Date()))
    }

    func test_noPayload_whenTheSampleIsMissingButMetricsAreStale() {
        let model = readyModel()
        model.latestSample = nil

        XCTAssertNotNil(model.latestMetrics)
        XCTAssertNil(model.jevPayloadIfDue(now: Date()))
    }

    func test_buildsAPayload_whenEverythingIsInPlace() throws {
        let model = readyModel()

        let payload = try XCTUnwrap(model.jevPayloadIfDue(now: Date()))

        // Normalised, not raw: 0.05 / 0.20.
        XCTAssertEqual(payload.lateralLeanInShoulderWidths, 0.25, accuracy: 1e-5)
        XCTAssertEqual(payload.trackingQuality, .good)
    }

    func test_refusesASecondCallInsideTheInterval() throws {
        let model = readyModel()
        model.jevMinInterval = 5
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertNotNil(model.jevPayloadIfDue(now: start))
        XCTAssertNil(model.jevPayloadIfDue(now: start.addingTimeInterval(4)),
                     "inside the interval")
        XCTAssertNotNil(model.jevPayloadIfDue(now: start.addingTimeInterval(5)),
                        "the interval has elapsed")
    }

    func test_recordComparison_landsInTheStoreWithTheBaseline() throws {
        let model = readyModel()
        let payload = try XCTUnwrap(model.jevPayloadIfDue(now: Date()))
        let verdict = JevVerdict(posture: "chair_swivel", confidence: 0.81,
                                 probabilities: ["chair_swivel": 0.81], model: "jev-1.13.0")

        model.recordJevComparison(features: payload, verdict: verdict, error: nil)

        XCTAssertEqual(model.jevComparisonStore.comparisons.count, 1)
        XCTAssertEqual(model.latestJevVerdict?.posture, "chair_swivel")
        XCTAssertNotNil(model.latestJevVerdictAt, "staleness must be visible: the HUD shows this beside a fresher threshold verdict")
        XCTAssertEqual(model.jevComparisonStore.comparisons.first?.baseline.shoulderWidth, 0.2)
    }

    func test_recordComparison_keepsAFailureAsEvidence() {
        let model = readyModel()
        let payload = model.jevPayloadIfDue(now: Date())!

        model.recordJevComparison(features: payload, verdict: nil, error: "busy(afterAttempts: 4)")

        XCTAssertNil(model.latestJevVerdict)
        XCTAssertEqual(model.latestJevError, "busy(afterAttempts: 4)")
        XCTAssertEqual(model.jevComparisonStore.comparisons.count, 1)
    }
}
