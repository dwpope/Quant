import XCTest
import simd
@testable import PostureLogic

/// Proves the ARKit head-pose decomposition is DECOUPLED at the source: a pure
/// rotation about one axis recovers that axis only, with the other two exactly
/// zero. This is the structural guarantee the monocular 2D path could never make
/// (its pitch leaked from yaw — the "W"). Synthetic simd matrices only; no ARKit
/// import, so it runs headlessly in the package against CI.
final class HeadOrientationDecompositionTests: XCTestCase {

    // MARK: - Rotation-matrix builders (column-major, right-handed)

    private func rx(_ deg: Float) -> simd_float3x3 {
        let t = deg * .pi / 180, c = cos(t), s = sin(t)
        return simd_float3x3(columns: (
            SIMD3(1, 0, 0),
            SIMD3(0, c, s),
            SIMD3(0, -s, c)
        ))
    }
    private func ry(_ deg: Float) -> simd_float3x3 {
        let t = deg * .pi / 180, c = cos(t), s = sin(t)
        return simd_float3x3(columns: (
            SIMD3(c, 0, -s),
            SIMD3(0, 1, 0),
            SIMD3(s, 0, c)
        ))
    }
    private func rz(_ deg: Float) -> simd_float3x3 {
        let t = deg * .pi / 180, c = cos(t), s = sin(t)
        return simd_float3x3(columns: (
            SIMD3(c, s, 0),
            SIMD3(-s, c, 0),
            SIMD3(0, 0, 1)
        ))
    }

    private func decompose(_ m: simd_float3x3) -> (yaw: Float, pitch: Float, roll: Float) {
        HeadOrientationDecomposition.taitBryanZYXDegrees(m)
    }

    // MARK: - 1-3: pure-axis decoupling (the headline proof)

    func test_pureYaw_yieldsZeroPitchAndRoll() {
        for theta: Float in [-60, -30, -10, 10, 30, 60] {
            let out = decompose(rz(theta))
            XCTAssertEqual(out.pitch, 0, accuracy: 1e-3, "pure yaw \(theta) leaked pitch")
            XCTAssertEqual(out.roll, 0, accuracy: 1e-3, "pure yaw \(theta) leaked roll")
            XCTAssertEqual(out.yaw, theta, accuracy: 1e-3)
        }
    }

    func test_purePitch_yieldsZeroYawAndRoll() {
        for theta: Float in [-60, -30, -10, 10, 30, 60] {
            let out = decompose(ry(theta))
            XCTAssertEqual(out.yaw, 0, accuracy: 1e-3, "pure pitch \(theta) leaked yaw")
            XCTAssertEqual(out.roll, 0, accuracy: 1e-3, "pure pitch \(theta) leaked roll")
            XCTAssertEqual(out.pitch, theta, accuracy: 1e-3)
        }
    }

    func test_pureRoll_yieldsZeroYawAndPitch() {
        for theta: Float in [-60, -30, -10, 10, 30, 60] {
            let out = decompose(rx(theta))
            XCTAssertEqual(out.yaw, 0, accuracy: 1e-3, "pure roll \(theta) leaked yaw")
            XCTAssertEqual(out.pitch, 0, accuracy: 1e-3, "pure roll \(theta) leaked pitch")
            XCTAssertEqual(out.roll, theta, accuracy: 1e-3)
        }
    }

    // MARK: - 5: identity

    func test_identity_isZero() {
        let out = decompose(matrix_identity_float3x3)
        XCTAssertEqual(out.yaw, 0, accuracy: 1e-6)
        XCTAssertEqual(out.pitch, 0, accuracy: 1e-6)
        XCTAssertEqual(out.roll, 0, accuracy: 1e-6)
    }

    // MARK: - 6: composed small angles re-decompose self-consistently

    func test_composedSmallAngles_roundTrip() {
        let triples: [(Float, Float, Float)] = [  // (yaw, pitch, roll)
            (10, 5, -8), (-15, 12, 6), (20, -10, 15), (-5, -20, -12),
        ]
        for (y, p, r) in triples {
            // Build R = Rz(yaw) * Ry(pitch) * Rx(roll) — the ZYX order the
            // decomposition inverts.
            let m = rz(y) * ry(p) * rx(r)
            let out = decompose(m)
            XCTAssertEqual(out.yaw, y, accuracy: 1e-2, "yaw of \(y),\(p),\(r)")
            XCTAssertEqual(out.pitch, p, accuracy: 1e-2, "pitch of \(y),\(p),\(r)")
            XCTAssertEqual(out.roll, r, accuracy: 1e-2, "roll of \(y),\(p),\(r)")
        }
    }

    // MARK: - 7: gimbal lock produces finite (never NaN) output

    func test_gimbalLock_isFinite() {
        for theta: Float in [90, -90] {
            let out = decompose(ry(theta))
            XCTAssertTrue(out.yaw.isFinite, "yaw NaN at pitch \(theta)")
            XCTAssertTrue(out.pitch.isFinite, "pitch NaN at pitch \(theta)")
            XCTAssertTrue(out.roll.isFinite, "roll NaN at pitch \(theta)")
            XCTAssertEqual(out.pitch, theta, accuracy: 1e-2)
        }
    }

    // MARK: - 8: tolerates a slightly non-orthonormal matrix (ARKit numeric scale)

    func test_slightlyNonOrthonormal_staysFinite() {
        var m = rz(20) * ry(10)
        // Perturb a column's scale, as ARKit's rigid transforms can carry tiny
        // numeric drift.
        m.columns.0 *= 1.0003
        m.columns.2 *= 0.9997
        let out = decompose(m)
        XCTAssertTrue(out.yaw.isFinite && out.pitch.isFinite && out.roll.isFinite)
        // Still close to the intended pose.
        XCTAssertEqual(out.yaw, 20, accuracy: 0.5)
        XCTAssertEqual(out.pitch, 10, accuracy: 0.5)
    }

    // MARK: - 4x4 overload ignores translation + re-orthonormalizes

    func test_4x4Overload_ignoresTranslation() {
        let r = rz(25) * rx(8)
        var m = matrix_identity_float4x4
        m.columns.0 = SIMD4(r.columns.0, 0)
        m.columns.1 = SIMD4(r.columns.1, 0)
        m.columns.2 = SIMD4(r.columns.2, 0)
        m.columns.3 = SIMD4(0.5, -0.3, 1.2, 1)  // translation must not matter
        let out = HeadOrientationDecomposition.taitBryanZYXDegrees(m)
        XCTAssertEqual(out.yaw, 25, accuracy: 1e-2)
        XCTAssertEqual(out.roll, 8, accuracy: 1e-2)
        XCTAssertEqual(out.pitch, 0, accuracy: 1e-2)
    }

    // MARK: - camera-relative overload depends only on head-vs-camera pose

    /// The decisive ARFace property: the decomposed angle depends ONLY on the head's
    /// pose relative to the lens, not on where that head+camera pair sits in ARKit's
    /// world frame. Same relative pose embedded at two different world placements
    /// (here, a tilted device carrying both) → identical decomposed angles, because
    /// `inverse(camera)·head` cancels the shared world transform.
    // MARK: - quaternion sibling agrees with the Euler path

    /// Builds a 4x4 from a rotation 3x3 (no translation).
    private func xform(_ r: simd_float3x3) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.0 = SIMD4(r.columns.0, 0)
        m.columns.1 = SIMD4(r.columns.1, 0)
        m.columns.2 = SIMD4(r.columns.2, 0)
        return m
    }

    /// The decisive R1 proof: `screenRotationQuat` carries the SAME screen-frame
    /// rotation the Euler path decomposes. Re-decompose the quaternion's matrix and
    /// it must match the yaw/pitch/roll obtained by decomposing the original matrix
    /// directly — pure yaw, pure pitch, and a combined rotation.
    func test_screenRotationQuat_agreesWithEulerPath() {
        let mats: [(name: String, m: simd_float3x3)] = [
            ("pureYaw", rz(35)),
            ("purePitch", ry(-22)),
            ("pureRoll", rx(18)),
            ("combined", rz(15) * ry(-10) * rx(8)),
            ("identity", matrix_identity_float3x3),
        ]
        for (name, m) in mats {
            let euler = HeadOrientationDecomposition.taitBryanZYXDegrees(m)
            let quat = HeadOrientationDecomposition.screenRotationQuat(xform(m))
            // Decompose the quaternion's own rotation matrix back to Euler.
            let viaQuat = HeadOrientationDecomposition.taitBryanZYXDegrees(simd_float3x3(quat))
            XCTAssertEqual(viaQuat.yaw, euler.yaw, accuracy: 1e-3, "\(name) yaw")
            XCTAssertEqual(viaQuat.pitch, euler.pitch, accuracy: 1e-3, "\(name) pitch")
            XCTAssertEqual(viaQuat.roll, euler.roll, accuracy: 1e-3, "\(name) roll")
        }
    }

    /// The camera-relative quaternion sibling matches its Euler counterpart for the
    /// full `inverse(camera)·head` + `portraitFixUp` path.
    func test_screenRotationQuat_cameraRelative_agreesWithEulerPath() {
        let head = xform(rz(20) * ry(-12) * rx(6))
        let camera = xform(rx(9) * ry(4))
        let fixUp = rz(90)   // a non-identity portrait re-base
        let euler = HeadOrientationDecomposition.taitBryanZYXDegrees(
            headTransform: head, cameraTransform: camera, portraitFixUp: fixUp)
        let quat = HeadOrientationDecomposition.screenRotationQuat(
            headTransform: head, cameraTransform: camera, portraitFixUp: fixUp)
        let viaQuat = HeadOrientationDecomposition.taitBryanZYXDegrees(simd_float3x3(quat))
        XCTAssertEqual(viaQuat.yaw, euler.yaw, accuracy: 1e-3, "yaw")
        XCTAssertEqual(viaQuat.pitch, euler.pitch, accuracy: 1e-3, "pitch")
        XCTAssertEqual(viaQuat.roll, euler.roll, accuracy: 1e-3, "roll")
    }

    func test_cameraRelative_cancelsDeviceTilt() {
        let head = rz(15) * ry(10)          // some fixed head pose in world
        var headXform = matrix_identity_float4x4
        headXform.columns.0 = SIMD4(head.columns.0, 0)
        headXform.columns.1 = SIMD4(head.columns.1, 0)
        headXform.columns.2 = SIMD4(head.columns.2, 0)

        func cam(tiltDeg: Float) -> simd_float4x4 {
            let r = rx(tiltDeg) * ry(tiltDeg * 0.5)
            var m = matrix_identity_float4x4
            m.columns.0 = SIMD4(r.columns.0, 0)
            m.columns.1 = SIMD4(r.columns.1, 0)
            m.columns.2 = SIMD4(r.columns.2, 0)
            m.columns.3 = SIMD4(0.1, 0.2, 0.3, 1)
            return m
        }

        let a = HeadOrientationDecomposition.taitBryanZYXDegrees(
            headTransform: cam(tiltDeg: 0) * headXform, cameraTransform: cam(tiltDeg: 0))
        let b = HeadOrientationDecomposition.taitBryanZYXDegrees(
            headTransform: cam(tiltDeg: 12) * headXform, cameraTransform: cam(tiltDeg: 12))
        XCTAssertEqual(a.yaw, b.yaw, accuracy: 1e-2, "device tilt leaked into yaw")
        XCTAssertEqual(a.pitch, b.pitch, accuracy: 1e-2, "device tilt leaked into pitch")
        XCTAssertEqual(a.roll, b.roll, accuracy: 1e-2, "device tilt leaked into roll")
    }
}

/// Camera-space head POSITION (the translation the orientation path discards).
/// This is the metric lean-in/viewing-distance signal: where the head origin sits
/// relative to the lens, in meters, independent of where the pair sits in ARKit's
/// world frame and of how either is rotated.
extension HeadOrientationDecompositionTests {

    private func xform(_ r: simd_float3x3, _ t: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(r.columns.0, 0),
            SIMD4(r.columns.1, 0),
            SIMD4(r.columns.2, 0),
            SIMD4(t, 1)
        ))
    }
    private func identityAt(_ t: SIMD3<Float>) -> simd_float4x4 {
        xform(matrix_identity_float3x3, t)
    }

    func test_headPosition_halfMeterInFrontOfIdentityCamera() {
        // ARKit camera looks down its -Z: a face 0.5 m in front sits at z = -0.5.
        let pos = HeadOrientationDecomposition.cameraSpaceHeadPosition(
            headTransform: identityAt(SIMD3(0, 0, -0.5)),
            cameraTransform: matrix_identity_float4x4)
        XCTAssertEqual(pos.x, 0, accuracy: 1e-5)
        XCTAssertEqual(pos.y, 0, accuracy: 1e-5)
        XCTAssertEqual(pos.z, -0.5, accuracy: 1e-5)
        XCTAssertEqual(simd_length(pos), 0.5, accuracy: 1e-5)
    }

    func test_headPosition_invariantToCameraWorldPose() {
        // Same head-relative-to-lens offset, but the camera is somewhere else in the
        // world and rotated: the recovered camera-space position must be the offset,
        // exactly — world placement must cancel (this is what makes the distance
        // signal immune to ARKit world-tracking drift).
        let offset = SIMD3<Float>(0.1, -0.2, -0.6)
        let camRot = rz(37) * ry(-20) * rx(11)
        let camPos = SIMD3<Float>(2, 1, 3)
        let camera = xform(camRot, camPos)
        let head = identityAt(camRot * offset + camPos)
        let pos = HeadOrientationDecomposition.cameraSpaceHeadPosition(
            headTransform: head, cameraTransform: camera)
        XCTAssertEqual(pos.x, offset.x, accuracy: 1e-4)
        XCTAssertEqual(pos.y, offset.y, accuracy: 1e-4)
        XCTAssertEqual(pos.z, offset.z, accuracy: 1e-4)
    }

    func test_headPosition_unaffectedByHeadRotation() {
        // Turning the head must not move the measured position: distance is a
        // translation-only signal (a head turn at fixed distance reads constant).
        let t = SIMD3<Float>(0.05, -0.1, -0.55)
        let still = HeadOrientationDecomposition.cameraSpaceHeadPosition(
            headTransform: identityAt(t), cameraTransform: matrix_identity_float4x4)
        let turned = HeadOrientationDecomposition.cameraSpaceHeadPosition(
            headTransform: xform(rz(40) * rx(-15), t), cameraTransform: matrix_identity_float4x4)
        XCTAssertEqual(still.x, turned.x, accuracy: 1e-5)
        XCTAssertEqual(still.y, turned.y, accuracy: 1e-5)
        XCTAssertEqual(still.z, turned.z, accuracy: 1e-5)
    }

    func test_headPosition_coincidentTransforms_isZero() {
        let m = xform(ry(25), SIMD3(1, 2, 3))
        let pos = HeadOrientationDecomposition.cameraSpaceHeadPosition(
            headTransform: m, cameraTransform: m)
        XCTAssertEqual(simd_length(pos), 0, accuracy: 1e-5)
    }
}
