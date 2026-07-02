import Foundation
import simd

/// Pure, ARKit-free decomposition of a 3D head-pose rotation into yaw/pitch/roll
/// degrees. An app-side provider extracts the two `simd_float4x4` transforms from
/// `ARFaceAnchor` / `ARFrame.camera` (the only ARKit-touching code) and hands plain
/// matrices here, so every line of trig is unit-tested headlessly in the package.
///
/// Why this beats the monocular 2D estimate it supersedes: those three formulas
/// each measured one axis off the *appearance* of a 2D face and assumed the other
/// two were zero, so a turn leaked into a phantom nod (the "W"). A real 3D rotation
/// has no such leak — a pure yaw rotation decomposes to `pitch = atan2(0, …) = 0`
/// exactly, by construction, not by correction.
///
/// Convention: ZYX Tait-Bryan (yaw about +Z, pitch about +Y, roll about +X), i.e.
/// the rotation is read as `R = Rz(yaw)·Ry(pitch)·Rx(roll)`. The mapping from these
/// internal axes onto the physical turn/nod/tilt the figure renders — and the three
/// per-axis signs — is dialed on device via the binding gains (the same place the
/// legacy signal's direction lived); this function commits only to a *consistent*
/// convention so the decoupling invariants hold regardless of those sign choices.
public enum HeadOrientationDecomposition {

    /// Decomposes a rotation matrix (column-major, right-handed) into
    /// yaw/pitch/roll degrees. Gimbal-safe: all-`atan2`, no bare `asin`, and a
    /// stable branch at pitch = ±90° so output is always finite.
    public static func taitBryanZYXDegrees(_ r: simd_float3x3) -> (yaw: Float, pitch: Float, roll: Float) {
        let c0 = r.columns.0   // image of the body +X axis
        let c1 = r.columns.1
        let c2 = r.columns.2

        // cos(pitch) recovered from the first column's horizontal extent. simd is
        // column-major, so c0 = (R00, R10, R20) in math (row,col) terms.
        let cosPitch = (c0.x * c0.x + c0.y * c0.y).squareRoot()
        let pitchRad = atan2(-c0.z, cosPitch)

        let yawRad: Float
        let rollRad: Float
        if cosPitch > 1e-6 {
            yawRad = atan2(c0.y, c0.x)
            rollRad = atan2(c1.z, c2.z)
        } else {
            // Gimbal lock (pitch ≈ ±90°): yaw and roll collapse onto one axis.
            // Pin roll = 0 and resolve yaw from the still-stable elements so the
            // result never goes NaN.
            yawRad = atan2(-c1.x, c1.y)
            rollRad = 0
        }

        let k = Float(180.0 / .pi)
        return (yawRad * k, pitchRad * k, rollRad * k)
    }

    /// Convenience: decompose the rotation embedded in a 4x4 transform, ignoring
    /// translation and re-orthonormalizing the rotation block (ARKit's rigid
    /// transforms can carry tiny numeric scale/skew that would otherwise perturb
    /// the extraction).
    public static func taitBryanZYXDegrees(_ transform: simd_float4x4) -> (yaw: Float, pitch: Float, roll: Float) {
        taitBryanZYXDegrees(orthonormalUpperLeft(transform))
    }

    /// The full Layer-1 path: head orientation **relative to the camera**, with an
    /// optional portrait/mirror fix-up applied before decomposition.
    ///
    /// `relative = inverse(camera) · head` expresses the face pose in camera space,
    /// so the result depends only on the head's pose *relative to the lens* and not
    /// on where that pair sits in ARKit's world frame — isolating the head turn from
    /// world-tracking placement. `portraitFixUp` re-bases ARKit's landscape-referenced
    /// camera axes onto the portrait screen (computed app-side, where the device
    /// orientation is known); identity by default so the math stays testable.
    public static func taitBryanZYXDegrees(
        headTransform: simd_float4x4,
        cameraTransform: simd_float4x4,
        portraitFixUp: simd_float3x3 = matrix_identity_float3x3
    ) -> (yaw: Float, pitch: Float, roll: Float) {
        let relative = simd_inverse(cameraTransform) * headTransform
        let screen = portraitFixUp * orthonormalUpperLeft(relative)
        return taitBryanZYXDegrees(screen)
    }

    /// The head origin expressed in CAMERA space, in meters — the translation part
    /// of `inverse(camera) · head`, which the orientation paths above discard.
    /// This is the metric lean-in / viewing-distance signal (TrueDepth-accurate):
    /// independent of where the head/camera pair sits in ARKit's world frame, and
    /// of head rotation. ARKit's camera looks down its −Z, so a face in front of
    /// the lens has negative z; `simd_length` of the result is the head-to-camera
    /// distance. No `portraitFixUp` parameter: distance is rotation-invariant, and
    /// consumers of the raw vector re-base axes themselves if they ever need to.
    public static func cameraSpaceHeadPosition(
        headTransform: simd_float4x4,
        cameraTransform: simd_float4x4
    ) -> SIMD3<Float> {
        let relative = simd_inverse(cameraTransform) * headTransform
        let t = relative.columns.3
        return SIMD3(t.x, t.y, t.z)
    }

    // MARK: - Quaternion siblings (viz-only passthrough)

    /// The orthonormalized screen-frame head rotation as a `simd_quatf`, built from
    /// the SAME upper-left 3x3 the Euler `taitBryanZYXDegrees(_:)` decomposes. Lets a
    /// later viz stage drive the figure head from the quaternion directly instead of
    /// re-amplifying decomposed Euler axes — by construction it agrees with the Euler
    /// path (its matrix re-decomposes to the same yaw/pitch/roll). Viz-only: this
    /// never feeds scoring.
    public static func screenRotationQuat(_ transform: simd_float4x4) -> simd_quatf {
        simd_quatf(orthonormalUpperLeft(transform))
    }

    /// Camera-relative quaternion sibling of
    /// `taitBryanZYXDegrees(headTransform:cameraTransform:portraitFixUp:)`: the same
    /// `portraitFixUp · orthonormalUpperLeft(inverse(camera) · head)` screen-frame
    /// rotation, returned as a `simd_quatf` rather than decomposed Euler degrees.
    public static func screenRotationQuat(
        headTransform: simd_float4x4,
        cameraTransform: simd_float4x4,
        portraitFixUp: simd_float3x3 = matrix_identity_float3x3
    ) -> simd_quatf {
        let relative = simd_inverse(cameraTransform) * headTransform
        let screen = portraitFixUp * orthonormalUpperLeft(relative)
        return simd_quatf(screen)
    }

    /// Extracts the upper-left 3x3 and re-orthonormalizes via Gram-Schmidt,
    /// producing a proper right-handed rotation (`c2 = c0 × c1`) even if the input
    /// carried float drift.
    private static func orthonormalUpperLeft(_ m: simd_float4x4) -> simd_float3x3 {
        let a = SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z)
        let b = SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z)
        let c0 = simd_normalize(a)
        var c1 = b - simd_dot(b, c0) * c0
        let len = simd_length(c1)
        c1 = len > 1e-6 ? c1 / len : c1
        let c2 = simd_cross(c0, c1)
        return simd_float3x3(columns: (c0, c1, c2))
    }
}
