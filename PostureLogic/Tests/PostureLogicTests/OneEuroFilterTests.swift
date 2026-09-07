import XCTest
@testable import PostureLogic

/// Headless proof for ``OneEuroFilter`` — the adaptive source-side denoiser for the
/// head angles. The two load-bearing properties are: (1) it is the *identity* when it
/// cannot measure a positive `dt` (the contract that keeps the camera-free view-model
/// tests, which stamp every frame `timestamp: 0`, behaving exactly as before), and
/// (2) it removes jitter when the signal is still yet tracks a fast move with little
/// lag — the adaptivity a fixed low-pass cannot offer.
final class OneEuroFilterTests: XCTestCase {

    private let dt60: Double = 1.0 / 60.0

    // MARK: - Identity contract (the view-model test-transparency guarantee)

    func test_firstSample_seedsAndReturnsRaw() {
        var f = OneEuroFilter(minCutoff: 1, beta: 0.05)
        XCTAssertFalse(f.isSeeded)
        let out = f.update(42, timestamp: 0)
        XCTAssertEqual(out, 42, accuracy: 0, "first sample must pass through unchanged (seed)")
        XCTAssertTrue(f.isSeeded)
    }

    func test_nonAdvancingTimestamp_passesRawThrough_everyFrame() {
        // THE contract. Feed wildly different values all stamped at the same time:
        // every output must equal that frame's RAW input. This is exactly what the
        // view-model unit tests do (makeSample uses timestamp: 0), so with this
        // property the One Euro stage is a no-op there and every prior assertion holds.
        var f = OneEuroFilter(minCutoff: 0.001, beta: 10)   // params that WOULD smooth hard
        let inputs: [Float] = [5, -80, 80, 0, 33, -33, 100]
        for x in inputs {
            let out = f.update(x, timestamp: 0)
            XCTAssertEqual(out, x, accuracy: 0,
                           "with a non-advancing timestamp the filter must be the identity")
        }
    }

    func test_constantInput_hasNoSteadyStateBias() {
        // Advancing time, constant value ⇒ converges to *exactly* that value. A biased
        // filter would settle slightly off and shift the calibrated rest reference.
        var f = OneEuroFilter(minCutoff: 1, beta: 0.05)
        var t = 0.0
        var out: Float = 0
        for _ in 0..<200 { t += dt60; out = f.update(7.5, timestamp: t) }
        XCTAssertEqual(out, 7.5, accuracy: 1e-3, "constant input must not develop a steady-state offset")
    }

    // MARK: - Denoise when still

    func test_stillSignal_attenuatesJitter() {
        // A stationary head with ±0.5° of sensor jitter (alternating sign). The output
        // swing must be a small fraction of the input swing — the whole point.
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.05)
        let base: Float = 10
        let noise: Float = 0.5
        var t = 0.0
        var outs: [Float] = []
        for i in 0..<120 {
            t += dt60
            let x = base + (i % 2 == 0 ? noise : -noise)
            outs.append(f.update(x, timestamp: t))
        }
        // Measure peak-to-peak over the settled tail (skip the seeding transient).
        let tail = Array(outs.suffix(60))
        let swing = (tail.max() ?? 0) - (tail.min() ?? 0)
        XCTAssertLessThan(swing, noise, "still-state jitter must be attenuated below the input ±swing")
        XCTAssertLessThan(swing, 2 * noise * 0.5, "and attenuated substantially (<50% of the 1.0° p-p input)")
    }

    func test_lowerMinCutoff_isSteadier() {
        // Lower minCutoff ⇒ more smoothing ⇒ smaller residual swing on the same jitter.
        func tailSwing(minCutoff: Float) -> Float {
            var f = OneEuroFilter(minCutoff: minCutoff, beta: 0.0)
            var t = 0.0
            var outs: [Float] = []
            for i in 0..<160 {
                t += dt60
                outs.append(f.update(10 + (i % 2 == 0 ? 0.5 : -0.5), timestamp: t))
            }
            let tail = Array(outs.suffix(60))
            return (tail.max() ?? 0) - (tail.min() ?? 0)
        }
        XCTAssertLessThan(tailSwing(minCutoff: 0.4), tailSwing(minCutoff: 2.0),
                          "a lower minimum cutoff must yield a steadier (smaller-swing) output")
    }

    // MARK: - Track when moving (the adaptivity a fixed low-pass lacks)

    func test_higherBeta_reducesLagOnFastMove() {
        // Drive a fast ramp through two filters identical but for beta. The higher-beta
        // filter must sit CLOSER to the live value (less lag) — proof the cutoff is
        // actually rising with speed rather than holding a fixed smoothing weight.
        func lagAtEnd(beta: Float) -> Float {
            var f = OneEuroFilter(minCutoff: 1.0, beta: beta)
            var t = 0.0
            var x: Float = 0
            var out: Float = 0
            for _ in 0..<40 {
                t += dt60
                x += 2.0                      // 2°/frame ≈ 120°/s — a brisk nod
                out = f.update(x, timestamp: t)
            }
            return x - out                    // positive lag (filter trails a rising ramp)
        }
        let lagLowBeta = lagAtEnd(beta: 0.0)
        let lagHighBeta = lagAtEnd(beta: 0.2)
        XCTAssertGreaterThan(lagLowBeta, 0, "a low-pass trails a moving ramp")
        XCTAssertLessThan(lagHighBeta, lagLowBeta,
                          "higher beta must reduce lag on a fast move (adaptive cutoff)")
    }

    func test_largeDtGap_snapsRatherThanLagsForever() {
        // A long gap between samples (tracking resumed) ⇒ huge dt ⇒ alpha → 1 ⇒ the
        // filter trusts the fresh sample instead of crawling toward it for seconds.
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.05)
        _ = f.update(0, timestamp: 0)
        let out = f.update(50, timestamp: 5.0)   // 5 s later
        XCTAssertGreaterThan(out, 45, "after a long gap the filter should essentially snap to the new value")
    }

    // MARK: - Reset

    func test_reset_returnsToUnseeded() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.05)
        var t = 0.0
        for _ in 0..<10 { t += dt60; f.update(20, timestamp: t) }
        XCTAssertTrue(f.isSeeded)
        f.reset()
        XCTAssertFalse(f.isSeeded)
        let out = f.update(99, timestamp: t + dt60)
        XCTAssertEqual(out, 99, accuracy: 0, "after reset the next sample re-seeds (passes through)")
    }
}
