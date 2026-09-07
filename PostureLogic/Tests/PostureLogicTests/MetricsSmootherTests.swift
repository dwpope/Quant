import XCTest
import simd
@testable import PostureLogic

final class MetricsSmootherTests: XCTestCase {

    // MARK: - Helpers

    private func makeSample(
        headPosition: SIMD3<Float> = SIMD3(0, 1.0, 0),
        shoulderMidpoint: SIMD3<Float> = SIMD3(0, 0, 0),
        timestamp: TimeInterval = 1.0
    ) -> PoseSample {
        PoseSample(
            timestamp: timestamp,
            depthMode: .twoDOnly,
            headPosition: headPosition,
            shoulderMidpoint: shoulderMidpoint,
            leftShoulder: SIMD3(-0.5, 0, 0),
            rightShoulder: SIMD3(0.5, 0, 0),
            torsoAngle: 5,
            headForwardOffset: 0,
            shoulderTwist: 0,
            shoulderWidthRaw: 0.2,
            trackingQuality: .good
        )
    }

    private func makeMetrics(
        forwardCreep: Float = 0,
        headDrop: Float = 0,
        shoulderRounding: Float = 0,
        lateralLean: Float = 0,
        twist: Float = 0,
        timestamp: TimeInterval = 1.0
    ) -> RawMetrics {
        RawMetrics(
            timestamp: timestamp,
            forwardCreep: forwardCreep,
            headDrop: headDrop,
            shoulderRounding: shoulderRounding,
            lateralLean: lateralLean,
            twist: twist,
            movementLevel: 0,
            headMovementPattern: .still
        )
    }

    // MARK: - First Sample (Passthrough)

    func test_firstSample_postureMetricsPassThrough() {
        var smoother = MetricsSmoother(alpha: 0.3)
        let metrics = makeMetrics(forwardCreep: 0.5, headDrop: 0.3, twist: 10)
        let sample = makeSample()

        let result = smoother.smooth(metrics, sample: sample)

        XCTAssertEqual(result.forwardCreep, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.headDrop, 0.3, accuracy: 0.001)
        XCTAssertEqual(result.twist, 10, accuracy: 0.001)
    }

    func test_firstSample_timestampPreserved() {
        var smoother = MetricsSmoother()
        let metrics = makeMetrics(timestamp: 42.0)
        let sample = makeSample(timestamp: 42.0)

        let result = smoother.smooth(metrics, sample: sample)

        XCTAssertEqual(result.timestamp, 42.0)
    }

    func test_firstSample_movementLevelIsZero() {
        var smoother = MetricsSmoother()
        let metrics = makeMetrics()
        let sample = makeSample()

        let result = smoother.smooth(metrics, sample: sample)

        XCTAssertEqual(result.movementLevel, 0)
    }

    // MARK: - EMA Smoothing

    func test_ema_secondSampleBlended() {
        var smoother = MetricsSmoother(alpha: 0.3)

        // First sample: forwardCreep = 0
        let m1 = makeMetrics(forwardCreep: 0, timestamp: 1.0)
        let s1 = makeSample(timestamp: 1.0)
        _ = smoother.smooth(m1, sample: s1)

        // Second sample: forwardCreep = 1.0
        let m2 = makeMetrics(forwardCreep: 1.0, timestamp: 1.1)
        let s2 = makeSample(timestamp: 1.1)
        let result = smoother.smooth(m2, sample: s2)

        // EMA: prev + (current - prev) * alpha = 0 + (1.0 - 0) * 0.3 = 0.3
        XCTAssertEqual(result.forwardCreep, 0.3, accuracy: 0.001)
    }

    func test_ema_convergesToStableValue() {
        var smoother = MetricsSmoother(alpha: 0.3)

        // Feed many samples with the same value, should converge
        for i in 0..<50 {
            let m = makeMetrics(headDrop: 0.5, timestamp: Double(i) * 0.1)
            let s = makeSample(timestamp: Double(i) * 0.1)
            _ = smoother.smooth(m, sample: s)
        }

        let final = smoother.smooth(
            makeMetrics(headDrop: 0.5, timestamp: 5.0),
            sample: makeSample(timestamp: 5.0)
        )
        XCTAssertEqual(final.headDrop, 0.5, accuracy: 0.001, "Should converge to stable value")
    }

    func test_ema_dampensSpike() {
        var smoother = MetricsSmoother(alpha: 0.3)

        // Establish stable baseline of 0
        for i in 0..<10 {
            let m = makeMetrics(lateralLean: 0, timestamp: Double(i) * 0.1)
            let s = makeSample(timestamp: Double(i) * 0.1)
            _ = smoother.smooth(m, sample: s)
        }

        // Sudden spike
        let spike = smoother.smooth(
            makeMetrics(lateralLean: 1.0, timestamp: 1.0),
            sample: makeSample(timestamp: 1.0)
        )

        XCTAssertLessThan(spike.lateralLean, 0.5, "Spike should be dampened by EMA")
        XCTAssertGreaterThan(spike.lateralLean, 0, "But should still move toward new value")
    }

    func test_ema_higherAlphaMoreResponsive() {
        var smootherLow = MetricsSmoother(alpha: 0.1)
        var smootherHigh = MetricsSmoother(alpha: 0.9)

        // First sample
        let m1 = makeMetrics(twist: 0, timestamp: 0)
        let s1 = makeSample(timestamp: 0)
        _ = smootherLow.smooth(m1, sample: s1)
        _ = smootherHigh.smooth(m1, sample: s1)

        // Second sample with big change
        let m2 = makeMetrics(twist: 10, timestamp: 0.1)
        let s2 = makeSample(timestamp: 0.1)
        let resultLow = smootherLow.smooth(m2, sample: s2)
        let resultHigh = smootherHigh.smooth(m2, sample: s2)

        XCTAssertGreaterThan(resultHigh.twist, resultLow.twist,
                             "Higher alpha should be more responsive to changes")
    }

    func test_ema_fourMetricsSmoothedByAlpha() {
        // The four non-headDrop fields share the fixed-weight EMA. `headDrop` is
        // deliberately excluded here: it now rides its own adaptive One Euro filter
        // (see `test_headDrop_isHeavierThanAlpha_onSlowRamp`), so on an advancing-
        // timestamp step it does NOT land on the EMA's alpha-blend value.
        var smoother = MetricsSmoother(alpha: 0.5)

        let m1 = makeMetrics(forwardCreep: 0, headDrop: 0, shoulderRounding: 0, lateralLean: 0, twist: 0, timestamp: 0)
        _ = smoother.smooth(m1, sample: makeSample(timestamp: 0))

        let m2 = makeMetrics(forwardCreep: 1, headDrop: 1, shoulderRounding: 1, lateralLean: 1, twist: 1, timestamp: 0.1)
        let result = smoother.smooth(m2, sample: makeSample(timestamp: 0.1))

        // With alpha=0.5: each of the four EMA-smoothed fields should be 0.5.
        XCTAssertEqual(result.forwardCreep, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.shoulderRounding, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.lateralLean, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.twist, 0.5, accuracy: 0.001)
    }

    // MARK: - headDrop dedicated One Euro filter

    /// `headDrop` rides its own One Euro filter, tuned heavier than the shared EMA.
    /// On a *posture-realistic slow ramp* (a real slouch developing over a few
    /// seconds — the regime where the `minCutoff` floor dominates), the One Euro
    /// `headDrop` must trail a reference `alpha` EMA fed the exact same field, i.e.
    /// it is genuinely more damped than the responsive metrics. (A single instantaneous
    /// jump would instead read as huge speed and snap through, which is why this uses a
    /// gradual change, not a step.)
    func test_headDrop_isHeavierThanAlpha_onSlowRamp() {
        // The smoother whose headDrop is One-Euro filtered.
        var smoother = MetricsSmoother(alpha: 0.3)
        // A plain reference EMA at the same alpha, fed the identical headDrop values.
        var referenceEMA: Float = 0
        let refAlpha: Float = 0.3

        // Seed both at 0.
        _ = smoother.smooth(makeMetrics(headDrop: 0, timestamp: 0), sample: makeSample(timestamp: 0))

        // Gradual ramp 0 → 0.03 over 3 s at 10 Hz (posture-speed drift).
        var oneEuro: Float = 0
        var t = 0.0
        for i in 1...30 {
            t += 0.1
            let x = Float(i) / 30.0 * 0.03
            oneEuro = smoother.smooth(makeMetrics(headDrop: x, timestamp: t), sample: makeSample(timestamp: t)).headDrop
            referenceEMA += refAlpha * (x - referenceEMA)
        }

        XCTAssertGreaterThan(oneEuro, 0, "Filtered headDrop must track a sustained ramp")
        XCTAssertLessThan(oneEuro, referenceEMA,
                          "On a slow posture-speed ramp the One Euro headDrop must lag the equally-weighted EMA (heavier smoothing)")
    }

    /// The identity contract that keeps the exact numeric assertions elsewhere valid:
    /// with a NON-advancing timestamp the One Euro stage is a pass-through, so a
    /// changing `headDrop` at constant time is reported raw (never EMA-blended either,
    /// since the alpha path also needs a prior value only through `previous`). The
    /// first sample seeds; each subsequent constant-timestamp sample returns raw.
    func test_headDrop_identityWhenTimestampDoesNotAdvance() {
        var smoother = MetricsSmoother(alpha: 0.5)

        // All samples stamped at the SAME time. The first seeds the filter (raw),
        // and every later one passes through raw because dt == 0.
        let inputs: [Float] = [0.02, 0.05, 0.01, 0.09, 0.03]
        for x in inputs {
            let result = smoother.smooth(
                makeMetrics(headDrop: x, timestamp: 5.0),
                sample: makeSample(timestamp: 5.0)
            )
            XCTAssertEqual(result.headDrop, x, accuracy: 1e-6,
                           "With a non-advancing timestamp, headDrop must pass through raw")
        }
    }

    /// A sustained step must eventually converge to the input — the heavy filter adds
    /// lag, not a permanent offset. A stuck-low filter would keep a real slouch from
    /// ever crossing `headDropThreshold`.
    func test_headDrop_sustainedStep_convergesToInput() {
        var smoother = MetricsSmoother(alpha: 0.5)

        // Seed at 0, then hold a bad-carriage headDrop of 0.03 for a few seconds at
        // 10 Hz. It must climb to ~0.03 despite the heavy stationary smoothing.
        _ = smoother.smooth(makeMetrics(headDrop: 0, timestamp: 0), sample: makeSample(timestamp: 0))

        var last: Float = 0
        var t = 0.0
        for _ in 0..<80 {                      // 8 s at 10 Hz
            t += 0.1
            last = smoother.smooth(
                makeMetrics(headDrop: 0.03, timestamp: t),
                sample: makeSample(timestamp: t)
            ).headDrop
        }
        XCTAssertEqual(last, 0.03, accuracy: 0.002, "A sustained step must converge to the held input")
    }

    /// A noisy, stationary `headDrop` (the on-device failure mode: ~±0.01 flicker at a
    /// fixed pose) must come out attenuated toward its mean — the reason the dedicated
    /// filter exists. Compares the settled output swing against the input swing.
    func test_headDrop_noisyStationaryInput_isAttenuated() {
        var smoother = MetricsSmoother(alpha: 0.5)

        let mean: Float = 0.02
        let noise: Float = 0.01               // ±0.01 measured jitter
        var t = 0.0
        var outs: [Float] = []
        for i in 0..<160 {
            t += 0.1
            let x = mean + (i % 2 == 0 ? noise : -noise)
            outs.append(smoother.smooth(
                makeMetrics(headDrop: x, timestamp: t),
                sample: makeSample(timestamp: t)
            ).headDrop)
        }
        // Settled tail only (skip the seeding transient).
        let tail = Array(outs.suffix(60))
        let outSwing = (tail.max() ?? 0) - (tail.min() ?? 0)
        let inSwing = 2 * noise               // 0.02 peak-to-peak input
        XCTAssertLessThan(outSwing, inSwing * 0.5,
                          "Stationary headDrop jitter must be attenuated to <50% of the input swing")
        // And it must stay centred on the mean (no steady-state bias).
        let tailMean = tail.reduce(0, +) / Float(tail.count)
        XCTAssertEqual(tailMean, mean, accuracy: 0.002, "Attenuated output must stay centred on the input mean")
    }

    // MARK: - Movement Level

    func test_movementLevel_zeroWhenStationary() {
        var smoother = MetricsSmoother()
        let pos = SIMD3<Float>(0, 1.0, 0)

        _ = smoother.smooth(makeMetrics(timestamp: 0), sample: makeSample(headPosition: pos, timestamp: 0))
        let result = smoother.smooth(makeMetrics(timestamp: 0.1), sample: makeSample(headPosition: pos, timestamp: 0.1))

        XCTAssertEqual(result.movementLevel, 0, accuracy: 0.001)
    }

    func test_movementLevel_increasesWithMovement() {
        var smoother = MetricsSmoother()

        let s1 = makeSample(headPosition: SIMD3(0, 1.0, 0), shoulderMidpoint: SIMD3(0, 0, 0), timestamp: 0)
        _ = smoother.smooth(makeMetrics(timestamp: 0), sample: s1)

        let s2 = makeSample(headPosition: SIMD3(0.1, 1.0, 0), shoulderMidpoint: SIMD3(0.1, 0, 0), timestamp: 0.1)
        let result = smoother.smooth(makeMetrics(timestamp: 0.1), sample: s2)

        XCTAssertGreaterThan(result.movementLevel, 0, "Movement should produce positive movementLevel")
    }

    func test_movementLevel_cappedAtOne() {
        var smoother = MetricsSmoother()

        let s1 = makeSample(headPosition: SIMD3(0, 0, 0), shoulderMidpoint: SIMD3(0, 0, 0), timestamp: 0)
        _ = smoother.smooth(makeMetrics(timestamp: 0), sample: s1)

        // Huge jump in one frame
        let s2 = makeSample(headPosition: SIMD3(5, 5, 0), shoulderMidpoint: SIMD3(5, 5, 0), timestamp: 0.1)
        let result = smoother.smooth(makeMetrics(timestamp: 0.1), sample: s2)

        XCTAssertEqual(result.movementLevel, 1.0, accuracy: 0.001, "Should be capped at 1.0")
    }

    func test_movementLevel_zeroWhenTimeDeltaIsZero() {
        var smoother = MetricsSmoother()

        let s1 = makeSample(headPosition: SIMD3(0, 0, 0), timestamp: 1.0)
        _ = smoother.smooth(makeMetrics(timestamp: 1.0), sample: s1)

        // Same timestamp
        let s2 = makeSample(headPosition: SIMD3(1, 1, 0), timestamp: 1.0)
        let result = smoother.smooth(makeMetrics(timestamp: 1.0), sample: s2)

        XCTAssertEqual(result.movementLevel, 0, "Zero time delta should produce zero movement")
    }

    // MARK: - Head Movement Pattern

    func test_headPattern_still_whenNotMoving() {
        var smoother = MetricsSmoother()
        let pos = SIMD3<Float>(0, 1.0, 0)

        // Feed enough samples to fill the window
        for i in 0..<10 {
            let result = smoother.smooth(
                makeMetrics(timestamp: Double(i) * 0.1),
                sample: makeSample(headPosition: pos, timestamp: Double(i) * 0.1)
            )
            if i >= 4 {
                XCTAssertEqual(result.headMovementPattern, .still)
            }
        }
    }

    func test_headPattern_smallOscillations_withMinorMovement() {
        var smoother = MetricsSmoother()

        // Small regular oscillations around center (±0.004 in x only → ~0.008 displacement per frame)
        for i in 0..<15 {
            let offset = Float(i % 2 == 0 ? 1 : -1) * 0.004
            let pos = SIMD3<Float>(offset, 1.0, 0)
            _ = smoother.smooth(
                makeMetrics(timestamp: Double(i) * 0.1),
                sample: makeSample(headPosition: pos, timestamp: Double(i) * 0.1)
            )
        }

        let result = smoother.smooth(
            makeMetrics(timestamp: 1.5),
            sample: makeSample(headPosition: SIMD3(0.004, 1.0, 0), timestamp: 1.5)
        )

        XCTAssertEqual(result.headMovementPattern, .smallOscillations)
    }

    func test_headPattern_largeMovements_withBigDisplacements() {
        var smoother = MetricsSmoother()

        // Large consistent movements
        for i in 0..<15 {
            let pos = SIMD3<Float>(Float(i) * 0.05, 1.0, 0)
            _ = smoother.smooth(
                makeMetrics(timestamp: Double(i) * 0.1),
                sample: makeSample(headPosition: pos, timestamp: Double(i) * 0.1)
            )
        }

        let result = smoother.smooth(
            makeMetrics(timestamp: 1.5),
            sample: makeSample(headPosition: SIMD3(0.75, 1.0, 0), timestamp: 1.5)
        )

        XCTAssertEqual(result.headMovementPattern, .largeMovements)
    }

    // MARK: - Reset

    func test_reset_clearsState() {
        var smoother = MetricsSmoother()

        // Build up state
        for i in 0..<10 {
            _ = smoother.smooth(
                makeMetrics(forwardCreep: 0.5, timestamp: Double(i) * 0.1),
                sample: makeSample(timestamp: Double(i) * 0.1)
            )
        }

        smoother.reset()

        // After reset, first sample should pass through unsmoothed
        let result = smoother.smooth(
            makeMetrics(forwardCreep: 1.0, timestamp: 10.0),
            sample: makeSample(timestamp: 10.0)
        )

        XCTAssertEqual(result.forwardCreep, 1.0, accuracy: 0.001,
                        "After reset, first sample should pass through unsmoothed")
        XCTAssertEqual(result.movementLevel, 0,
                        "After reset, no previous sample so movementLevel should be 0")
    }

    // MARK: - Debug State

    func test_debugState_containsExpectedKeys() {
        var smoother = MetricsSmoother()
        _ = smoother.smooth(makeMetrics(), sample: makeSample())
        let state = smoother.debugState

        XCTAssertNotNil(state["alpha"])
        XCTAssertNotNil(state["sampleCount"])
        XCTAssertNotNil(state["headWindowCount"])
        XCTAssertNotNil(state["lastMovementLevel"])
        XCTAssertNotNil(state["lastHeadPattern"])
    }

    func test_debugState_sampleCountIncrements() {
        var smoother = MetricsSmoother()

        _ = smoother.smooth(makeMetrics(timestamp: 0), sample: makeSample(timestamp: 0))
        XCTAssertEqual(smoother.debugState["sampleCount"] as? Int, 1)

        _ = smoother.smooth(makeMetrics(timestamp: 0.1), sample: makeSample(timestamp: 0.1))
        XCTAssertEqual(smoother.debugState["sampleCount"] as? Int, 2)
    }
}
