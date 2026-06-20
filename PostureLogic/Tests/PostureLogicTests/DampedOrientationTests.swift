import XCTest
import simd
@testable import PostureLogic

/// Headless proof for ``DampedOrientation`` — the quaternion follower. This is the layer
/// the render binding relies on for a fluid head, and the layer where the explicitly
/// *rejected* "snap to every fresh sample" failure mode would live, so it is covered
/// directly here rather than only via its scalar component.
final class DampedOrientationTests: XCTestCase {

    private let dt60: Float = 1.0 / 60.0
    private let smoothTime: Float = 0.09

    private func yaw(_ degrees: Float) -> simd_quatf {
        simd_quatf(angle: degrees * .pi / 180, axis: SIMD3<Float>(0, 0, 1))
    }

    /// Unsigned geodesic angle (radians) between two rotations.
    private func angle(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        let d = min(1, abs(simd_dot(a.vector, b.vector)))
        return 2 * acos(d)
    }

    // MARK: - Seeding

    func test_firstUpdate_seedsAndSnapsToTarget() {
        var damp = DampedOrientation()
        let target = yaw(25)
        let out = damp.update(toward: target, smoothTime: smoothTime, dt: dt60)
        // Unseeded ⇒ snap, so the rig appears at the live pose instead of swinging in
        // from identity on the first frame.
        XCTAssertLessThan(angle(out, target), 0.001, "first update must snap to the target")
    }

    func test_nonPositiveSmoothTime_snaps() {
        var damp = DampedOrientation()
        _ = damp.update(toward: yaw(0), smoothTime: smoothTime, dt: dt60)   // seed
        let target = yaw(30)
        let out = damp.update(toward: target, smoothTime: 0, dt: dt60)
        XCTAssertLessThan(angle(out, target), 0.001, "smoothTime <= 0 ⇒ snap (smoothing off)")
    }

    // MARK: - Shortest-path sign flip (the quaternion double cover)

    func test_shortestPath_negatedTargetDoesNotTravelTheLongWay() {
        // q and -q are the SAME rotation. After settling at q, feeding -q must keep the
        // follower put — NOT send it the long way around through identity toward -q.
        // Without the `simd_dot(cur, t) < 0 ? -t` flip this drifts ~all the way around.
        var damp = DampedOrientation()
        let q = yaw(40)
        _ = damp.update(toward: q, smoothTime: smoothTime, dt: dt60)   // seed at q (snap)

        let negated = simd_quatf(vector: -q.vector)                     // identical rotation, opposite sign
        for _ in 0..<20 {
            damp.update(toward: negated, smoothTime: smoothTime, dt: dt60)
        }
        XCTAssertLessThan(angle(damp.current, q), 0.01,
                          "feeding the negated-but-equal quaternion must not move the rendered rotation")
    }

    // MARK: - Convergence / no overshoot on the combined quaternion

    func test_constantCombinedTarget_convergesWithoutVisibleOvershoot() {
        // A blended yaw+pitch target (a head turned and nodded at once). The follower must
        // close on it without overshoot or ringing, and actually arrive.
        //
        // Tolerance note: each quaternion component is monotone/no-overshoot, but the
        // renormalized GEODESIC angle is not perfectly monotone — near convergence the
        // four components' overshoot guards clamp on slightly different frames, so the
        // re-normalized direction wobbles by a sub-visual ~0.04° (~7e-4 rad) for a frame
        // or two (a known, accepted trade of component-wise vs. exact-geodesic smoothing).
        // The tolerance admits that blip while still catching any real (degree-scale)
        // overshoot or ringing.
        let blipTolerance: Float = 2e-3   // ~0.11°, comfortably above the ~0.04° artifact
        var damp = DampedOrientation()
        _ = damp.update(toward: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1)),
                        smoothTime: smoothTime, dt: dt60)   // seed at identity
        let yawQ = simd_quatf(angle: 20 * .pi / 180, axis: SIMD3<Float>(0, 0, 1))
        let pitchQ = simd_quatf(angle: 15 * .pi / 180, axis: SIMD3<Float>(1, 0, 0))
        let target = yawQ * pitchQ

        var prevErr = angle(damp.current, target)
        for _ in 0..<120 {
            damp.update(toward: target, smoothTime: smoothTime, dt: dt60)
            let err = angle(damp.current, target)
            XCTAssertLessThanOrEqual(err, prevErr + blipTolerance, "must not visibly overshoot the combined target")
            prevErr = err
        }
        XCTAssertLessThan(prevErr, 0.005, "must converge to the combined target")
    }

    // MARK: - No pulse at the quaternion level (the staircase the source actually makes)

    /// The 10 Hz-sampled head pose is a *staircase* to the 60 Hz renderer. Feed that
    /// staircase as quaternions and assert the per-frame angular displacement RAMPS after
    /// each step (smallest on the step frame, growing for a few frames) — the no-pulse
    /// signature. A first-order EMA, or the rejected "snap to each fresh sample" scheme,
    /// makes its LARGEST move on the step frame instead. This is the quaternion analogue
    /// of the scalar no-pulse test, on the layer where the rejected bug would live.
    func test_noPulse_quaternionStaircase_displacementRampsAfterEachStep() {
        var damp = DampedOrientation()

        func feed(toward target: simd_quatf, frames: Int) -> [Float] {
            var deltas: [Float] = []
            for _ in 0..<frames {
                let before = damp.current
                damp.update(toward: target, smoothTime: smoothTime, dt: dt60)
                deltas.append(angle(before, damp.current))
            }
            return deltas
        }

        _ = feed(toward: yaw(0), frames: 1)         // seed at 0 (snap)
        let step1 = feed(toward: yaw(15), frames: 10)   // first riser
        let step2 = feed(toward: yaw(30), frames: 10)   // second riser (post prior settle)

        for (label, seg, riseDeg) in [("step1", step1, Float(15)), ("step2", step2, Float(15))] {
            XCTAssertLessThan(seg[0], seg[2], "\(label): displacement must ramp after the step (no spike on it)")
            XCTAssertLessThan(seg[0], seg[3], "\(label): still ramping a few frames in")
            let riseRad = riseDeg * .pi / 180
            XCTAssertLessThan(seg.max() ?? .greatestFiniteMagnitude, riseRad * 0.6,
                              "\(label): no single frame may swallow most of the step")
        }
    }
}
