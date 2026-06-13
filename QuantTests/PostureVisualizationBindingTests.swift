import XCTest
import SwiftUI
import simd
import PostureLogic
@testable import Quant

/// Step 4 (plan.md) — proves `PostureVisualizationBinding.resolve` maps the
/// ViewModel's display scalars onto the correct scene-space transforms.
///
/// RealityKit rendering can't be asserted headlessly (that's the manual Step
/// 7 visual check), so the binding is split: a pure `resolve` (tested here)
/// and a thin entity-poking `apply` (untested — it only forwards `resolve`'s
/// output into Apple's setters). These tests pin the load-bearing conversions:
/// degrees→radians, points→metres, Euler axis assignment, and the end-to-end
/// chain from a `RawMetrics`/`PoseSample` ingest through to resolved transforms.
@MainActor
final class PostureVisualizationBindingTests: XCTestCase {

    private typealias Binding = PostureVisualizationBinding
    private let deg2rad = Float.pi / 180

    // MARK: - Pure resolve: scalar → transform conversions

    func test_discRotation_degreesToRadians() {
        let t = Binding.resolve(
            shoulderRotationDegrees: 30,
            sideLeanOffsetPoints: 0, headForwardOffsetPoints: 0,
            assemblyScale: 1,
            headYawDegrees: 0, headPitchDegrees: 0, headRollDegrees: 0,
            opacity: 1
        )
        XCTAssertEqual(t.discYawRadians, 30 * deg2rad, accuracy: 1e-6)
    }

    func test_headTranslation_pointsToMetres_andRestYPreserved() {
        let t = Binding.resolve(
            shoulderRotationDegrees: 0,
            sideLeanOffsetPoints: 100,        // → x
            headForwardOffsetPoints: -50,     // → z
            assemblyScale: 1,
            headYawDegrees: 0, headPitchDegrees: 0, headRollDegrees: 0,
            opacity: 1
        )
        XCTAssertEqual(t.headTranslation.x, 100 * Binding.metersPerPoint, accuracy: 1e-7)
        XCTAssertEqual(t.headTranslation.z, -50 * Binding.metersPerPoint, accuracy: 1e-7)
        // Y is the scaffold's rest height — never the lean/forward signal.
        XCTAssertEqual(t.headTranslation.y,
                       PostureVisualizationScene.Layout.headCenterY, accuracy: 1e-7)
    }

    func test_headEuler_axisAssignment_pitchX_yawY_rollZ() {
        let t = Binding.resolve(
            shoulderRotationDegrees: 0,
            sideLeanOffsetPoints: 0, headForwardOffsetPoints: 0,
            assemblyScale: 1,
            headYawDegrees: -90, headPitchDegrees: 60, headRollDegrees: 45,
            opacity: 1
        )
        XCTAssertEqual(t.headEulerRadians.x, 60 * deg2rad, accuracy: 1e-6)   // pitch
        XCTAssertEqual(t.headEulerRadians.y, -90 * deg2rad, accuracy: 1e-6)  // yaw
        XCTAssertEqual(t.headEulerRadians.z, 45 * deg2rad, accuracy: 1e-6)   // roll
    }

    func test_scaleAndOpacity_passThroughAsFloat() {
        let t = Binding.resolve(
            shoulderRotationDegrees: 0,
            sideLeanOffsetPoints: 0, headForwardOffsetPoints: 0,
            assemblyScale: 1.2,
            headYawDegrees: 0, headPitchDegrees: 0, headRollDegrees: 0,
            opacity: 0.6
        )
        XCTAssertEqual(t.assemblyScale, 1.2, accuracy: 1e-6)
        XCTAssertEqual(t.opacity, 0.6, accuracy: 1e-6)
    }

    // MARK: - headOrientation quaternion

    func test_headOrientation_zeroEuler_isIdentity() {
        let q = Binding.headOrientation(.zero)
        XCTAssertEqual(q.angle, 0, accuracy: 1e-6)
    }

    func test_headOrientation_pureYaw90_rotatesForwardToRight() {
        // +90° about Y maps local +Z (the "nose" axis) to +X.
        let q = Binding.headOrientation(SIMD3<Float>(0, .pi / 2, 0))
        let rotated = q.act(SIMD3<Float>(0, 0, 1))
        XCTAssertEqual(rotated.x, 1, accuracy: 1e-5)
        XCTAssertEqual(rotated.y, 0, accuracy: 1e-5)
        XCTAssertEqual(rotated.z, 0, accuracy: 1e-5)
    }

    // MARK: - End-to-end: RawMetrics/PoseSample → ViewModel → resolved transforms

    func test_resolveFromViewModel_endToEnd() {
        let vm = PostureVisualizationViewModel()
        // First ingest seeds the low-pass filters directly (no ramp), so the
        // published values equal their targets exactly — deterministic chain.
        vm.ingest(
            metrics: RawMetrics(
                timestamp: 0,
                forwardCreep: 0.4,      // → assemblyScale 1 + 0.4·0.5 = 1.2
                headDrop: 0, shoulderRounding: 0,
                lateralLean: 0.5,       // → sideLean 0.5·100 = 50 pt
                twist: 0.2,             // → shoulderRotation 0.2·1.5 = 0.3°
                movementLevel: 0,
                headMovementPattern: .still
            ),
            pose: PoseSample(
                timestamp: 0,
                depthMode: .twoDOnly,
                headPosition: .zero,
                shoulderMidpoint: .zero,
                leftShoulder: .zero,
                rightShoulder: SIMD3<Float>(1, 0, 0),
                torsoAngle: 0,
                headForwardOffset: -0.1,  // → forward -0.1·100 = -10 pt
                shoulderTwist: 0,
                shoulderWidthRaw: 0.3,
                trackingQuality: .degraded
            ),
            state: .good,
            quality: .degraded
        )

        let t = Binding.resolve(from: vm)

        // Binding-owned conversions, end to end with concrete numbers.
        XCTAssertEqual(t.discYawRadians, 0.3 * deg2rad, accuracy: 1e-5)
        XCTAssertEqual(t.headTranslation.x, 50 * Binding.metersPerPoint, accuracy: 1e-6)
        XCTAssertEqual(t.headTranslation.z, -10 * Binding.metersPerPoint, accuracy: 1e-6)
        XCTAssertEqual(t.assemblyScale, 1.2, accuracy: 1e-5)
        XCTAssertEqual(t.opacity, Float(vm.opacity), accuracy: 1e-6)
        // Rotation channels forward the VM's degrees faithfully (the heuristic
        // itself is Step 1's tested concern, not the binding's).
        XCTAssertEqual(t.headEulerRadians.x, Float(vm.headPitchDegrees) * deg2rad, accuracy: 1e-6)
        XCTAssertEqual(t.headEulerRadians.y, Float(vm.headYawDegrees) * deg2rad, accuracy: 1e-6)
        XCTAssertEqual(t.headEulerRadians.z, Float(vm.headRollDegrees) * deg2rad, accuracy: 1e-6)
    }

    // MARK: - Mirror (horizontal-sense flip only)

    private func makeTransforms() -> Binding.ResolvedPostureTransforms {
        Binding.ResolvedPostureTransforms(
            discYawRadians: 0.3,
            headTranslation: SIMD3<Float>(0.04, 0.15, -0.02),
            headEulerRadians: SIMD3<Float>(0.5, -0.7, 0.2),
            assemblyScale: 1.2,
            opacity: 0.6
        )
    }

    func test_mirror_flipsOnlyHorizontalSenseChannels() {
        let t = makeTransforms()
        let m = Binding.mirror(t)

        // Flipped: disc twist, head X, head yaw, head roll.
        XCTAssertEqual(m.discYawRadians, -t.discYawRadians)
        XCTAssertEqual(m.headTranslation.x, -t.headTranslation.x)
        XCTAssertEqual(m.headEulerRadians.y, -t.headEulerRadians.y)
        XCTAssertEqual(m.headEulerRadians.z, -t.headEulerRadians.z)

        // Untouched: rest height, depth, pitch, scale, opacity.
        XCTAssertEqual(m.headTranslation.y, t.headTranslation.y)
        XCTAssertEqual(m.headTranslation.z, t.headTranslation.z)
        XCTAssertEqual(m.headEulerRadians.x, t.headEulerRadians.x)
        XCTAssertEqual(m.assemblyScale, t.assemblyScale)
        XCTAssertEqual(m.opacity, t.opacity)
    }

    func test_mirror_isInvolution() {
        let t = makeTransforms()
        XCTAssertEqual(Binding.mirror(Binding.mirror(t)), t,
                       "mirroring twice must restore the original transforms")
    }

    // MARK: - DebugChannels defaults ARE the production behaviour

    /// The `DebugChannels` contract: an untouched `debug` reproduces the
    /// shipped behaviour exactly. Every channel live, nothing hidden, and the
    /// front-camera mirror on. If a tuning session changes a default (or a
    /// leftover tuning override is committed), this test fails the build.
    func test_debugChannels_defaultsMatchProduction() {
        let d = Binding.DebugChannels()
        XCTAssertTrue(d.shoulderRotation)
        XCTAssertFalse(d.hideShoulderDisc)
        XCTAssertFalse(d.hideGhost)
        XCTAssertFalse(d.hideHeadBand)
        XCTAssertTrue(d.sideLean)
        XCTAssertTrue(d.headForward)
        XCTAssertTrue(d.headYaw)
        XCTAssertTrue(d.headPitch)
        XCTAssertTrue(d.headRoll)
        XCTAssertTrue(d.assemblyScale)
        XCTAssertTrue(d.opacity)
        XCTAssertTrue(d.stateTint)
        XCTAssertTrue(d.mirrored, "mirror reading is the production default for a front camera")
    }

    // MARK: - Step 5: state tint + calibrating pulse

    /// Plan Step 5 done-criterion: "four states visibly distinct in code
    /// (colour values asserted in a small test)". The three judged states pass
    /// the VM hue straight through; calibrating contributes a neutral grey.
    func test_stateTint_fourStates_arePairwiseDistinct() {
        let good        = Binding.stateTint(stateColor: .green,  isCalibrating: false, pulse: 0)
        let drifting    = Binding.stateTint(stateColor: .orange, isCalibrating: false, pulse: 0)
        let bad         = Binding.stateTint(stateColor: .red,    isCalibrating: false, pulse: 0)
        let calibrating = Binding.stateTint(stateColor: .gray,   isCalibrating: true,  pulse: 0.5)

        XCTAssertEqual(good, .green)
        XCTAssertEqual(bad, .red)

        let distinct = Set([good, drifting, bad, calibrating].map(rgba))
        XCTAssertEqual(distinct.count, 4,
                       "All four visualization states must be visibly distinct")
    }

    /// Calibrating "breathes": brighter pulse → strictly higher luminance on
    /// every channel, and the result stays achromatic (R≈G≈B) so only
    /// brightness changes, never hue.
    func test_stateTint_calibratingPulse_modulatesBrightnessNotHue() {
        let dim    = rgba(Binding.stateTint(stateColor: .gray, isCalibrating: true, pulse: 0))
        let bright = rgba(Binding.stateTint(stateColor: .gray, isCalibrating: true, pulse: 1))

        XCTAssertGreaterThan(bright[0], dim[0])
        XCTAssertGreaterThan(bright[1], dim[1])
        XCTAssertGreaterThan(bright[2], dim[2])

        XCTAssertEqual(dim[0], dim[1]);       XCTAssertEqual(dim[1], dim[2])
        XCTAssertEqual(bright[0], bright[1]); XCTAssertEqual(bright[1], bright[2])
    }

    /// The pulse phase must not bleed into the judged (non-calibrating) states.
    func test_stateTint_nonCalibrating_ignoresPulse() {
        XCTAssertEqual(
            rgba(Binding.stateTint(stateColor: .green, isCalibrating: false, pulse: 0)),
            rgba(Binding.stateTint(stateColor: .green, isCalibrating: false, pulse: 1))
        )
    }

    // MARK: - Helpers

    /// Repo convention (PostureVisualizationViewModelTests / PostureVisualStyle
    /// Tests): compare colours via UIColor component extraction, not `Color`
    /// identity.
    private func rgba(_ color: Color) -> [Int] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return [Int((r * 255).rounded()), Int((g * 255).rounded()),
                Int((b * 255).rounded()), Int((a * 255).rounded())]
    }
}
