import XCTest
@testable import PostureLogic

/// Headless proof that ``CriticallyDampedScalar`` behaves as a frame-rate-independent,
/// critically-damped (no-overshoot, no-pulse) follower — the properties the render
/// binding relies on to turn a stepwise ~10 Hz head-angle target into fluid motion.
final class CriticallyDampedScalarTests: XCTestCase {

    private let dt60: Float = 1.0 / 60.0
    private let dt120: Float = 1.0 / 120.0

    // MARK: - Step response: monotone, no overshoot, actually smooths

    func test_stepResponse_easesNotSnaps_andIsMonotoneWithNoOvershoot() {
        var f = CriticallyDampedScalar(value: 0)
        let smoothTime: Float = 0.1

        // First step must move toward the target but NOT snap to it — proof it is
        // smoothing rather than passing through.
        let afterOne = f.update(target: 1, smoothTime: smoothTime, dt: dt60)
        XCTAssertGreaterThan(afterOne, 0, "must move toward target")
        XCTAssertLessThan(afterOne, 0.5, "must not snap to the target in one frame")

        // Drive it out and assert monotone-up and never overshooting past 1.
        var prev = afterOne
        for _ in 0..<600 {   // 10 s of frames — far past convergence
            let v = f.update(target: 1, smoothTime: smoothTime, dt: dt60)
            XCTAssertGreaterThanOrEqual(v, prev - 1e-6, "critically damped ⇒ monotone, never reverses")
            XCTAssertLessThanOrEqual(v, 1.0 + 1e-4, "critically damped ⇒ no overshoot past target")
            prev = v
        }
        XCTAssertEqual(prev, 1.0, accuracy: 1e-3, "converges to the target")
    }

    func test_stepResponse_partiallyConvergedAtSmoothTime() {
        // A critically-damped follower reaches ~59% at t = smoothTime (1 - 3·e⁻²),
        // and ~95% by ~2.4·smoothTime. Assert a wide, robust window proving it is
        // neither snapping (would be ~1.0) nor stalled (would be ~0).
        var f = CriticallyDampedScalar(value: 0)
        let smoothTime: Float = 0.12
        let stepsToSmoothTime = Int((smoothTime / dt60).rounded())   // ~7
        var v: Float = 0
        for _ in 0..<stepsToSmoothTime { v = f.update(target: 1, smoothTime: smoothTime, dt: dt60) }
        // Critically-damped lands ~0.59 at t = smoothTime (the analytic 1 - 3·e⁻²). A
        // tight window pins the second-order COEFFICIENT, not just "not snap / not stall":
        // a degenerate first-order factor 1/(1+x) lands ~0.47 (rejected below) and a
        // wrong 1/(1+x+x²+x³) lands ~0.69 (rejected above).
        XCTAssertGreaterThan(v, 0.54, "should be ~0.59 at t = smoothTime (rejects a first-order factor)")
        XCTAssertLessThan(v, 0.66, "and not over-fast — proves the critically-damped coefficient")
    }

    // MARK: - Frame-rate invariance (the dt-awareness an EMA lacks)

    func test_frameRateInvariance_60vs120_convergeTogetherInWallClock() {
        // Same wall-clock elapsed, different tick rates: a dt-aware follower lands in
        // the same place. A fixed-weight EMA (which the old slerp was) would be ~2×
        // further along at 120 Hz — the wobble users feel across ProMotion/thermal.
        var slow = CriticallyDampedScalar(value: 0)
        var fast = CriticallyDampedScalar(value: 0)
        let smoothTime: Float = 0.15
        let seconds: Float = 0.25

        for _ in 0..<Int((seconds / dt60).rounded()) {
            slow.update(target: 1, smoothTime: smoothTime, dt: dt60)
        }
        for _ in 0..<Int((seconds / dt120).rounded()) {
            fast.update(target: 1, smoothTime: smoothTime, dt: dt120)
        }
        // Real divergence is ~2e-5; a 0.005 tolerance keeps ~250× headroom while staying
        // sensitive enough to catch a future dt-dependence regression.
        XCTAssertEqual(slow.value, fast.value, accuracy: 0.005,
                       "follower must be frame-rate independent (same wall-clock ⇒ same value)")
    }

    // MARK: - No pulse: velocity is continuous across a stepping target

    /// THE discriminating test. Feed a real STAIRCASE — hold, jump, hold, jump again —
    /// the shape a 10 Hz source makes when sampled by a 60 Hz renderer. A correct
    /// second-order follower starts each riser with ~zero velocity and *ramps up*, so its
    /// largest per-frame move comes a few frames AFTER the step, not on it. A first-order
    /// EMA — or the rejected "damp the slerp parameter toward 1" scheme, which snaps to
    /// each fresh sample once it saturates — makes its LARGEST move on the step frame: a
    /// velocity spike = the visible pulse. The SECOND riser (fed after the first has
    /// settled) is what exercises that post-saturation state, so a single step would not
    /// suffice. We assert the ramp on every riser, which only the correct version passes.
    func test_noPulse_velocityRampsAfterEachStaircaseStep() {
        var f = CriticallyDampedScalar(value: 0)
        let smoothTime: Float = 0.1

        func riser(to target: Float, frames: Int) -> [Float] {
            var deltas: [Float] = []
            for _ in 0..<frames {
                let before = f.value
                f.update(target: target, smoothTime: smoothTime, dt: dt60)
                deltas.append(abs(f.value - before))
            }
            return deltas
        }

        _ = riser(to: 0, frames: 1)            // seed/hold at 0
        let s1 = riser(to: 0.5, frames: 12)    // first riser
        let s2 = riser(to: 1.0, frames: 12)    // second riser — AFTER s1 has nearly settled

        for (label, s) in [("step 1", s1), ("step 2", s2)] {
            // Ramp signature: the move on the step frame is smaller than a few frames in.
            XCTAssertLessThan(s[0], s[2], "\(label): velocity must ramp after the step (no spike on it)")
            XCTAssertLessThan(s[0], s[3], "\(label): still ramping a few frames in — the hallmark of no pulse")
            // And no single frame swallows most of the 0.5 riser (a snap would be ~0.5).
            XCTAssertLessThan(s.max() ?? 1, 0.2, "\(label): no frame may snap most of the step")
        }
    }

    func test_movingTarget_tracksWithBoundedLag_neverSnaps() {
        // A continuously moving target (ramp) must be followed smoothly with a small,
        // bounded lag — never caught instantly (that would be a snap) and never lost.
        var f = CriticallyDampedScalar(value: 0)
        let smoothTime: Float = 0.08
        var target: Float = 0
        let perFrame: Float = 0.01
        for _ in 0..<300 {
            target += perFrame
            f.update(target: target, smoothTime: smoothTime, dt: dt60)
            let lag = target - f.value
            XCTAssertGreaterThan(lag, 0, "a smoother lags a rising ramp (never overtakes)")
            XCTAssertLessThan(lag, 0.5, "lag stays bounded — it tracks, not stalls")
        }
    }

    // MARK: - Snap / edge behaviour

    func test_nonPositiveSmoothTime_snaps() {
        var f = CriticallyDampedScalar(value: 5)
        XCTAssertEqual(f.update(target: 9, smoothTime: 0, dt: dt60), 9, accuracy: 0)
        XCTAssertEqual(f.velocity, 0, accuracy: 0)
        XCTAssertEqual(f.update(target: -3, smoothTime: -0.1, dt: dt60), -3, accuracy: 0)
    }

    func test_nonPositiveDt_snaps() {
        var f = CriticallyDampedScalar(value: 2)
        XCTAssertEqual(f.update(target: 7, smoothTime: 0.1, dt: 0), 7, accuracy: 0)
        XCTAssertEqual(f.velocity, 0, accuracy: 0)
    }

    func test_reset_zeroesVelocity() {
        var f = CriticallyDampedScalar(value: 0)
        for _ in 0..<5 { f.update(target: 1, smoothTime: 0.1, dt: dt60) }
        XCTAssertNotEqual(f.velocity, 0, "moving ⇒ nonzero velocity")
        f.reset(to: 3)
        XCTAssertEqual(f.value, 3, accuracy: 0)
        XCTAssertEqual(f.velocity, 0, accuracy: 0, "reset must zero velocity so it does not lurch")
    }
}
