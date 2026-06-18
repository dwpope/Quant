import SwiftUI
import Combine
import simd
import PostureLogic

/// First-order exponential low-pass filter (`vₙ = vₙ₋₁ + α·(target − vₙ₋₁)`).
///
/// The first sample *seeds* the filter directly (no ramp from zero) so channels
/// with a non-zero rest value — e.g. `assemblyScale` rests at 1.0 — settle
/// immediately on first data instead of crawling up from 0. Subsequent samples
/// approach the target geometrically. Exposed as `internal` so Step 1 tests can
/// pin the α math directly.
struct LowPassFilter {
    private(set) var value: Double = 0
    private var seeded = false
    let alpha: Double

    init(alpha: Double = 0.2) {
        self.alpha = alpha
    }

    @discardableResult
    mutating func update(_ target: Double) -> Double {
        if seeded {
            value += alpha * (target - value)
        } else {
            value = target
            seeded = true
        }
        return value
    }

    mutating func reset() {
        value = 0
        seeded = false
    }
}

/// Framework-agnostic view model that turns live posture signals into display
/// values for the 3D visualization (RealityKit *or* the SwiftUI fallback —
/// whichever ships). It owns **no** detection logic: it only consumes the
/// metrics/geometry the pipeline already publishes (design anti-goal: "no new
/// posture detection logic").
///
/// Head yaw/pitch/roll come from the **real head geometry** now exposed on
/// `PoseSample` (`headYaw`/`headPitch`/`headRoll`, degrees, computed in
/// `PoseDepthFusion.computeHeadAngles` from the nose/ear/eye keypoints — and, in
/// depth mode, a LiDAR elevation for pitch). Earlier sub-stages substituted
/// shoulder-skeleton proxies (yaw ← `shoulderTwist`, pitch ← `headForwardOffset`,
/// roll ← shoulder-line angle) because the keypoints weren't on the public
/// surface; that surface now exists, so a shoulder shrug with a still head no
/// longer registers as head movement. The ViewModel only *amplifies, caps, and
/// rest-relative-zeroes* these angles for display — it owns no detection logic.
///
/// Tests drive the camera-free `ingest(metrics:pose:state:quality:)` seam;
/// `bind(to:)` wires the same seam to `AppModel`'s Combine publishers in the app.
@MainActor
final class PostureVisualizationViewModel: ObservableObject {

    // MARK: Published display values (the design doc's output property list)

    @Published private(set) var shoulderRotationDegrees: Double = 0   // ← twist
    @Published private(set) var sideLeanOffsetPoints: Double = 0       // ← lateralLean
    @Published private(set) var headForwardOffsetPoints: Double = 0    // ← PoseSample.headForwardOffset
    @Published private(set) var assemblyScale: Double = 1              // ← forwardCreep
    @Published private(set) var headYawDegrees: Double = 0             // ← PoseSample.headYaw
    @Published private(set) var headPitchDegrees: Double = 0           // ← PoseSample.headPitch
    @Published private(set) var headRollDegrees: Double = 0            // ← PoseSample.headRoll
    @Published private(set) var opacity: Double = 1                    // ← trackingQuality
    @Published private(set) var stateColor: Color = .gray             // ← postureState
    @Published private(set) var isCalibrating: Bool = false           // ← postureState

    // MARK: Raw upstream inputs (unsmoothed; dev tuning HUD only)
    //
    // `ingest` consumes the pipeline signals and immediately maps + smooths
    // them into the display values above, discarding the raw inputs. The dev
    // overlay needs the *pre-mapping* numbers next to the mapped outputs to
    // judge whether the `Mapping` amplify/cap constants feel right, so we keep
    // a parallel, unsmoothed copy. These never drive the scene — the binding
    // reads only the display values — so they cannot affect the visual.
    // Written only while `isTuningHUDActive`, so the hidden HUD costs no
    // `objectWillChange` traffic on the per-frame ingest path.

    /// Set by the hosting view when the tuning HUD is shown/hidden. Gates the
    /// eight HUD-only published properties below; the display values above are
    /// always live.
    var isTuningHUDActive = false

    @Published private(set) var rawTwist: Double = 0                  // RawMetrics.twist
    @Published private(set) var rawLateralLean: Double = 0            // RawMetrics.lateralLean
    @Published private(set) var rawForwardCreep: Double = 0           // RawMetrics.forwardCreep
    @Published private(set) var rawHeadForwardOffset: Double = 0      // PoseSample.headForwardOffset
    @Published private(set) var rawShoulderTwist: Double = 0          // PoseSample.shoulderTwist

    /// Lean diagnostics: is the pipeline delivering metrics at all (nil ⇒ no
    /// baseline ⇒ every baseline-relative channel is 0), and the raw shoulder
    /// midpoint image-x that `lateralLeanSigned` is the baseline-delta of — so we
    /// can see whether the *source* moves when you lean.
    @Published private(set) var metricsPresent: Bool = false         // metrics != nil
    @Published private(set) var rawShoulderMidX: Double = 0          // PoseSample.shoulderMidpoint.x

    /// Real head angles straight off `PoseSample` (degrees, pre-amplify/clamp) —
    /// the raw side of the dev HUD's raw↔mapped head rows (Step 5).
    @Published private(set) var rawHeadYaw: Double = 0                // PoseSample.headYaw
    @Published private(set) var rawHeadPitch: Double = 0              // PoseSample.headPitch
    @Published private(set) var rawHeadRoll: Double = 0               // PoseSample.headRoll

    /// Amplified yaw/pitch/roll *before* the per-axis cap. Compared against the
    /// clamped `head*Degrees` outputs, a divergence here means the cap is
    /// currently clipping — the single clearest cue for tuning `*CapDegrees`.
    @Published private(set) var unclampedYawDegrees: Double = 0
    @Published private(set) var unclampedPitchDegrees: Double = 0
    @Published private(set) var unclampedRollDegrees: Double = 0

    /// Low-pass smoothing factor (design starting value). Tune by eye later.
    static let smoothingAlpha: Double = 0.2

    /// Faster smoothing for the lean channels. Lean already passes through the
    /// pipeline's `MetricsSmoother` upstream, so a second α=0.2 stage here stacks
    /// into a sluggish ~1.5–2 s settle; a higher α keeps lean responsive to a real
    /// torso movement while the upstream stage still removes per-frame jitter.
    static let leanSmoothingAlpha: Double = 0.5

    /// All scaling/clamping constants in one place so the renderer and the
    /// ViewModel stay in sync and remain tunable during demo recording
    /// (design "Variable Mapping" reference table).
    enum Mapping {
        /// twist → shoulder-disc rotation. Signed & tunable (a DEBUG slider flips
        /// it past 0 to correct direction); Release uses the default.
        static var twistAmplification: Double = twistAmplificationDefault
        static let twistAmplificationDefault: Double = 1.5
        static let sideLeanPointsPerUnit = 100.0       // lateralLean → points
        static let headForwardPointsPerUnit = 100.0    // headForwardOffset → points
        static let forwardCreepScaleFactor = 0.5       // assemblyScale = 1 + creep × 0.5
        static let headRotationAmplification = 1.5     // yaw/pitch/roll amplify
        static let yawCapDegrees = 90.0
        static let pitchCapDegrees = 60.0
        static let rollCapDegrees = 45.0
        /// Reference depth (metres) the head sits forward of the shoulders;
        /// mirrors the design's ~0.15 head-above-disc offset and turns the
        /// unbounded `headForwardOffset` into a bounded pitch angle.
        static let headDepthReference = 0.15
        /// Number of judged frames averaged into the calibration-relative
        /// rest reference. Vision keypoints jitter frame to frame; snapshotting
        /// a single transition frame bakes that noise into every subsequent
        /// render, so the reference is the running mean of the first N judged
        /// frames instead (~1 s at the pipeline's ~10 FPS).
        static let restPoseCaptureFrames = 10
    }

    // MARK: Smoothing channels (one filter per continuous output)

    private var rotationFilter = LowPassFilter(alpha: smoothingAlpha)
    private var sideLeanFilter = LowPassFilter(alpha: leanSmoothingAlpha)
    private var forwardFilter = LowPassFilter(alpha: leanSmoothingAlpha)
    private var scaleFilter = LowPassFilter(alpha: smoothingAlpha)
    private var yawFilter = LowPassFilter(alpha: smoothingAlpha)
    private var pitchFilter = LowPassFilter(alpha: smoothingAlpha)
    private var rollFilter = LowPassFilter(alpha: smoothingAlpha)
    private var opacityFilter = LowPassFilter(alpha: smoothingAlpha)

    // MARK: Calibration-relative reference (pitch & roll)
    //
    // Pitch and roll are derived from *absolute* pose geometry, so a person
    // whose neutral sit isn't geometrically level (camera tilt, natural
    // posture) renders permanently tilted — the original "buggy look". When
    // the system leaves calibration into a judged state we average the
    // absolute pitch/roll over the first `Mapping.restPoseCaptureFrames`
    // judged frames (the user's calibrated neutral, noise-averaged) and
    // express subsequent pitch/roll *relative* to it, so a neutral sit reads
    // ~0°. Re-armed on every (re)calibration. A VM that never sees a
    // `.calibrating` frame keeps the `0` references, i.e. absolute behaviour —
    // which is why the Step 1 absolute-geometry tests still hold.
    private var restPitchDegrees: Double = 0
    private var restRollDegrees: Double = 0
    private var wasCalibrating = false
    private var restCaptureRemaining = 0
    private var restPitchSum: Double = 0
    private var restRollSum: Double = 0

    private var cancellables = Set<AnyCancellable>()

    // MARK: Init

    init() {}

    /// App entry point: subscribe to the live pipeline signals.
    convenience init(appModel: AppModel) {
        self.init()
        bind(to: appModel)
    }

    /// Teardown releases value-type filters and cancels Combine subscriptions —
    /// none of which require main-actor isolation. Without this, the module's
    /// default `@MainActor` isolation gives the class an *isolated* deinit that
    /// back-deploys (iOS 18 target) through `swift_task_deinitOnExecutorMain‑
    /// ActorBackDeploy`; when XCTest deallocates the object outside a Swift
    /// task that shim corrupts the heap and aborts. `nonisolated` emits a
    /// plain deinit with no executor hop. See implementation/progress.md.
    nonisolated deinit {}

    // MARK: Binding

    /// Wires `AppModel`'s four posture publishers into the testable `ingest`
    /// seam. `CombineLatest4` re-emits whenever any input changes; all four are
    /// `@Published` so each delivers its current value on subscription.
    ///
    /// Idempotent: re-binding replaces any previous subscription instead of
    /// stacking a duplicate pipeline, so callers can bind on every appear.
    /// Delivery hops via `DispatchQueue.main` (not `RunLoop.main`, which
    /// stalls in the tracking run-loop mode during scrolls and drags).
    func bind(to appModel: AppModel) {
        cancellables.removeAll()
        Publishers.CombineLatest4(
            appModel.$latestMetrics,
            appModel.$latestSample,
            appModel.$postureState,
            appModel.$trackingQuality
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] metrics, sample, state, quality in
            self?.ingest(metrics: metrics, pose: sample, state: state, quality: quality)
        }
        .store(in: &cancellables)
    }

    // MARK: Ingest seam (camera-free; the unit-test entry point)

    func ingest(
        metrics: RawMetrics?,
        pose: PoseSample?,
        state: PostureState,
        quality: TrackingQuality
    ) {
        let m = metrics ?? .zero

        // Signed twist so the disc rotates the way the torso actually turned
        // (m.twist is unsigned magnitude for scoring; the viz needs the sense).
        let rotationTarget = Double(m.twistSigned) * Double(Mapping.twistAmplification)
        // Signed lateral lean so the figure tilts toward the actual lean side
        // (`m.lateralLean` is unsigned magnitude for scoring; the viz needs sense).
        let sideLeanTarget = Double(m.lateralLeanSigned) * Mapping.sideLeanPointsPerUnit
        let scaleTarget = 1.0 + Double(m.forwardCreep) * Mapping.forwardCreepScaleFactor

        let forwardTarget: Double
        let yawTarget: Double
        let pitchTarget: Double
        let rollTarget: Double

        let judged = Self.isJudged(state)

        if let p = pose {
            forwardTarget = Double(p.headForwardOffset) * Mapping.headForwardPointsPerUnit

            // Yaw ← real head yaw (PoseSample.headYaw, degrees). Absolute: a
            // forward-facing head already reads ~0°, so no rest reference is
            // needed (unlike pitch/roll, whose raw zero is geometric).
            let yawRaw = Double(p.headYaw) * Mapping.headRotationAmplification
            yawTarget = Self.clamp(yawRaw, -Mapping.yawCapDegrees, Mapping.yawCapDegrees)

            // Pitch ← real head pitch (degrees). Absolute geometry, re-zeroed to
            // the calibrated rest pose below (the raw zero is the on-the-line /
            // ear-plane case, not a physiological neutral — see
            // PoseDepthFusion.computeHeadPitch / computeHeadPitch3D).
            let pitchAbs = Double(p.headPitch) * Mapping.headRotationAmplification

            // Roll ← real head roll (PoseSample.headRoll, degrees).
            let rollAbs = Double(p.headRoll) * Mapping.headRotationAmplification

            // On the calibrating→judged transition, start capturing the rest
            // reference so neutral reads ~0° (fixes the permanently-tilted
            // rig). Only re-arms once per (re)calibration.
            if wasCalibrating && judged {
                restCaptureRemaining = Mapping.restPoseCaptureFrames
                restPitchSum = 0
                restRollSum = 0
                wasCalibrating = false
            }

            // While capturing, the reference is the running mean of the judged
            // frames seen so far — the first frame still zeroes the display
            // immediately, and each further frame averages the keypoint jitter
            // out of the reference instead of freezing a single noisy frame in.
            if restCaptureRemaining > 0 && judged {
                restPitchSum += pitchAbs
                restRollSum += rollAbs
                let captured = Mapping.restPoseCaptureFrames - restCaptureRemaining + 1
                restPitchDegrees = restPitchSum / Double(captured)
                restRollDegrees = restRollSum / Double(captured)
                restCaptureRemaining -= 1
            }

            // Express pitch/roll relative to the calibrated rest pose. With the
            // default `0` references (no calibration seen) this is identity, so
            // the absolute-geometry behaviour is preserved.
            let pitchRel = pitchAbs - restPitchDegrees
            let rollRel = rollAbs - restRollDegrees
            pitchTarget = Self.clamp(pitchRel, -Mapping.pitchCapDegrees, Mapping.pitchCapDegrees)
            rollTarget = Self.clamp(rollRel, -Mapping.rollCapDegrees, Mapping.rollCapDegrees)

            // Keep the pre-clamp (calibration-relative) angles for the dev HUD,
            // so its cap-clipping highlight reflects what is actually clamped.
            if isTuningHUDActive {
                unclampedYawDegrees = yawRaw
                unclampedPitchDegrees = pitchRel
                unclampedRollDegrees = rollRel
            }
        } else {
            forwardTarget = 0
            yawTarget = 0
            pitchTarget = 0
            rollTarget = 0
            if isTuningHUDActive {
                unclampedYawDegrees = 0
                unclampedPitchDegrees = 0
                unclampedRollDegrees = 0
            }
        }

        // Re-arm the rest-pose capture while calibrating, so the first run and
        // every recalibration re-snapshot a fresh neutral on the next judged
        // frame. Placed after the capture check: a single frame is either
        // calibrating or judged, never both, so there is no same-frame race.
        if state == .calibrating { wasCalibrating = true }

        shoulderRotationDegrees = rotationFilter.update(rotationTarget)
        sideLeanOffsetPoints = sideLeanFilter.update(sideLeanTarget)
        headForwardOffsetPoints = forwardFilter.update(forwardTarget)
        assemblyScale = scaleFilter.update(scaleTarget)
        headYawDegrees = yawFilter.update(yawTarget)
        headPitchDegrees = pitchFilter.update(pitchTarget)
        headRollDegrees = rollFilter.update(rollTarget)
        opacity = opacityFilter.update(Self.opacity(for: quality))

        // Discrete signals — no smoothing (an interpolated colour/flag is wrong).
        stateColor = Self.color(for: state)
        isCalibrating = (state == .calibrating)

        // Raw inputs mirrored for the dev HUD (unsmoothed, scene-irrelevant).
        if isTuningHUDActive {
            rawTwist = Double(m.twistSigned)               // signed: the viz HUD shows twist direction
            rawLateralLean = Double(m.lateralLeanSigned)   // signed: the viz HUD shows lean direction
            rawForwardCreep = Double(m.forwardCreep)
            metricsPresent = (metrics != nil)
            rawShoulderMidX = pose.map { Double($0.shoulderMidpoint.x) } ?? 0
            rawHeadForwardOffset = pose.map { Double($0.headForwardOffset) } ?? 0
            rawShoulderTwist = pose.map { Double($0.shoulderTwist) } ?? 0
            rawHeadYaw = pose.map { Double($0.headYaw) } ?? 0
            rawHeadPitch = pose.map { Double($0.headPitch) } ?? 0
            rawHeadRoll = pose.map { Double($0.headRoll) } ?? 0
        }
    }

    // MARK: Pure mappings

    /// Tracking quality → opacity. Monotonic so a quality drop visibly fades
    /// the assembly (design acceptance criterion).
    static func opacity(for quality: TrackingQuality) -> Double {
        switch quality {
        case .lost:     return 0.25
        case .degraded: return 0.6
        case .good:     return 1.0
        }
    }

    /// Posture state → tint. The four judged states are deliberately distinct;
    /// `.absent` shares the neutral grey of `.calibrating` (idle ≈ not judging).
    static func color(for state: PostureState) -> Color {
        switch state {
        case .absent, .calibrating: return .gray
        case .good:                 return .green
        case .drifting:             return .orange
        case .bad:                  return .red
        }
    }

    private static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(x, lo), hi)
    }

    /// Whether the state is one the engine actively judges (vs. idle/absent or
    /// still calibrating). Gates the calibration-relative rest-pose capture so
    /// it snapshots a settled posture, never a transient calibration frame.
    private static func isJudged(_ state: PostureState) -> Bool {
        switch state {
        case .good, .drifting, .bad: return true
        case .absent, .calibrating:  return false
        }
    }
}
