import simd

/// A critically-damped follower for a full 3-D orientation — the quaternion companion
/// to ``CriticallyDampedScalar``. It eases a rendered rotation toward a (possibly
/// per-frame-moving) target with continuous angular velocity, so a stepwise pose source
/// reads as one fluid, pulse-free arc.
///
/// **How.** It SmoothDamps the quaternion's four components *independently* toward the
/// target, then renormalizes — the standard "nlerp-style" quaternion smoothing. Because
/// all four chase the *same* target together (not three independent Euler axes), a
/// blended nod+turn stays on the short arc, so a head "circle" traces round rather than
/// each axis jerking. A **shortest-path sign flip** (a quaternion `q` and `-q` are the
/// same rotation) aims at whichever sign is nearer the current value, so it never eases
/// "the long way" around through identity.
///
/// **Why component-wise and not a damped slerp parameter.** Damping a scalar `s` toward
/// 1 and `slerp(rendered, target, s)` *snaps* to every fresh sample once `s` saturates
/// near 1 — it cannot follow a moving target. Carrying velocity in the components keeps
/// the follow continuous across a target step (no pulse); the small departure from an
/// exact geodesic is second-order and sub-visual at the head's capped angles.
///
/// Pure value type (no entity, no RealityKit, no actor isolation) so it unit-tests
/// headlessly and is safe to embed in the value-type-only render binding.
public struct DampedOrientation: Equatable, Sendable {
    private var x = CriticallyDampedScalar()
    private var y = CriticallyDampedScalar()
    private var z = CriticallyDampedScalar()
    private var w = CriticallyDampedScalar()
    private var seeded = false

    public init() {}

    /// The current smoothed, re-normalized rotation (identity until first seeded).
    public var current: simd_quatf {
        let v = SIMD4<Float>(x.value, y.value, z.value, w.value)
        let len = simd_length(v)
        return len > 1e-6 ? simd_quatf(vector: v / len) : simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    }

    /// Snap to `q` and zero all component velocities (first frame / post-dropout reseed).
    public mutating func reset(to q: simd_quatf) {
        let v = q.vector   // (.x,.y,.z) = imaginary, .w = real
        x.reset(to: v.x); y.reset(to: v.y); z.reset(to: v.z); w.reset(to: v.w)
        seeded = true
    }

    /// Eases one `dt` step toward `target` and returns the new rendered rotation. An
    /// unseeded follower, or a non-positive `smoothTime`/`dt`, snaps (and seeds) — so the
    /// first frame and "smoothing off" both reproduce a direct write.
    @discardableResult
    public mutating func update(toward target: simd_quatf, smoothTime: Float, dt: Float) -> simd_quatf {
        guard seeded, smoothTime > 0, dt > 0 else {
            reset(to: target)
            return current
        }
        // Double cover: q and -q are the same rotation. Aim at whichever sign is nearer
        // the current value so each component eases along the short arc.
        let cur = SIMD4<Float>(x.value, y.value, z.value, w.value)
        var t = target.vector
        if simd_dot(cur, t) < 0 { t = -t }
        x.update(target: t.x, smoothTime: smoothTime, dt: dt)
        y.update(target: t.y, smoothTime: smoothTime, dt: dt)
        z.update(target: t.z, smoothTime: smoothTime, dt: dt)
        w.update(target: t.w, smoothTime: smoothTime, dt: dt)
        return current
    }
}
