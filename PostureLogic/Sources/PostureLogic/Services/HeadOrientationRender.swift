import simd

/// Pure, viz-only render math that turns a measured head quaternion into the
/// figure-frame rendered quaternion.
///
/// This replaces the legacy per-axis Euler gain stack (×−6 pitch / ×−3 roll /
/// ×−0.6 yaw applied after a `taitBryanZYXDegrees` decomposition) with ONE
/// uniform rotation-angle gain + ONE total-angle clamp + a fixed basis remap.
/// The decomposition leaked yaw→pitch and the anisotropic gains magnified the
/// leak, so a level left↔right turn "dipped" twice. Carrying the quaternion
/// through a single uniform-angle gain has no per-axis channel to leak into, so
/// a single-axis input rotation produces a single-axis output rotation **by
/// construction** — the structural fix proved by `HeadOrientationRenderTests`.
///
/// Headless-pure: `import simd` only. This must NEVER feed scoring; it is render
/// math for the figure head and nothing else.
public struct HeadOrientationRender: Equatable, Sendable {

    /// Uniform rotation-angle gain. `1.0` is faithful (no exaggeration); the same
    /// scalar scales the rotation about whatever axis the head turned, so it can
    /// never introduce a cross-axis leak the way the old per-axis gains did.
    public var gain: Float

    /// Clamp on the TOTAL rendered rotation angle (about the gained axis), a sane
    /// head limit. Defaults to 60°. Applied after the gain, before the basis remap.
    public var maxAngleRadians: Float

    /// The FIXED basis-remap `B` into the figure's Z-up frame
    /// (yaw=+Z, pitch=+X, roll=+Y). Applied by conjugation so it remaps the axis of
    /// rotation without altering the rotation angle — single-axis-in stays
    /// single-axis-out. DEVICE-CONFIRM in R5: defaults to identity so the math's
    /// correctness and the no-leak invariant do NOT depend on `B`'s particular value.
    public var basis: simd_quatf

    public init(
        gain: Float = 1.0,
        maxAngleRadians: Float = 60 * .pi / 180,
        basis: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    ) {
        self.gain = gain
        self.maxAngleRadians = maxAngleRadians
        self.basis = basis
    }

    /// Angles below this are treated as "no rotation": the axis is numerically
    /// undefined near identity, so we return identity for the gain/clamp steps.
    private static let angleEpsilon: Float = 1e-5

    /// Render a measured head orientation, expressed relative to a captured rest
    /// pose, into the figure frame.
    ///
    /// Order: rest-relative → uniform angle gain → angle clamp → basis remap. A
    /// neutral head (`head == rest`) yields identity; a single-axis input rotation
    /// yields a single-axis output rotation.
    public func render(head: simd_quatf, rest: simd_quatf) -> simd_quatf {
        // 1. Rest-relative: neutral head (head == rest) → identity.
        let qRel = (rest.inverse * head).normalized

        // 2. Shortest-path normalize. q and -q are the same rotation; forcing
        //    real ≥ 0 keeps `.angle` the short way in [0, π] so gain/clamp act on
        //    the intuitive (small) angle and the axis is the short-path axis.
        let qShort = qRel.real < 0
            ? simd_quatf(ix: -qRel.imag.x, iy: -qRel.imag.y, iz: -qRel.imag.z, r: -qRel.real)
            : qRel

        let angle = qShort.angle

        // Near-identity guard: axis is undefined as angle → 0. Returning identity
        // here (rather than reading an arbitrary axis) keeps the result finite.
        guard angle > Self.angleEpsilon else {
            return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        }
        let axis = qShort.axis

        // 3. Uniform gain: scale the angle about the SAME axis.
        let gained = Self.scaledAngle(angle, by: gain)

        // 4. Clamp the TOTAL rendered angle, axis preserved.
        let capped = Self.clampedAngle(gained, to: maxAngleRadians)

        let qClamped = simd_quatf(angle: capped, axis: axis)

        // 5. Basis remap into the figure frame by conjugation. Conjugation rotates
        //    the axis but leaves the rotation angle untouched, so a single-axis
        //    rotation maps to a single-axis rotation about the remapped axis.
        return (basis * qClamped * basis.inverse).normalized
    }

    // MARK: - Unit-testable angle helpers

    /// Scale a rotation angle by a uniform gain. Pure scalar; the caller pairs it
    /// with the preserved axis to rebuild the quaternion.
    public static func scaledAngle(_ angle: Float, by gain: Float) -> Float {
        angle * gain
    }

    /// Cap a rotation angle at `maxAngle` (a non-negative ceiling). The axis is the
    /// caller's responsibility and is preserved across the clamp.
    public static func clampedAngle(_ angle: Float, to maxAngle: Float) -> Float {
        min(angle, maxAngle)
    }
}
