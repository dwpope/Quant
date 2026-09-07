import XCTest
import SwiftUI
import simd
import PostureLogic
@testable import Quant

/// TDD coverage for the framework-agnostic display ViewModel.
///
/// As of plan Step 4 the head angles come from the **real head geometry** now
/// exposed on `PoseSample` — yaw ← `headYaw`, pitch ← `headPitch`, roll ←
/// `headRoll` (degrees, computed in `PoseDepthFusion.computeHeadAngles`). These
/// tests pin that source (a pure shoulder twist no longer moves head yaw), the
/// ×1.5 amplification, the hard caps (±90° yaw, ±60° pitch, ±45° roll), the
/// calibration-relative rest-zeroing of pitch/roll, and the α = 0.2 low-pass.
@MainActor
final class PostureVisualizationViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeSample(
        headForwardOffset: Float = 0,
        shoulderTwist: Float = 0,
        leftShoulderY: Float = -0.05,
        rightShoulderY: Float = 0.05,
        headX: Float = 0,
        headPitch: Float = 0,
        headYaw: Float = 0,
        headRoll: Float = 0,
        timestamp: TimeInterval = 0
    ) -> PoseSample {
        PoseSample(
            timestamp: timestamp,
            depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(headX, 0.8, 0),
            shoulderMidpoint: SIMD3<Float>(0, 0, 1),
            leftShoulder: SIMD3<Float>(-0.5, leftShoulderY, 0),
            rightShoulder: SIMD3<Float>(0.5, rightShoulderY, 0),
            torsoAngle: 0,
            headForwardOffset: headForwardOffset,
            shoulderTwist: shoulderTwist,
            shoulderWidthRaw: 0.4,
            trackingQuality: .good,
            headPitch: headPitch,
            headYaw: headYaw,
            headRoll: headRoll
        )
    }

    private func metrics(
        forwardCreep: Float = 0,
        lateralLean: Float = 0,
        twist: Float = 0,
        lateralLeanSigned: Float? = nil,
        twistSigned: Float? = nil
    ) -> RawMetrics {
        // The ViewModel maps the *signed* channels (`twistSigned`/`lateralLeanSigned`)
        // to the disc rotation and side-lean — the unsigned `twist`/`lateralLean` are
        // scoring magnitudes only. So the fixture must populate the signed fields, or
        // the rotation/lean assertions read 0 (the `RawMetrics` init defaults them to
        // 0). Default each signed value to its magnitude; callers may override to test
        // a specific direction.
        RawMetrics(
            timestamp: 0,
            forwardCreep: forwardCreep,
            headDrop: 0,
            shoulderRounding: 0,
            lateralLean: lateralLean,
            twist: twist,
            movementLevel: 0,
            headMovementPattern: .still,
            lateralLeanSigned: lateralLeanSigned ?? lateralLean,
            twistSigned: twistSigned ?? twist
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

    // MARK: - Head yaw (← PoseSample.headYaw, ×1.5, clamp ±90)
    // The amplify case lives in test_headYaw_drivenByRealHeadTurn below; this
    // section now only pins the cap.

    func test_headYaw_clampedTo90() {
        let vm = PostureVisualizationViewModel()
        vm.ingest(metrics: metrics(), pose: makeSample(headYaw: 80),
                  state: .good, quality: .good)
        XCTAssertEqual(vm.headYawDegrees, 90, accuracy: 0.0001) // 80 × 1.5 → clamp
        vm.ingest(metrics: metrics(), pose: makeSample(headYaw: -80),
                  state: .good, quality: .good)
        XCTAssertGreaterThanOrEqual(vm.headYawDegrees, -90)
    }

    // MARK: - Head yaw decoupled from shoulders (Step 4: real head geometry)
    //
    // The point of this sub-stage: head yaw must come from the HEAD
    // (`PoseSample.headYaw`), not the shoulder-twist proxy. A pure shoulder twist
    // with a forward-facing head must read ~0° head yaw — the proxy's central bug
    // (a shoulder shrug currently reads as head movement). An actual head turn,
    // shoulders square, must drive yaw.

    func test_headYaw_isZeroForPureShoulderTwist() {
        let vm = PostureVisualizationViewModel()
        // Shoulders rotated hard, but the head faces forward (headYaw = 0).
        vm.ingest(metrics: metrics(twist: 40),
                  pose: makeSample(shoulderTwist: 40, headYaw: 0),
                  state: .good, quality: .good)
        XCTAssertEqual(vm.headYawDegrees, 0, accuracy: 0.01,
                       "a pure shoulder twist with a forward-facing head must not move head yaw")
    }

    func test_headYaw_drivenByRealHeadTurn() {
        let vm = PostureVisualizationViewModel()
        // Head turned, shoulders square → yaw tracks PoseSample.headYaw (×1.5).
        vm.ingest(metrics: metrics(twist: 0),
                  pose: makeSample(shoulderTwist: 0, headYaw: 30),
                  state: .good, quality: .good)
        XCTAssertEqual(vm.headYawDegrees, 45, accuracy: 0.01,
                       "head yaw must track PoseSample.headYaw, amplified ×1.5")
    }

    // MARK: - Head pitch (← PoseSample.headPitch, ×1.5, cap ±60°)

    func test_headPitch_fromHeadPitch_amplified() {
        let vm = PostureVisualizationViewModel()
        // No `.calibrating` frame → absolute behaviour: headPitch × 1.5.
        vm.ingest(metrics: metrics(), pose: makeSample(headPitch: 18),
                  state: .good, quality: .good)
        XCTAssertEqual(vm.headPitchDegrees, 18 * 1.5, accuracy: 0.01)
        XCTAssertGreaterThan(vm.headPitchDegrees, 0) // chin-down / forward head = +pitch
    }

    func test_headPitch_cappedAt60() {
        let vm = PostureVisualizationViewModel()
        vm.ingest(metrics: metrics(), pose: makeSample(headPitch: 100),
                  state: .good, quality: .good)
        XCTAssertEqual(vm.headPitchDegrees, 60, accuracy: 0.0001) // 100 × 1.5 → clamp

        let vm2 = PostureVisualizationViewModel()
        vm2.ingest(metrics: metrics(), pose: makeSample(headPitch: -100),
                   state: .good, quality: .good)
        XCTAssertEqual(vm2.headPitchDegrees, -60, accuracy: 0.0001)
    }

    func test_headPitch_jitterDenoised_withAdvancingTimestamps() {
        // The other head tests stamp every frame `timestamp: 0`, where the One Euro
        // source filter is the identity (no rate to measure) — which is exactly why
        // those exact-value assertions still hold. This one proves the *production*
        // path: with real advancing timestamps the filter engages, so a still head
        // with sensor jitter renders far steadier than the raw ±swing × gain.
        HeadAngleFilterTuning.minCutoff = HeadAngleFilterTuning.minCutoffDefault
        HeadAngleFilterTuning.beta = HeadAngleFilterTuning.betaDefault
        defer {   // leave the shared static as found for any later test
            HeadAngleFilterTuning.minCutoff = HeadAngleFilterTuning.minCutoffDefault
            HeadAngleFilterTuning.beta = HeadAngleFilterTuning.betaDefault
        }

        let vm = PostureVisualizationViewModel()
        var t: TimeInterval = 0
        var outs: [Double] = []
        for i in 0..<80 {
            t += 0.1   // ~10 Hz pose cadence ⇒ dt > 0 ⇒ filter active
            let jittered: Float = 10 + (i.isMultiple(of: 2) ? 2 : -2)   // ±2° sensor jitter
            vm.ingest(metrics: metrics(),
                      pose: makeSample(headPitch: jittered, timestamp: t),
                      state: .good, quality: .good)
            outs.append(vm.headPitchDegrees)
        }
        // Raw, the ±2° jitter × 1.5 gain would render a 6° peak-to-peak shimmer.
        let tail = Array(outs.suffix(40))
        let swing = (tail.max() ?? 0) - (tail.min() ?? 0)
        XCTAssertLessThan(swing, 3.0,
                          "advancing timestamps must engage the One Euro denoise (well under the 6° raw swing)")
    }

    func test_headPitch_trackingLossThenResume_tracksFreshValue_noStaleDrag() {
        // The One Euro filters are deliberately NOT reset on tracking loss. When pose
        // goes nil the head eases to neutral and the filters simply aren't updated;
        // on resume the dt-aware filter sees a large dt and converges decisively to the
        // FRESH value rather than dragging toward the stale pre-loss angle. This locks
        // the adversarial review's "reset on discontinuity" concern as a non-issue — a
        // hard reset would instead expose one raw, unsmoothed frame on every brief drop.
        HeadAngleFilterTuning.minCutoff = HeadAngleFilterTuning.minCutoffDefault
        HeadAngleFilterTuning.beta = HeadAngleFilterTuning.betaDefault
        defer {
            HeadAngleFilterTuning.minCutoff = HeadAngleFilterTuning.minCutoffDefault
            HeadAngleFilterTuning.beta = HeadAngleFilterTuning.betaDefault
        }

        let vm = PostureVisualizationViewModel()
        var t: TimeInterval = 0
        for _ in 0..<30 {   // settle on a held pose at pitch 10
            t += 0.1
            vm.ingest(metrics: metrics(), pose: makeSample(headPitch: 10, timestamp: t),
                      state: .good, quality: .good)
        }
        XCTAssertEqual(vm.headPitchDegrees, 10 * 1.5, accuracy: 1.0, "should track the held pose")

        for _ in 0..<6 {    // lose tracking ~0.6 s (pose nil; clock keeps advancing)
            t += 0.1
            vm.ingest(metrics: metrics(), pose: nil, state: .good, quality: .degraded)
        }
        XCTAssertEqual(vm.headPitchDegrees, 0, accuracy: 0.0001, "no pose ⇒ head eases to neutral")

        t += 0.1            // resume at a genuinely different pose
        vm.ingest(metrics: metrics(), pose: makeSample(headPitch: 30, timestamp: t),
                  state: .good, quality: .good)
        // Fresh target is 30×1.5=45, stale would be 10×1.5=15; must land decisively on fresh.
        XCTAssertGreaterThan(vm.headPitchDegrees, 30,
                             "resume must snap toward the fresh pose (45), not the stale (15)")
        XCTAssertLessThanOrEqual(vm.headPitchDegrees, 45 + 0.01, "never overshoots the fresh target")
    }

    // MARK: - Head roll (← PoseSample.headRoll, ×1.5, cap ±45°)

    func test_headRoll_fromHeadRoll_amplified() {
        let vm = PostureVisualizationViewModel()
        vm.ingest(metrics: metrics(), pose: makeSample(headRoll: 20),
                  state: .good, quality: .good)
        XCTAssertEqual(vm.headRollDegrees, 20 * 1.5, accuracy: 0.01)
    }

    func test_headRoll_cappedAt45() {
        let vm = PostureVisualizationViewModel()
        vm.ingest(metrics: metrics(), pose: makeSample(headRoll: 100),
                  state: .good, quality: .good)
        XCTAssertEqual(vm.headRollDegrees, 45, accuracy: 0.0001) // 100 × 1.5 → clamp

        let vm2 = PostureVisualizationViewModel()
        vm2.ingest(metrics: metrics(), pose: makeSample(headRoll: -100),
                   state: .good, quality: .good)
        XCTAssertEqual(vm2.headRollDegrees, -45, accuracy: 0.0001)
    }

    // MARK: - Calibration-relative pitch & roll (B0 fix)
    //
    // Pitch and roll are now expressed relative to the pose captured when the
    // system leaves calibration into a judged state, so a person whose neutral
    // sit isn't geometrically level no longer renders permanently tilted. The
    // capture only arms via a `.calibrating` frame — without one the behaviour
    // stays absolute (the Step 1 tests above rely on that).

    /// Drives the same frame until the α = 0.2 low-pass has effectively
    /// converged, so assertions can target the steady-state mapped value.
    private func converge(
        _ vm: PostureVisualizationViewModel,
        to pose: PoseSample,
        state: PostureState = .good,
        frames: Int = 400
    ) {
        for _ in 0..<frames {
            vm.ingest(metrics: metrics(), pose: pose, state: state, quality: .good)
        }
    }

    func test_pitchRoll_neutralReadsZero_afterCalibration() {
        let vm = PostureVisualizationViewModel()
        // A neutral sit whose real head geometry is NOT zero: head slightly
        // pitched (+pitch) and tilted (+roll). Pre-fix this would render
        // permanently pitched/rolled.
        let rest = makeSample(headPitch: 8, headRoll: 6)

        vm.ingest(metrics: metrics(), pose: rest, state: .calibrating, quality: .good)
        converge(vm, to: rest, state: .good)

        XCTAssertEqual(vm.headPitchDegrees, 0, accuracy: 0.01,
                       "calibrated neutral pose should read ~0° pitch")
        XCTAssertEqual(vm.headRollDegrees, 0, accuracy: 0.01,
                       "calibrated neutral pose should read ~0° roll")
    }

    func test_pitch_deviationFromCalibratedRest_isRelative() {
        let vm = PostureVisualizationViewModel()
        let rest = makeSample(headPitch: 8, headRoll: 6)
        // Deviation: chin further down (more +pitch); roll unchanged.
        let leanedIn = makeSample(headPitch: 16, headRoll: 6)

        vm.ingest(metrics: metrics(), pose: rest, state: .calibrating, quality: .good)
        // Hold the rest pose through the whole capture window so the averaged
        // reference equals the rest pose exactly.
        for _ in 0..<PostureVisualizationViewModel.Mapping.restPoseCaptureFrames {
            vm.ingest(metrics: metrics(), pose: rest, state: .good, quality: .good)
        }
        converge(vm, to: leanedIn, state: .good)

        // pitch is headPitch × amplification, expressed relative to the rest.
        let expected = (16.0 - 8.0) * 1.5

        XCTAssertEqual(vm.headPitchDegrees, expected, accuracy: 0.01,
                       "pitch should be measured relative to the calibrated rest")
        XCTAssertGreaterThan(vm.headPitchDegrees, 0, "chin further down past rest = +pitch")
        XCTAssertEqual(vm.headRollDegrees, 0, accuracy: 0.01,
                       "unchanged head roll should keep roll at the calibrated 0")
    }

    func test_recalibration_recapturesNeutral() {
        let vm = PostureVisualizationViewModel()
        let poseA = makeSample(headPitch: 8, headRoll: 6)
        // A genuinely different neutral (new desk/posture) on recalibration.
        let poseB = makeSample(headPitch: 12, headRoll: 2)

        vm.ingest(metrics: metrics(), pose: poseA, state: .calibrating, quality: .good)
        converge(vm, to: poseA, state: .good)
        XCTAssertEqual(vm.headPitchDegrees, 0, accuracy: 0.01)
        XCTAssertEqual(vm.headRollDegrees, 0, accuracy: 0.01)

        // Recalibrate at poseB — the reference must re-arm and re-snapshot.
        vm.ingest(metrics: metrics(), pose: poseB, state: .calibrating, quality: .good)
        converge(vm, to: poseB, state: .good)
        XCTAssertEqual(vm.headPitchDegrees, 0, accuracy: 0.01,
                       "recalibration should zero pitch against the new neutral")
        XCTAssertEqual(vm.headRollDegrees, 0, accuracy: 0.01,
                       "recalibration should zero roll against the new neutral")
    }

    func test_restCapture_averagesOutFrameJitter() {
        // Vision keypoints jitter frame to frame. The rest reference must be
        // the mean over the capture window, not a single (possibly outlying)
        // transition frame. Alternate two noisy rest frames whose mean is the
        // true neutral; afterwards, sitting at the true neutral must read ~0°.
        let vm = PostureVisualizationViewModel()
        let noisyA = makeSample(headForwardOffset: -0.04,
                                leftShoulderY: -0.08, rightShoulderY: 0.08)
        let noisyB = makeSample(headForwardOffset: -0.06,
                                leftShoulderY: -0.12, rightShoulderY: 0.12)
        let trueNeutral = makeSample(headForwardOffset: -0.05,
                                     leftShoulderY: -0.10, rightShoulderY: 0.10)

        vm.ingest(metrics: metrics(), pose: noisyA, state: .calibrating, quality: .good)
        for i in 0..<PostureVisualizationViewModel.Mapping.restPoseCaptureFrames {
            vm.ingest(metrics: metrics(), pose: i.isMultiple(of: 2) ? noisyA : noisyB,
                      state: .good, quality: .good)
        }
        converge(vm, to: trueNeutral, state: .good)

        // A single-frame snapshot of noisyA would leave a ~5° pitch error
        // (atan2 is mildly non-linear, so the mean-of-angles reference differs
        // from the true-neutral angle by well under a degree — accept 0.5°).
        XCTAssertEqual(vm.headPitchDegrees, 0, accuracy: 0.5,
                       "averaged rest reference should cancel capture-window jitter")
        XCTAssertEqual(vm.headRollDegrees, 0, accuracy: 0.5,
                       "averaged rest reference should cancel capture-window jitter")
    }

    func test_withoutCalibrationFrame_pitchRollStayAbsolute() {
        // No `.calibrating` frame is ever ingested → references stay 0 →
        // behaviour is the original absolute geometry. This is the contract the
        // Step 1 single-ingest tests depend on; pin it explicitly at steady
        // state too.
        let vm = PostureVisualizationViewModel()
        let tilted = makeSample(headPitch: 0, headRoll: 10)
        converge(vm, to: tilted, state: .good)

        let expectedRollAbs = 10.0 * 1.5
        XCTAssertEqual(vm.headRollDegrees, expectedRollAbs, accuracy: 0.01,
                       "without calibration, roll stays absolute")
        XCTAssertEqual(vm.headPitchDegrees, 0, accuracy: 0.01)
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
