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
/// Head yaw/pitch/roll are *display heuristics* derived from `PoseSample`
/// geometry. The design doc derives them from raw nose/ear/eye keypoints, but
/// those are PostureLogic-internal and not exposed on `AppModel`/`PoseSample`
/// (see implementation/progress.md "Type Map"). The substituted mapping —
/// roll ← left/right-shoulder line angle, yaw ← `shoulderTwist`,
/// pitch ← `headForwardOffset` elevation — keeps the work inside the public
/// surface while preserving the design's amplify-and-cap intent.
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
    @Published private(set) var headYawDegrees: Double = 0             // ← shoulderTwist
    @Published private(set) var headPitchDegrees: Double = 0           // ← headForwardOffset
    @Published private(set) var headRollDegrees: Double = 0            // ← shoulder line angle
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

    @Published private(set) var rawTwist: Double = 0                  // RawMetrics.twist
    @Published private(set) var rawLateralLean: Double = 0            // RawMetrics.lateralLean
    @Published private(set) var rawForwardCreep: Double = 0           // RawMetrics.forwardCreep
    @Published private(set) var rawHeadForwardOffset: Double = 0      // PoseSample.headForwardOffset
    @Published private(set) var rawShoulderTwist: Double = 0          // PoseSample.shoulderTwist

    /// Amplified yaw/pitch/roll *before* the per-axis cap. Compared against the
    /// clamped `head*Degrees` outputs, a divergence here means the cap is
    /// currently clipping — the single clearest cue for tuning `*CapDegrees`.
    @Published private(set) var unclampedYawDegrees: Double = 0
    @Published private(set) var unclampedPitchDegrees: Double = 0
    @Published private(set) var unclampedRollDegrees: Double = 0

    /// Low-pass smoothing factor (design starting value). Tune by eye later.
    static let smoothingAlpha: Double = 0.2

    /// All scaling/clamping constants in one place so the renderer and the
    /// ViewModel stay in sync and remain tunable during demo recording
    /// (design "Variable Mapping" reference table).
    enum Mapping {
        static let twistAmplification = 1.5            // twist → shoulder disc rotation
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
    }

    // MARK: Smoothing channels (one filter per continuous output)

    private var rotationFilter = LowPassFilter(alpha: smoothingAlpha)
    private var sideLeanFilter = LowPassFilter(alpha: smoothingAlpha)
    private var forwardFilter = LowPassFilter(alpha: smoothingAlpha)
    private var scaleFilter = LowPassFilter(alpha: smoothingAlpha)
    private var yawFilter = LowPassFilter(alpha: smoothingAlpha)
    private var pitchFilter = LowPassFilter(alpha: smoothingAlpha)
    private var rollFilter = LowPassFilter(alpha: smoothingAlpha)
    private var opacityFilter = LowPassFilter(alpha: smoothingAlpha)

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
    func bind(to appModel: AppModel) {
        Publishers.CombineLatest4(
            appModel.$latestMetrics,
            appModel.$latestSample,
            appModel.$postureState,
            appModel.$trackingQuality
        )
        .receive(on: RunLoop.main)
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

        let rotationTarget = Double(m.twist) * Mapping.twistAmplification
        let sideLeanTarget = Double(m.lateralLean) * Mapping.sideLeanPointsPerUnit
        let scaleTarget = 1.0 + Double(m.forwardCreep) * Mapping.forwardCreepScaleFactor

        let forwardTarget: Double
        let yawTarget: Double
        let pitchTarget: Double
        let rollTarget: Double

        if let p = pose {
            forwardTarget = Double(p.headForwardOffset) * Mapping.headForwardPointsPerUnit

            // Yaw ← shoulder twist (already degrees: asin(clamp)·180/π).
            let yawRaw = Double(p.shoulderTwist) * Mapping.headRotationAmplification
            yawTarget = Self.clamp(yawRaw, -Mapping.yawCapDegrees, Mapping.yawCapDegrees)

            // Pitch ← head depth offset as an elevation angle. Negative
            // headForwardOffset = head toward camera = leaning forward = +pitch.
            let pitchRaw = atan2(Double(-p.headForwardOffset), Mapping.headDepthReference)
                * 180.0 / .pi * Mapping.headRotationAmplification
            pitchTarget = Self.clamp(pitchRaw, -Mapping.pitchCapDegrees, Mapping.pitchCapDegrees)

            // Roll ← angle of the right→left shoulder line (the exposed analog
            // of the design's ear-line roll).
            let dx = Double(p.rightShoulder.x - p.leftShoulder.x)
            let dy = Double(p.rightShoulder.y - p.leftShoulder.y)
            let rollRaw = atan2(dy, dx) * 180.0 / .pi * Mapping.headRotationAmplification
            rollTarget = Self.clamp(rollRaw, -Mapping.rollCapDegrees, Mapping.rollCapDegrees)

            // Keep the pre-clamp angles for the dev HUD (does not drive scene).
            unclampedYawDegrees = yawRaw
            unclampedPitchDegrees = pitchRaw
            unclampedRollDegrees = rollRaw
        } else {
            forwardTarget = 0
            yawTarget = 0
            pitchTarget = 0
            rollTarget = 0
            unclampedYawDegrees = 0
            unclampedPitchDegrees = 0
            unclampedRollDegrees = 0
        }

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
        rawTwist = Double(m.twist)
        rawLateralLean = Double(m.lateralLean)
        rawForwardCreep = Double(m.forwardCreep)
        rawHeadForwardOffset = pose.map { Double($0.headForwardOffset) } ?? 0
        rawShoulderTwist = pose.map { Double($0.shoulderTwist) } ?? 0
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
}
