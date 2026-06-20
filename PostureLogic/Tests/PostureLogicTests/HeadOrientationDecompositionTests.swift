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
