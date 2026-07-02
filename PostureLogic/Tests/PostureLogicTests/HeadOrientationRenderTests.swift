import XCTest
import simd
@testable import PostureLogic

/// Proves the quaternion render path is STRUCTURALLY decoupled: a pure rotation
/// about ONE axis renders to a pure rotation about ONE axis, no matter the basis
/// remap — so a level left↔right turn can never "dip" into pitch. This is the
/// guarantee the old Euler gain stack could not make (its `taitBryanZYXDegrees`
/// decomposition leaked yaw→pitch and the ×−6 pitch gain magnified the leak).
/// Synthetic simd quaternions only; no ARKit import, so it runs headlessly.
final class HeadOrientationRenderTests: XCTestCase {

    private let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    private func quat(angleDeg: Float, axis: SIMD3<Float>) -> simd_quatf {
        simd_quatf(angle: angleDeg * .pi / 180, axis: simd_normalize(axis))
    }

    /// Re-decompose a rendered quaternion to figure-frame Euler degrees via the
    /// authoritative R1 helper (does NOT touch `taitBryanZYXDegrees`'s definition).
    private func euler(_ q: simd_quatf) -> (yaw: Float, pitch: Float, roll: Float) {
        HeadOrientationDecomposition.taitBryanZYXDegrees(simd_float3x3(q))
    }

    // MARK: - 1. THE INVARIANT: single-axis-in → single-axis-out (the "no dip" proof)

    /// Part A: an arbitrary tilted input axis + a non-identity basis. Across a
    /// −50°…+50° sweep the OUTPUT axis is CONSTANT (all parallel) and the output
    /// angle tracks |θ|. Conjugation preserves single-axis rotation by construction.
    func testInvariant_outputAxisConstant_andAngleTracksInput() {
        // A deliberately non-trivial, tilted input axis.
        let a = simd_normalize(SIMD3<Float>(0.3, -0.7, 0.65))
        // A non-identity basis remap (arbitrary 37° about a tilted axis).
        let basis = quat(angleDeg: 37, axis: SIMD3(0.2, 0.9, -0.4))
        let render = HeadOrientationRender(gain: 1, maxAngleRadians: 200 * .pi / 180, basis: basis)

        var referenceAxis: SIMD3<Float>?
        for thetaDeg in stride(from: Float(-50), through: 50, by: 5) {
            // Skip ~0 where the axis is undefined (covered by the guard test).
            guard abs(thetaDeg) > 1 else { continue }

            let head = quat(angleDeg: thetaDeg, axis: a)
            let out = render.render(head: head, rest: identity)

            // Output angle tracks the input magnitude (gain = 1, away from clamp).
            XCTAssertEqual(out.angle, abs(thetaDeg) * .pi / 180, accuracy: 1e-4,
                           "output angle must track |θ| at θ=\(thetaDeg)")

            // Output axis is constant across the whole sweep (parallel within 1e-3).
            // Sign of the axis flips with the sign of θ (q(−θ,a) == q(θ,−a)); compare
            // the orientation line, not the ray, by aligning signs.
            let axis = simd_normalize(out.axis)
            if let ref = referenceAxis {
                let aligned = simd_dot(axis, ref) < 0 ? -axis : axis
                XCTAssertEqual(simd_length(aligned - ref), 0, accuracy: 1e-3,
                               "output axis must be constant across the sweep at θ=\(thetaDeg)")
            } else {
                referenceAxis = axis
            }
        }
        XCTAssertNotNil(referenceAxis, "sweep must have produced at least one sample")
    }

    /// Part B: choose `a` and `basis` so the remapped axis is the figure yaw axis
    /// +Z. Then EVERY θ must render with |pitch|,|roll| < 1e-3° — a pure turn
    /// produces zero pitch/roll. This is the structural kill of the dip bug.
    func testInvariant_remappedToFigureYaw_producesZeroPitchAndRoll() {
        // Pick an input axis `a`; choose `basis` to map `a` onto +Z. The simplest
        // construction: let `a == +Z` and `basis == identity`, OR a tilted `a` with
        // a basis whose conjugation sends it to +Z. We use a tilted `a` + a derived
        // basis to exercise a genuinely non-trivial remap.
        let a = simd_normalize(SIMD3<Float>(0.4, 0.5, 0.768))
        let zAxis = SIMD3<Float>(0, 0, 1)
        // Basis that rotates `a` to +Z: rotation about (a × z) by the angle between them.
        let cross = simd_cross(a, zAxis)
        let dot = simd_dot(a, zAxis)
        let basis: simd_quatf
        if simd_length(cross) < 1e-6 {
            basis = identity // already aligned
        } else {
            let angle = acos(max(-1, min(1, dot)))
            basis = simd_quatf(angle: angle, axis: simd_normalize(cross))
        }

        let render = HeadOrientationRender(gain: 1, maxAngleRadians: 200 * .pi / 180, basis: basis)

        for thetaDeg in stride(from: Float(-50), through: 50, by: 5) {
            guard abs(thetaDeg) > 1 else { continue }
            let head = quat(angleDeg: thetaDeg, axis: a)
            let out = render.render(head: head, rest: identity)

            // The rendered axis is +Z (figure yaw), so pitch and roll are ~0.
            let outAxis = simd_normalize(out.axis)
            let aligned = outAxis.z < 0 ? -outAxis : outAxis
            XCTAssertEqual(simd_length(aligned - zAxis), 0, accuracy: 1e-3,
                           "rendered axis must be figure yaw +Z at θ=\(thetaDeg)")

            let e = euler(out)
            XCTAssertLessThan(abs(e.pitch), 1e-3, "pitch must stay 0 on a pure turn at θ=\(thetaDeg)")
            XCTAssertLessThan(abs(e.roll), 1e-3, "roll must stay 0 on a pure turn at θ=\(thetaDeg)")
        }
    }

    // MARK: - 2. gain = 1 is faithful

    func testGainOne_isFaithful() {
        let render = HeadOrientationRender(gain: 1, maxAngleRadians: 200 * .pi / 180)
        let inputs: [(Float, SIMD3<Float>)] = [
            (10, SIMD3(0, 0, 1)),
            (25, SIMD3(1, 0, 0)),
            (40, SIMD3(0.3, -0.6, 0.7)),
            (-30, SIMD3(0.1, 0.9, 0.2))
        ]
        for (deg, axis) in inputs {
            let head = quat(angleDeg: deg, axis: axis)
            let out = render.render(head: head, rest: identity)
            XCTAssertEqual(out.angle, abs(deg) * .pi / 180, accuracy: 1e-4,
                           "gain=1 output angle must equal input rest-relative angle (\(deg)°)")
        }
    }

    // MARK: - 3. gain scales angle (same axis)

    func testGainTwo_doublesAngle_sameAxis() {
        let axis = simd_normalize(SIMD3<Float>(0.2, 0.5, 0.84))
        let render = HeadOrientationRender(gain: 2, maxAngleRadians: 200 * .pi / 180)

        let inputDeg: Float = 20
        let head = quat(angleDeg: inputDeg, axis: axis)
        let out = render.render(head: head, rest: identity)

        XCTAssertEqual(out.angle, 2 * inputDeg * .pi / 180, accuracy: 1e-4,
                       "gain=2 must double the rendered angle away from the clamp")

        // Axis unchanged (identity basis → rendered axis == input axis).
        let outAxis = simd_normalize(out.axis)
        let aligned = simd_dot(outAxis, axis) < 0 ? -outAxis : outAxis
        XCTAssertEqual(simd_length(aligned - axis), 0, accuracy: 1e-3, "gain must not move the axis")
    }

    // MARK: - 4. clamp

    func testClamp_capsTotalAngle_axisUnchanged() {
        let axis = simd_normalize(SIMD3<Float>(0.6, 0.2, 0.77))
        let maxDeg: Float = 55
        let render = HeadOrientationRender(gain: 1, maxAngleRadians: maxDeg * .pi / 180)

        // Input well past the cap.
        let head = quat(angleDeg: 80, axis: axis)
        let out = render.render(head: head, rest: identity)

        XCTAssertEqual(out.angle, maxDeg * .pi / 180, accuracy: 1e-4,
                       "input past maxAngle must render at exactly maxAngle")

        let outAxis = simd_normalize(out.axis)
        let aligned = simd_dot(outAxis, axis) < 0 ? -outAxis : outAxis
        XCTAssertEqual(simd_length(aligned - axis), 0, accuracy: 1e-3, "clamp must preserve the axis")
    }

    // MARK: - 5. rest-relative

    func testRestRelative_headEqualsRest_rendersIdentity() {
        // A non-identity rest pose; head identical to it → identity render.
        let rest = quat(angleDeg: 33, axis: SIMD3(0.4, 0.5, 0.768))
        let render = HeadOrientationRender(gain: 1.5, maxAngleRadians: 60 * .pi / 180,
                                           basis: quat(angleDeg: 20, axis: SIMD3(1, 0, 0)))
        let out = render.render(head: rest, rest: rest)
        XCTAssertEqual(out.angle, 0, accuracy: 1e-5, "head == rest must render to identity (angle ≈ 0)")
    }

    // MARK: - 6. near-identity guard

    func testNearIdentityGuard_noNaN_returnsIdentity() {
        let render = HeadOrientationRender(gain: 3, maxAngleRadians: 60 * .pi / 180,
                                           basis: quat(angleDeg: 45, axis: SIMD3(0, 1, 0)))

        // Exactly identity input.
        let outZero = render.render(head: identity, rest: identity)
        XCTAssertFalse(outZero.angle.isNaN, "identity input must not NaN")
        XCTAssertEqual(outZero.angle, 0, accuracy: 1e-5, "identity input renders ~identity")

        // Sub-epsilon input (smaller than 1e-5 rad).
        let tiny = simd_quatf(angle: 1e-6, axis: SIMD3(0, 0, 1))
        let outTiny = render.render(head: tiny, rest: identity)
        XCTAssertFalse(outTiny.angle.isNaN, "sub-epsilon input must not NaN")
        XCTAssertEqual(outTiny.angle, 0, accuracy: 1e-5, "sub-epsilon input renders ~identity")
    }
}
