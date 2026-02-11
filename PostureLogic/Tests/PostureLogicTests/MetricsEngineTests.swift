import XCTest
import simd
@testable import PostureLogic

final class MetricsEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makeSample(
        headPosition: SIMD3<Float> = SIMD3(0, 1.0, 0),
        shoulderMidpoint: SIMD3<Float> = SIMD3(0, 0, 0),
        torsoAngle: Float = 5,
        shoulderTwist: Float = 0,
        shoulderWidthRaw: Float = 0.2,
        timestamp: TimeInterval = 1.0
    ) -> PoseSample {
        PoseSample(
            timestamp: timestamp,
            depthMode: .twoDOnly,
            headPosition: headPosition,
            shoulderMidpoint: shoulderMidpoint,
            leftShoulder: SIMD3(-0.5, 0, 0),
            rightShoulder: SIMD3(0.5, 0, 0),
            torsoAngle: torsoAngle,
            headForwardOffset: 0,
            shoulderTwist: shoulderTwist,
            shoulderWidthRaw: shoulderWidthRaw,
            trackingQuality: .good
        )
    }

    private func makeBaseline(
        headPosition: SIMD3<Float> = SIMD3(0, 1.0, 0),
        shoulderMidpoint: SIMD3<Float> = SIMD3(0, 0, 0),
        torsoAngle: Float = 5,
        shoulderWidth: Float = 0.2
    ) -> Baseline {
        Baseline(
            timestamp: Date(),
            shoulderMidpoint: shoulderMidpoint,
            headPosition: headPosition,
            torsoAngle: torsoAngle,
            shoulderWidth: shoulderWidth,
            depthAvailable: false
        )
    }

    // MARK: - No Baseline

    func test_noBaseline_allZeros() {
        var engine = MetricsEngine()
        let sample = makeSample()
        let metrics = engine.compute(from: sample, baseline: nil)

        XCTAssertEqual(metrics.forwardCreep, 0)
        XCTAssertEqual(metrics.headDrop, 0)
        XCTAssertEqual(metrics.shoulderRounding, 0)
        XCTAssertEqual(metrics.lateralLean, 0)
        XCTAssertEqual(metrics.twist, 0)
        XCTAssertEqual(metrics.movementLevel, 0)
        XCTAssertEqual(metrics.headMovementPattern, .still)
    }

    func test_noBaseline_timestampPreserved() {
        var engine = MetricsEngine()
        let sample = makeSample(timestamp: 42.0)
        let metrics = engine.compute(from: sample, baseline: nil)
        XCTAssertEqual(metrics.timestamp, 42.0)
    }

    // MARK: - Identical to Baseline

    func test_identicalToBaseline_allNearZero() {
        var engine = MetricsEngine()
        let baseline = makeBaseline()
        let sample = makeSample()
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertEqual(metrics.forwardCreep, 0, accuracy: 0.001)
        XCTAssertEqual(metrics.headDrop, 0, accuracy: 0.001)
        XCTAssertEqual(metrics.shoulderRounding, 0, accuracy: 0.001)
        XCTAssertEqual(metrics.lateralLean, 0, accuracy: 0.001)
        XCTAssertEqual(metrics.twist, 0, accuracy: 0.001)
    }

    // MARK: - Forward Slouch (multiple metrics worsen together)

    func test_forwardSlouch() {
        var engine = MetricsEngine()
        let baseline = makeBaseline()

        // Slouching: closer to camera (wider shoulders), head drops, more lean
        let sample = makeSample(
            headPosition: SIMD3(0, 0.7, 0),     // head dropped
            torsoAngle: 20,                       // more forward lean
            shoulderWidthRaw: 0.25                // closer to camera
        )
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertGreaterThan(metrics.forwardCreep, 0, "Closer to camera should increase forwardCreep")
        XCTAssertGreaterThan(metrics.headDrop, 0, "Lower head should increase headDrop")
        XCTAssertGreaterThan(metrics.shoulderRounding, 0, "More lean should increase shoulderRounding")
    }

    // MARK: - Forward Creep

    func test_forwardCreep_closerToCamera() {
        var engine = MetricsEngine()
        let baseline = makeBaseline(shoulderWidth: 0.2)
        let sample = makeSample(shoulderWidthRaw: 0.24) // 20% wider
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertEqual(metrics.forwardCreep, 0.2, accuracy: 0.001)
    }

    func test_forwardCreep_fartherFromCamera() {
        var engine = MetricsEngine()
        let baseline = makeBaseline(shoulderWidth: 0.2)
        let sample = makeSample(shoulderWidthRaw: 0.16) // 20% narrower
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertEqual(metrics.forwardCreep, -0.2, accuracy: 0.001)
    }

    // MARK: - Head Drop

    func test_headDrop_headLower() {
        var engine = MetricsEngine()
        let baseline = makeBaseline(headPosition: SIMD3(0, 1.0, 0))
        let sample = makeSample(headPosition: SIMD3(0, 0.7, 0))
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertEqual(metrics.headDrop, 0.3, accuracy: 0.001)
    }

    func test_headDrop_headHigher() {
        var engine = MetricsEngine()
        let baseline = makeBaseline(headPosition: SIMD3(0, 1.0, 0))
        let sample = makeSample(headPosition: SIMD3(0, 1.2, 0))
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertLessThan(metrics.headDrop, 0, "Head higher than baseline should be negative headDrop")
    }

    func test_headDropOnly_othersNearZero() {
        var engine = MetricsEngine()
        let baseline = makeBaseline()
        // Only change head position, keep everything else the same
        let sample = makeSample(headPosition: SIMD3(0, 0.8, 0))
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertGreaterThan(metrics.headDrop, 0, "Head drop should be positive")
        XCTAssertEqual(metrics.forwardCreep, 0, accuracy: 0.001, "forwardCreep should be ~0")
        XCTAssertEqual(metrics.shoulderRounding, 0, accuracy: 0.001, "shoulderRounding should be ~0")
        XCTAssertEqual(metrics.lateralLean, 0, accuracy: 0.001, "lateralLean should be ~0")
        XCTAssertEqual(metrics.twist, 0, accuracy: 0.001, "twist should be ~0")
    }

    // MARK: - Shoulder Rounding

    func test_shoulderRounding_moreForwardLean() {
        var engine = MetricsEngine()
        let baseline = makeBaseline(torsoAngle: 5)
        let sample = makeSample(torsoAngle: 15)
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertEqual(metrics.shoulderRounding, 10, accuracy: 0.001)
    }

    // MARK: - Lateral Lean

    func test_lateralLean_offCenter() {
        var engine = MetricsEngine()
        let baseline = makeBaseline(shoulderMidpoint: SIMD3(0, 0, 0))
        let sample = makeSample(shoulderMidpoint: SIMD3(0.15, 0, 0))
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertEqual(metrics.lateralLean, 0.15, accuracy: 0.001)
    }

    func test_lateralLean_symmetricLeftRight() {
        var engine = MetricsEngine()
        let baseline = makeBaseline()

        let sampleLeft = makeSample(shoulderMidpoint: SIMD3(-0.1, 0, 0))
        let sampleRight = makeSample(shoulderMidpoint: SIMD3(0.1, 0, 0))

        let metricsLeft = engine.compute(from: sampleLeft, baseline: baseline)
        let metricsRight = engine.compute(from: sampleRight, baseline: baseline)

        XCTAssertEqual(metricsLeft.lateralLean, metricsRight.lateralLean, accuracy: 0.001,
                       "Lateral lean should be symmetric")
    }

    // MARK: - Twist

    func test_twist_positive() {
        var engine = MetricsEngine()
        let baseline = makeBaseline()
        let sample = makeSample(shoulderTwist: 10)
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertEqual(metrics.twist, 10, accuracy: 0.001)
    }

    func test_twist_negativeBecomesPositive() {
        var engine = MetricsEngine()
        let baseline = makeBaseline()
        let sample = makeSample(shoulderTwist: -10)
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertEqual(metrics.twist, 10, accuracy: 0.001, "Twist should be absolute value")
    }

    // MARK: - Deferred Metrics

    func test_movementLevel_alwaysZero() {
        var engine = MetricsEngine()
        let baseline = makeBaseline()
        let sample = makeSample()
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertEqual(metrics.movementLevel, 0)
    }

    func test_headMovementPattern_alwaysStill() {
        var engine = MetricsEngine()
        let baseline = makeBaseline()
        let sample = makeSample()
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertEqual(metrics.headMovementPattern, .still)
    }

    // MARK: - Debug State

    func test_debugState_containsExpectedKeys() {
        var engine = MetricsEngine()
        _ = engine.compute(from: makeSample(), baseline: makeBaseline())
        let state = engine.debugState

        XCTAssertNotNil(state["computeCount"])
        XCTAssertNotNil(state["noBaselineCount"])
    }

    func test_debugState_computeCountIncrements() {
        var engine = MetricsEngine()
        XCTAssertEqual(engine.computeCount, 0)
        _ = engine.compute(from: makeSample(), baseline: makeBaseline())
        XCTAssertEqual(engine.computeCount, 1)
        _ = engine.compute(from: makeSample(), baseline: makeBaseline())
        XCTAssertEqual(engine.computeCount, 2)
    }

    func test_debugState_noBaselineCountIncrements() {
        var engine = MetricsEngine()
        XCTAssertEqual(engine.noBaselineCount, 0)
        _ = engine.compute(from: makeSample(), baseline: nil)
        XCTAssertEqual(engine.noBaselineCount, 1)
    }
}
