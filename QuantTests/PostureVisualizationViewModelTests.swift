import XCTest
import SwiftUI
import simd
import PostureLogic
@testable import Quant

/// Step 1 (plan.md) — TDD coverage for the framework-agnostic display ViewModel.
///
/// The design doc derives head yaw/pitch/roll from raw nose/ear/eye keypoints,
/// but those are NOT exposed on the public `AppModel`/`PoseSample` surface
/// (raw `Keypoint`/`Joint` are PostureLogic-internal — see progress.md Type
/// Map). These tests therefore pin the *substituted* geometry derivation:
/// roll ← left/right shoulder line angle, yaw ← `shoulderTwist`, pitch ←
/// `headForwardOffset`. The hard caps (±60° pitch, ±45° roll) and the α = 0.2
/// low-pass are the load-bearing assertions.
@MainActor
final class PostureVisualizationViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeSample(
        headForwardOffset: Float = 0,
        shoulderTwist: Float = 0,
        leftShoulderY: Float = -0.05,
        rightShoulderY: Float = 0.05,
        headX: Float = 0
    ) -> PoseSample {
        PoseSample(
            timestamp: 0,
            depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(headX, 0.8, 0),
            shoulderMidpoint: SIMD3<Float>(0, 0, 1),
            leftShoulder: SIMD3<Float>(-0.5, leftShoulderY, 0),
            rightShoulder: SIMD3<Float>(0.5, rightShoulderY, 0),
            torsoAngle: 0,
            headForwardOffset: headForwardOffset,
            shoulderTwist: shoulderTwist,
            shoulderWidthRaw: 0.4,
            trackingQuality: .good
        )
    }

    private func metrics(
        forwardCreep: Float = 0,
        lateralLean: Float = 0,
        twist: Float = 0
    ) -> RawMetrics {
        RawMetrics(
            timestamp: 0,
            forwardCreep: forwardCreep,
            headDrop: 0,
            shoulderRounding: 0,
            lateralLean: lateralLean,
            twist: twist,
            movementLevel: 0,
            headMovementPattern: .still
        )
    }

    // MARK: - Defaults

    func test_initialState_isNeutral() {
        let vm = PostureVisualizationViewModel()
        XCTAssertEqual(vm.shoulderRotationDegrees, 0)
        XCTAssertEqual(vm.sideLeanOffsetPoints, 0)
        XCTAssertEqual(vm.headForwardOffsetPoints, 0)
        XCTAssertEqual(vm.assemblyScale, 1, accuracy: 0.0001)
        XCTAssertEqual(vm.headYawDegrees, 0)
        XCTAssertEqual(vm.headPitchDegrees, 0)
        XCTAssertEqual(vm.headRollDegrees, 0)
        XCTAssertEqual(vm.opacity, 1, accuracy: 0.0001)
        XCTAssertFalse(vm.isCalibrating)
    }

    // MARK: - Metric-derived scaling (first ingest seeds the filter → exact)

    func test_twist_scalesToShoulderRotation_1_5x() {
        let vm = PostureVisualizationViewModel()
        vm.ingest(metrics: metrics(twist: 20), pose: makeSample(),
                  state: .good, quality: .good)
        XCTAssertEqual(vm.shoulderRotationDegrees, 30, accuracy: 0.0001) // 20 × 1.5
    }

    func test_lateralLean_scalesToSideLean_100ptPerUnit() {
        let vm = PostureVisualizationViewModel()
        vm.ingest(metrics: metrics(lateralLean: 0.4), pose: makeSample(),
                  state: .good, quality: .good)
        XCTAssertEqual(vm.sideLeanOffsetPoints, 40, accuracy: 0.0001) // 0.4 × 100
    }

    func test_forwardCreep_scalesToAssemblyScale_1PlusCreepHalf() {
        let vm = PostureVisualizationViewModel()
        vm.ingest(metrics: metrics(forwardCreep: 0.6), pose: makeSample(),
                  state: .good, quality: .good)
        XCTAssertEqual(vm.assemblyScale, 1.3, accuracy: 0.0001) // 1 + 0.6 × 0.5
    }

    func test_headForwardOffset_scalesToPoints_100ptPerUnit() {
        let vm = PostureVisualizationViewModel()
        vm.ingest(metrics: metrics(), pose: makeSample(headForwardOffset: -0.2),
                  state: .good, quality: .good)
        XCTAssertEqual(vm.headForwardOffsetPoints, -20, accuracy: 0.0001) // -0.2 × 100
    }

    // MARK: - Head yaw (← shoulderTwist, ×1.5, clamp ±90)

    func test_headYaw_fromShoulderTwist_amplified() {
        let vm = PostureVisualizationViewModel()
        vm.ingest(metrics: metrics(), pose: makeSample(shoulderTwist: 30),
                  state: .good, quality: .good)
        XCTAssertEqual(vm.headYawDegrees, 45, accuracy: 0.0001) // 30 × 1.5
    }

    func test_headYaw_clampedTo90() {
        let vm = PostureVisualizationViewModel()
        vm.ingest(metrics: metrics(), pose: makeSample(shoulderTwist: 80),
                  state: .good, quality: .good)
        XCTAssertEqual(vm.headYawDegrees, 90, accuracy: 0.0001) // 80 × 1.5 → clamp
        vm.ingest(metrics: metrics(), pose: makeSample(shoulderTwist: -80),
                  state: .good, quality: .good)
        XCTAssertGreaterThanOrEqual(vm.headYawDegrees, -90)
    }

    // MARK: - Head pitch (← headForwardOffset, cap ±60°)

    func test_headPitch_withinRange() {
        let vm = PostureVisualizationViewModel()
        // atan2(0.05, 0.15) ≈ 18.43° × 1.5 ≈ 27.65°
        vm.ingest(metrics: metrics(), pose: makeSample(headForwardOffset: -0.05),
                  state: .good, quality: .good)
        let expected = atan2(0.05, 0.15) * 180 / .pi * 1.5
        XCTAssertEqual(vm.headPitchDegrees, expected, accuracy: 0.01)
        XCTAssertGreaterThan(vm.headPitchDegrees, 0) // leaning toward camera = +pitch
    }

    func test_headPitch_cappedAt60() {
        let vm = PostureVisualizationViewModel()
        vm.ingest(metrics: metrics(), pose: makeSample(headForwardOffset: -100),
                  state: .good, quality: .good)
        XCTAssertEqual(vm.headPitchDegrees, 60, accuracy: 0.0001)

        let vm2 = PostureVisualizationViewModel()
        vm2.ingest(metrics: metrics(), pose: makeSample(headForwardOffset: 100),
                   state: .good, quality: .good)
        XCTAssertEqual(vm2.headPitchDegrees, -60, accuracy: 0.0001)
    }

    // MARK: - Head roll (← left/right shoulder line angle, cap ±45°)

    func test_headRoll_fromShoulderLineAngle() {
        let vm = PostureVisualizationViewModel()
        // Δy = 0.1 - (-0.1) = 0.2, Δx = 0.5 - (-0.5) = 1.0
        vm.ingest(metrics: metrics(),
                  pose: makeSample(leftShoulderY: -0.1, rightShoulderY: 0.1),
                  state: .good, quality: .good)
        let expected = atan2(0.2, 1.0) * 180 / .pi * 1.5
        XCTAssertEqual(vm.headRollDegrees, expected, accuracy: 0.01)
    }

    func test_headRoll_cappedAt45() {
        let vm = PostureVisualizationViewModel()
        vm.ingest(metrics: metrics(),
                  pose: makeSample(leftShoulderY: -100, rightShoulderY: 100),
                  state: .good, quality: .good)
        XCTAssertEqual(vm.headRollDegrees, 45, accuracy: 0.0001)

        let vm2 = PostureVisualizationViewModel()
        vm2.ingest(metrics: metrics(),
                   pose: makeSample(leftShoulderY: 100, rightShoulderY: -100),
                   state: .good, quality: .good)
        XCTAssertEqual(vm2.headRollDegrees, -45, accuracy: 0.0001)
    }

    // MARK: - State → colour (4 states must be visibly distinct)

    func test_stateColor_discreteMapping() {
        let vm = PostureVisualizationViewModel()

        vm.ingest(metrics: metrics(), pose: makeSample(), state: .calibrating, quality: .good)
        let calibrating = vm.stateColor
        vm.ingest(metrics: metrics(), pose: makeSample(), state: .good, quality: .good)
        let good = vm.stateColor
        vm.ingest(metrics: metrics(), pose: makeSample(), state: .drifting(since: 0), quality: .good)
        let drifting = vm.stateColor
        vm.ingest(metrics: metrics(), pose: makeSample(), state: .bad(since: 0), quality: .good)
        let bad = vm.stateColor

        XCTAssertEqual(good, .green)
        XCTAssertEqual(drifting, .orange)
        XCTAssertEqual(bad, .red)

        // All four must be pairwise distinct.
        let distinct = Set([calibrating, good, drifting, bad].map(rgba))
        XCTAssertEqual(distinct.count, 4, "All four state colours must be visibly distinct")
    }

    func test_isCalibrating_trueOnlyForCalibratingState() {
        let vm = PostureVisualizationViewModel()

        vm.ingest(metrics: metrics(), pose: makeSample(), state: .calibrating, quality: .good)
        XCTAssertTrue(vm.isCalibrating)
        vm.ingest(metrics: metrics(), pose: makeSample(), state: .good, quality: .good)
        XCTAssertFalse(vm.isCalibrating)
        vm.ingest(metrics: metrics(), pose: makeSample(), state: .bad(since: 0), quality: .good)
        XCTAssertFalse(vm.isCalibrating)
        vm.ingest(metrics: metrics(), pose: makeSample(), state: .absent, quality: .good)
        XCTAssertFalse(vm.isCalibrating)
    }

    // MARK: - Tracking quality → opacity (monotonic, first ingest seeds)

    func test_trackingQuality_mapsToOpacity_monotonic() {
        let lost = PostureVisualizationViewModel()
        lost.ingest(metrics: metrics(), pose: makeSample(), state: .good, quality: .lost)

        let degraded = PostureVisualizationViewModel()
        degraded.ingest(metrics: metrics(), pose: makeSample(), state: .good, quality: .degraded)

        let good = PostureVisualizationViewModel()
        good.ingest(metrics: metrics(), pose: makeSample(), state: .good, quality: .good)

        XCTAssertEqual(good.opacity, 1.0, accuracy: 0.0001)
        XCTAssertLessThan(degraded.opacity, good.opacity)
        XCTAssertLessThan(lost.opacity, degraded.opacity)
        XCTAssertGreaterThanOrEqual(lost.opacity, 0)
    }

    // MARK: - Low-pass filter (α = 0.2 exponential approach)

    func test_lowPassFilter_alpha02_exponentialApproach() {
        var f = LowPassFilter()
        XCTAssertEqual(f.update(0), 0, accuracy: 1e-9)      // first sample seeds
        XCTAssertEqual(f.update(10), 2.0, accuracy: 1e-9)   // 0 + 0.2·(10−0)
        XCTAssertEqual(f.update(10), 3.6, accuracy: 1e-9)   // 2 + 0.2·(10−2)
        XCTAssertEqual(f.update(10), 4.88, accuracy: 1e-9)  // 3.6 + 0.2·(10−3.6)
        for _ in 0..<200 { _ = f.update(10) }
        XCTAssertEqual(f.update(10), 10, accuracy: 1e-3)    // converges to target
    }

    func test_smoothing_appliedToContinuousChannel() {
        let vm = PostureVisualizationViewModel()
        // Seed at 0, then step the twist input to a constant target.
        vm.ingest(metrics: metrics(twist: 0), pose: makeSample(), state: .good, quality: .good)
        XCTAssertEqual(vm.shoulderRotationDegrees, 0, accuracy: 1e-9)

        let target = 20.0 * PostureVisualizationViewModel.Mapping.twistAmplification
        vm.ingest(metrics: metrics(twist: 20), pose: makeSample(), state: .good, quality: .good)
        XCTAssertEqual(vm.shoulderRotationDegrees, 0.2 * target, accuracy: 1e-6)
        vm.ingest(metrics: metrics(twist: 20), pose: makeSample(), state: .good, quality: .good)
        XCTAssertEqual(vm.shoulderRotationDegrees, 0.36 * target, accuracy: 1e-6)

        for _ in 0..<200 {
            vm.ingest(metrics: metrics(twist: 20), pose: makeSample(), state: .good, quality: .good)
        }
        XCTAssertEqual(vm.shoulderRotationDegrees, target, accuracy: 1e-3)
    }

    func test_alphaConstant_is02() {
        XCTAssertEqual(PostureVisualizationViewModel.smoothingAlpha, 0.2, accuracy: 1e-12)
    }

    // MARK: - Helpers

    /// Repo convention (PostureVisualStyleTests) compares colours via UIColor
    /// component extraction rather than relying on Color identity.
    private func rgba(_ color: Color) -> [Int] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return [Int((r * 255).rounded()), Int((g * 255).rounded()),
                Int((b * 255).rounded()), Int((a * 255).rounded())]
    }
}
