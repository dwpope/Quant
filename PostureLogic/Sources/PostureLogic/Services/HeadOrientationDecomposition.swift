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

    // MARK: - Gravity-levelled decomposition (the tilted-camera fix)

    /// Head angles against a **levelled** reference frame instead of the raw
    /// camera frame. The camera-frame path above inherits the phone's physical
    /// tilt: on a propped device, a level head turn is a rotation about an axis
    /// that is *oblique* in camera coordinates, so it decomposes into mixed
    /// yaw+pitch+roll (measured on device: a level turn swung "pitch" by −14°,
    /// and no discrete axis remap could fix it — the mix is continuous).
    ///
    /// The levelled frame (right-handed): X = horizontal camera-right,
    /// Y = `worldUp` (gravity; ARKit `.gravity` world alignment makes this
    /// `(0,1,0)`), Z = horizontal, pointing from the subject toward the camera.
    /// Neutral — subject facing the camera squarely, head upright — is the
    /// levelled frame itself, so all angles read zero regardless of device tilt.
    ///
    /// Decomposition order `R = Ry(turn)·Rx(nod)·Rz(tilt)`, right-hand rule
    /// about the levelled axes: a world-vertical head turn is pure `turn` by
    /// construction, a nod about the horizontal right-axis is pure `nod`, an
    /// ear-to-shoulder tilt about the toward-camera axis is pure `tilt`.
    public static func gravityLevelledHeadAngles(
        headTransform: simd_float4x4,
        cameraTransform: simd_float4x4,
        worldUp: SIMD3<Float> = SIMD3(0, 1, 0)
    ) -> (turn: Float, nod: Float, tilt: Float) {
        let rel = gravityLevelledRelativeRotation(
            headTransform: headTransform, cameraTransform: cameraTransform, worldUp: worldUp)
        return turnNodTilt(rel)
    }

    /// Quaternion sibling of ``gravityLevelledHeadAngles``: the SAME
    /// levelled-relative rotation, undecomposed, for the render path — by
    /// construction it re-decomposes to the same turn/nod/tilt, so the HUD
    /// numbers and the figure can never disagree.
    public static func gravityLevelledRotationQuat(
        headTransform: simd_float4x4,
        cameraTransform: simd_float4x4,
        worldUp: SIMD3<Float> = SIMD3(0, 1, 0)
    ) -> simd_quatf {
        simd_quatf(gravityLevelledRelativeRotation(
            headTransform: headTransform, cameraTransform: cameraTransform, worldUp: worldUp))
    }

    /// `Lᵀ · H`: the head rotation expressed in the levelled camera frame.
    private static func gravityLevelledRelativeRotation(
        headTransform: simd_float4x4,
        cameraTransform: simd_float4x4,
        worldUp: SIMD3<Float>
    ) -> simd_float3x3 {
        let levelled = levelledCameraRotation(cameraTransform, worldUp: worldUp)
        return levelled.transpose * orthonormalUpperLeft(headTransform)
    }

    /// Builds the levelled frame from the camera pose. The camera boresight
    /// (−Z) projected onto the horizontal plane supplies the heading; if the
    /// camera points (near-)straight along gravity that projection collapses,
    /// and the camera's +Y axis — necessarily (near-)horizontal then, since the
    /// frame is orthonormal — supplies it instead.
    ///
    /// CONDITIONING: the heading azimuth's noise sensitivity grows as
    /// ~1/sin(boresight-from-vertical), so a phone lying near-FLAT (boresight
    /// within a few degrees of gravity) turns small IMU wobble into visible turn
    /// jitter. That pose is outside this app's supported setup — face tracking
    /// needs the propped range (boresight ≳30° from vertical), where the frame
    /// is well-conditioned — so it is documented rather than special-cased.
    private static func levelledCameraRotation(
        _ cameraTransform: simd_float4x4,
        worldUp: SIMD3<Float>
    ) -> simd_float3x3 {
        let r = orthonormalUpperLeft(cameraTransform)
        let up = simd_normalize(worldUp)
        var heading = horizontalPart(-r.columns.2, up: up)
        if simd_length(heading) < 1e-4 {
            heading = horizontalPart(r.columns.1, up: up)
        }
        let fh = simd_normalize(heading)
        let x = simd_normalize(simd_cross(fh, up))
        return simd_float3x3(columns: (x, up, -fh))
    }

    private static func horizontalPart(_ v: SIMD3<Float>, up: SIMD3<Float>) -> SIMD3<Float> {
        v - simd_dot(v, up) * up
    }

    /// Decomposes `R = Ry(turn)·Rx(nod)·Rz(tilt)` (degrees). Gimbal-safe: at
    /// nod = ±90° (head aimed straight along gravity — not a posture) tilt is
    /// pinned to 0 and turn resolved from the still-stable elements.
    private static func turnNodTilt(_ m: simd_float3x3) -> (turn: Float, nod: Float, tilt: Float) {
        // Element M[row][col] = m.columns.col[row] (simd is column-major).
        let sinNod = -m.columns.2.y                                   // −M[1][2]
        let cosNod = (m.columns.0.y * m.columns.0.y
                    + m.columns.1.y * m.columns.1.y).squareRoot()     // √(M[1][0]² + M[1][1]²)
        let nodRad = atan2(sinNod, cosNod)

        let turnRad: Float
        let tiltRad: Float
        if cosNod > 1e-6 {
            turnRad = atan2(m.columns.2.x, m.columns.2.z)             // M[0][2], M[2][2]
            tiltRad = atan2(m.columns.0.y, m.columns.1.y)             // M[1][0], M[1][1]
        } else {
            let sp: Float = sinNod > 0 ? 1 : -1
            turnRad = atan2(sp * m.columns.1.x, m.columns.0.x)        // sp·M[0][1], M[0][0]
            tiltRad = 0
        }

        let k = Float(180.0 / .pi)
        return (turnRad * k, nodRad * k, tiltRad * k)
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
