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
        neckHeight: Float = 1.0,
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
            trackingQuality: .good,
            neckHeight: neckHeight
        )
    }

    private func makeBaseline(
        headPosition: SIMD3<Float> = SIMD3(0, 1.0, 0),
        shoulderMidpoint: SIMD3<Float> = SIMD3(0, 0, 0),
        torsoAngle: Float = 5,
        shoulderTwist: Float = 0,
        shoulderWidth: Float = 0.2,
        neckHeight: Float = 1.0
    ) -> Baseline {
        Baseline(
            timestamp: Date(),
            shoulderMidpoint: shoulderMidpoint,
            headPosition: headPosition,
            torsoAngle: torsoAngle,
            shoulderTwist: shoulderTwist,
            shoulderWidth: shoulderWidth,
            depthAvailable: false,
            neckHeight: neckHeight
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

        // Slouching: closer to camera (wider shoulders), head carriage drops, more lean
        let sample = makeSample(
            torsoAngle: 20,                       // more forward lean
            shoulderWidthRaw: 0.25,               // closer to camera
            neckHeight: 0.7                        // head carried lower (ear-based)
        )
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertGreaterThan(metrics.forwardCreep, 0, "Closer to camera should increase forwardCreep")
        XCTAssertGreaterThan(metrics.headDrop, 0, "Lower head carriage should increase headDrop")
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
        // headDrop = baseline.neckHeight - sample.neckHeight = 1.0 - 0.7 = 0.3
        let baseline = makeBaseline(neckHeight: 1.0)
        let sample = makeSample(neckHeight: 0.7)
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertEqual(metrics.headDrop, 0.3, accuracy: 0.001)
    }

    func test_headDrop_headHigher() {
        var engine = MetricsEngine()
        // Sample carried higher than the calibrated neutral ⇒ negative headDrop.
        let baseline = makeBaseline(neckHeight: 1.0)
        let sample = makeSample(neckHeight: 1.2)
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertLessThan(metrics.headDrop, 0, "Head carriage higher than baseline should be negative headDrop")
    }

    func test_headDropOnly_othersNearZero() {
        var engine = MetricsEngine()
        let baseline = makeBaseline()
        // Only lower the head carriage (neckHeight), keep everything else the same.
        let sample = makeSample(neckHeight: 0.8)
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertGreaterThan(metrics.headDrop, 0, "Head drop should be positive")
        XCTAssertEqual(metrics.forwardCreep, 0, accuracy: 0.001, "forwardCreep should be ~0")
        XCTAssertEqual(metrics.shoulderRounding, 0, accuracy: 0.001, "shoulderRounding should be ~0")
        XCTAssertEqual(metrics.lateralLean, 0, accuracy: 0.001, "lateralLean should be ~0")
        XCTAssertEqual(metrics.twist, 0, accuracy: 0.001, "twist should be ~0")
    }

    /// The refined (ear-sourced) headDrop still crosses `headDropThreshold` exactly
    /// as the metric did before: a carriage deficit larger than the threshold trips
    /// it, a smaller one does not. The threshold's meaning is unchanged (both are in
    /// shoulder-widths of carriage/height); only the underlying signal moved from
    /// `headPosition.y` to `neckHeight`.
    func test_headDrop_crossesThresholdFromNeckHeight() {
        var engine = MetricsEngine()
        let threshold = PostureThresholds().headDropThreshold   // 0.15 (ear-sourced)
        let baseline = makeBaseline(neckHeight: 1.0)

        // Just under the threshold: neckHeight deficit 0.10 ⇒ headDrop 0.10 < 0.15.
        // (0.10 is the device "mild slouch" deficit the threshold sits above —
        //  2026-07-03 post-One-Euro readings.)
        let under = engine.compute(from: makeSample(neckHeight: 1.0 - 0.10), baseline: baseline)
        XCTAssertLessThan(under.headDrop, threshold, "Deficit below threshold must not trip")

        // Just over the threshold: neckHeight deficit 0.22 ⇒ headDrop 0.22 > 0.15.
        // (0.22 is the device "clearly bad" deficit the threshold sits below.)
        let over = engine.compute(from: makeSample(neckHeight: 1.0 - 0.22), baseline: baseline)
        XCTAssertGreaterThan(over.headDrop, threshold, "Deficit above threshold must trip")
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

    func test_lateralLeanSigned_carriesDirection() {
        var engine = MetricsEngine()
        let baseline = makeBaseline(shoulderMidpoint: SIMD3(0, 0, 0))

        let left = engine.compute(from: makeSample(shoulderMidpoint: SIMD3(-0.1, 0, 0)), baseline: baseline)
        let right = engine.compute(from: makeSample(shoulderMidpoint: SIMD3(0.1, 0, 0)), baseline: baseline)

        // Signed keeps left/right sense (image-x: right of baseline → positive)…
        XCTAssertLessThan(left.lateralLeanSigned, 0)
        XCTAssertGreaterThan(right.lateralLeanSigned, 0)
        XCTAssertEqual(left.lateralLeanSigned, -right.lateralLeanSigned, accuracy: 0.001)
        // …while its magnitude still matches the unsigned scoring metric.
        XCTAssertEqual(abs(right.lateralLeanSigned), right.lateralLean, accuracy: 0.001)
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

    func test_twistSigned_carriesDirection() {
        var engine = MetricsEngine()
        let baseline = makeBaseline(shoulderTwist: 0)

        let pos = engine.compute(from: makeSample(shoulderTwist: 10), baseline: baseline)
        let neg = engine.compute(from: makeSample(shoulderTwist: -10), baseline: baseline)

        // Signed keeps the turn direction the unsigned scoring metric discards…
        XCTAssertEqual(pos.twistSigned, 10, accuracy: 0.001)
        XCTAssertEqual(neg.twistSigned, -10, accuracy: 0.001)
        // …while its magnitude still matches the unsigned metric.
        XCTAssertEqual(abs(neg.twistSigned), neg.twist, accuracy: 0.001)
    }

    func test_twist_baselineSubtracted() {
        var engine = MetricsEngine()
        let baseline = makeBaseline(shoulderTwist: 5)
        let sample = makeSample(shoulderTwist: 15)
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertEqual(metrics.twist, 10, accuracy: 0.001, "Twist should be relative to baseline")
    }

    func test_twist_atBaseline_isZero() {
        var engine = MetricsEngine()
        let baseline = makeBaseline(shoulderTwist: 7)
        let sample = makeSample(shoulderTwist: 7)
        let metrics = engine.compute(from: sample, baseline: baseline)

        XCTAssertEqual(metrics.twist, 0, accuracy: 0.001, "Twist at baseline should be zero")
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
