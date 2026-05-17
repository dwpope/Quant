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
}
