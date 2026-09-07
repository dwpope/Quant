/// A frame-rate-independent, critically-damped follower for one scalar — the
/// second-order ("SmoothDamp") analogue of an exponential low-pass.
///
/// **Why second-order.** A fixed-weight EMA (`value += alpha * (target - value)`)
/// is *first-order*: its velocity is proportional to the distance to the target, so
/// the instant the target jumps the output velocity jumps with it. When the source
/// is a stepwise signal — e.g. the head-angle pipeline republishing a fresh sample at
/// ~10 Hz while the renderer ticks at 60–120 Hz — that velocity jump-then-decay on
/// every step *is* the ~10 Hz "pulse/throb" the rig was showing. This follower carries
/// a `velocity` term, so when the target steps the *acceleration* jumps but the
/// *velocity* stays continuous (it ramps up smoothly from where it was). No spike, no
/// pulse; the motion reads as one fluid arc.
///
/// **Why critically damped.** The spring is tuned to the critical-damping ratio, so it
/// converges as fast as possible *without overshoot or ringing* — exactly what a head
/// pose wants (an under-damped follower would wobble past the target).
///
/// `update(target:smoothTime:dt:)` is the standard analytic SmoothDamp step
/// (Game Programming Gems 4 §1.10 / Unity `Mathf.SmoothDamp`): it integrates the
/// critically-damped spring in *closed form*, so it is exact and unconditionally
/// stable for any `dt` (no sub-stepping, no blow-up at a large `dt` after a stall).
/// `smoothTime` is the approximate seconds-to-converge — a true time constant, hence
/// frame-rate independent — **not** a per-frame blend weight.
///
/// Pure value type (no Foundation, no `simd`, no actor isolation) so it unit-tests
/// headlessly and is safe to embed in the value-type-only render binding. Compose four
/// of these to smooth a quaternion component-wise (the renderer does exactly that).
public struct CriticallyDampedScalar: Equatable, Sendable {

    /// Current smoothed value.
    public private(set) var value: Float

    /// Current rate of change (units/second), carried across calls. This is the
    /// state that makes the follower second-order — an EMA has no equivalent, which
    /// is precisely why an EMA pulses on a stepping target and this does not.
    public private(set) var velocity: Float

    public init(value: Float = 0, velocity: Float = 0) {
        self.value = value
        self.velocity = velocity
    }

    /// Hard-set the value and zero the velocity. Use on (re)seed — the first frame,
    /// or after a tracking dropout — so the follower starts *at* the live pose rather
    /// than easing in from a stale one (or from identity).
    public mutating func reset(to newValue: Float) {
        value = newValue
        velocity = 0
    }

    /// Advances one analytic critically-damped step toward `target`.
    ///
    /// - Parameters:
    ///   - target: where to head. May move every call — that is the whole point; the
    ///     follower chases a live target with continuous velocity.
    ///   - smoothTime: approximate seconds to converge. `<= 0` snaps to `target` and
    ///     zeroes velocity (reproduces "no smoothing").
    ///   - dt: elapsed seconds since the last call. `<= 0` snaps (nothing to integrate).
    /// - Returns: the new ``value``.
    @discardableResult
    public mutating func update(target: Float, smoothTime: Float, dt: Float) -> Float {
        guard smoothTime > 0, dt > 0 else {
            value = target
            velocity = 0
            return value
        }

        // Critically-damped spring with natural frequency ω = 2 / smoothTime.
        let omega = 2 / smoothTime
        let x = omega * dt
        // Rational (Padé-style) approximation of e^{-x}: the closed-form integrator's
        // damping factor. Cheap, and stays in (0, 1] for every x >= 0 (so the step is
        // always stable, unlike an explicit Euler spring that diverges at large dt).
        let expFactor = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)

        let originalValue = value
        let originalTarget = target
        let change = originalValue - originalTarget
        let temp = (velocity + omega * change) * dt
        velocity = (velocity - omega * temp) * expFactor
        var output = originalTarget + (change + temp) * expFactor

        // Overshoot guard: if this step crossed the (original) target, clamp to it and
        // kill the residual velocity. Only fires when the target is static or slow
        // relative to smoothTime; a fast-moving target never trips it.
        if (originalTarget - originalValue > 0) == (output > originalTarget) {
            output = originalTarget
            velocity = (output - originalTarget) / dt   // == 0
        }

        value = output
        return value
    }
}
