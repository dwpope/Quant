#if DEBUG
import SwiftUI
import PostureLogic

/// Dev-only on-device tuning panel for the live posture mapping. Two sections:
/// * **Head-yaw calibration** — `HeadYawTuning.oneEarCalibration` (the `k = E₀/d`
///   factor in `PoseDepthFusion.oneEarYaw`). Occlude one ear, watch the live
///   `rawYaw`, and nudge `k` until the figure matches a known angle.
/// * **Lean gains** — `PostureVisualizationBinding.lean/forwardLeanRadiansPerMeter`.
///   Signed sliders: slide past 0 to flip lean direction, away from 0 for
///   intensity. Lean left/right & fore/aft to confirm sign by eye.
///
/// Dials the mapping by eye without a rebuild.
///
/// **Scaffolding, not product**: the whole file is `#if DEBUG`, so it is stripped
/// from Release / TestFlight (matching `PostureVisualizationDevNotes`). It writes
/// the shared `static var` knobs directly — see the concurrency note on
/// `HeadYawTuning`; the unsynchronized scalar writes from the main thread are a
/// benign debug race. The panel mirrors the rig's other HUDs (monospaced,
/// ultra-thin material).
struct PostureVisualizationCalibrationOverlay: View {

    @ObservedObject var viewModel: PostureVisualizationViewModel
    @ObservedObject var appModel: AppModel

    private typealias Bind = PostureVisualizationBinding

    /// Sources of truth for the sliders. Each backing knob is a plain `static var`
    /// (not observable), so we drive it from `@State` and write through on change
    /// rather than binding to it directly.
    // One @State per tunable 2D-posture knob. Depth-only channels (forward-lean,
    // axial twist) have no sliders here — they can't be tuned without LiDAR.
    @State private var calibration: Float = HeadYawTuning.oneEarCalibration
    @State private var sideLeanGain: Float = Bind.leanRadiansPerMeter
    @State private var headYawGain: Float = Bind.headYawGain
    @State private var headPitchGain: Float = Bind.headPitchGain
    @State private var nodDownBoost: Float = Bind.headPitchDownBoost
    @State private var headRollGain: Float = Bind.headRollGain
    @State private var scaleGain: Float = Float(PostureVisualizationViewModel.Mapping.forwardCreepScaleFactor)
    @State private var leanTurnAtten: Float = Bind.leanTurnAttenPower
    @State private var turnDecouple: Float = Bind.turnTiltDecouple
    @State private var tiltFade: Float = Bind.activeTiltTurnFadePower
    @State private var smoothing: Float = Bind.orientationSmoothTime
    @State private var jitterFloor: Float = HeadAngleFilterTuning.minCutoff
    @State private var jitterCatchup: Float = HeadAngleFilterTuning.beta

    // Quaternion head path (Front Face): one uniform angle gain + one total-angle
    // clamp + the indexed axis-map, replacing the per-axis Euler gains above.
    @State private var headRotationGain: Float = Bind.headRotationGain
    @State private var headRotationMaxAngle: Float = Bind.headRotationMaxAngleDegrees
    @State private var basisIndex: Int = Bind.headRenderBasisIndex

    /// Bumped on every channel toggle / solo / all-off so the panel's label &
    /// `iso` states refresh — the underlying `debug` flags are a non-observable
    /// `static`, so without a published nudge the row colours would lag a frame.
    @State private var channelTick = 0

    /// Head-yaw `k` (one-ear detection calibration) bounds — device-tuned to ≈8.0.
    private static let yawRange: ClosedRange<Float> = 1.0...12.0

    /// Side-lean gain bounds. **Signed**, straddling 0, so the slider both flips
    /// direction (past 0) and sets intensity. Wide because the lean signal is a
    /// small normalized shoulder shift (~0.05–0.1) attenuated ×0.1 by the legacy
    /// points→metres chain (output capped at `leanCapRadians`, so over-driving
    /// just saturates).
    private static let leanRange: ClosedRange<Float> = -100.0...100.0

    /// Head display-gain bounds. **Signed** so each head axis can be flipped or
    /// damped/boosted. ±6 (widened 2026-06-19): head nod needed −6 for a legible
    /// nod once the ×0.6 shaping + deadzone are accounted for; turn (−0.6) and
    /// tilt (−3) sit well inside.
    private static let headGainRange: ClosedRange<Float> = -6.0...6.0

    /// Proximity (lean-in) zoom bounds — unsigned; 0 = no scale response.
    private static let scaleRange: ClosedRange<Float> = 0.0...2.0

    /// Chin-down nod boost bounds (`headPitchDownBoost`): 1 = symmetric with the
    /// base nod gain, up to 8× extra travel going down (the 2D pitch signal is
    /// small, so the down nod needs a large multiplier to read).
    private static let nodBoostRange: ClosedRange<Float> = 1.0...8.0

    /// Turn-cancels-lean aggressiveness (`cos(headYaw)^this`): 0 = off, 1 = cos,
    /// >1 = a small turn already kills the lean.
    private static let attenRange: ClosedRange<Float> = 0.0...3.0

    /// Turn→nod decouple bounds (`turnTiltDecouple`): **signed** raw-pitch
    /// correction gain. Defaulted OFF — the additive shape didn't match the device's
    /// phantom (it bulged instead of flattening); `turn↓tilt` fade is the live knob.
    private static let decoupleRange: ClosedRange<Float> = -2.0...2.0

    /// Turn-fades-tilt exponent (`cos(yaw)^this` on pitch/roll), editing whichever
    /// head source is live: **0 = fade off, perfectly round** (the `.frontFace`
    /// ARKit default — decoupled source, no phantom to cancel); 1 = plain cos; higher
    /// = flatter pure turn at the cost of a flatter circle (the legacy 2D default is
    /// 2). Overshoot-proof (only fades toward flat).
    private static let tiltFadeRange: ClosedRange<Float> = 0.0...6.0

    /// Orientation smoothing bounds (`orientationSmoothTime`, **seconds** — the dt-aware
    /// critically-damped follower's convergence time, NOT a slerp weight). 0 = no
    /// smoothing (snap to the live pose); higher = smoother but laggier. Top at 0.30 s
    /// (clearly over-damped) so the slider spans snap → sluggish; ~0.09 s is the default.
    private static let smoothRange: ClosedRange<Float> = 0.0...0.30

    /// Head-angle One Euro **steady** floor (`HeadAngleFilterTuning.minCutoff`, Hz):
    /// the smoothing applied while the head is still. **Lower = steadier** (kills more
    /// jitter, a touch more hold-lag); higher lets the raw signal through. The fix for
    /// "the pitch won't sit still" lives here. ~1.0 is the gentle default.
    private static let jitterFloorRange: ClosedRange<Float> = 0.2...4.0

    /// Head-angle One Euro **catch-up** (`HeadAngleFilterTuning.beta`): how fast the
    /// cutoff opens up with motion. **Higher = snappier** on a real nod (less lag),
    /// lower = more smoothing even while moving. 0 makes it a plain fixed low-pass.
    private static let jitterCatchupRange: ClosedRange<Float> = 0.0...0.30

    /// Quaternion-head uniform rotation-angle **gain** (`headRotationGain`): 1.0 =
    /// faithful (figure mirrors the real head 1:1), up for legibility exaggeration.
    /// One scalar scales the rotation about whatever axis the head turned, so it can
    /// never introduce the cross-axis leak the old anisotropic Euler gains did.
    private static let headRotGainRange: ClosedRange<Float> = 0.5...2.0

    /// Quaternion-head total-angle **clamp** (`headRotationMaxAngleDegrees`): the
    /// single rendered-angle ceiling replacing the three Euler caps.
    private static let headRotMaxRange: ClosedRange<Float> = 20.0...120.0

    // The body is split into these `@ViewBuilder` sections deliberately: as one
    // ~140-line `VStack` the Swift type-checker timed out ("unable to type-check
    // in reasonable time"), since a result-builder block is inferred as a single
    // expression whose cost grows super-linearly with sibling count. Each section
    // is its own `some View`, keeping every block small enough to solve quickly.

    /// Calibration baseline status + a recalibrate action. Lean/twist/creep are
    /// measured relative to this baseline; with none they read 0 at any gain
    /// (head angles bypass it), and the viz shows no prompt — so surface it here.
    @ViewBuilder
    private var calibrationSection: some View {
        HStack(spacing: 6) {
            Text("CALIBRATION").fontWeight(.semibold)
            Spacer(minLength: 12)
            Button("recalibrate") { appModel.recalibrate() }
                .buttonStyle(.plain).foregroundStyle(.blue)
        }
        let calib = calibLabel(appModel.calibrationStatus)
        HStack(spacing: 6) {
            Text("state").foregroundStyle(.secondary)
            Text(calib.text).fontWeight(.semibold).foregroundStyle(calib.tint)
        }
        Text("sit upright & still until 'calibrated ✓', then lean")
            .font(.caption2).foregroundStyle(.secondary)
    }

    /// Head-yaw `k` calibration slider with live `rawYaw` feedback — turn to a
    /// known angle and tune `k` until the readout matches it.
    @ViewBuilder
    private var headYawSection: some View {
        sectionHeader("HEAD-YAW CALIB",
                      reset: { calibration = HeadYawTuning.oneEarCalibrationDefault },
                      isDefault: calibration == HeadYawTuning.oneEarCalibrationDefault)

        // The knob: k (E₀/d). Step matches the eyeball precision you can judge.
        gainRow("k", value: $calibration, range: Self.yawRange, step: 0.05, decimals: 2)

        // Live feedback: raw head-yaw (the signal k scales). Only meaningful past
        // the ear-occlusion boundary — below it both ears drive the asin path.
        HStack(spacing: 6) {
            Text("rawYaw").foregroundStyle(.secondary)
            Text("→").foregroundStyle(.secondary)
            Text(String(format: "%+.1f°", viewModel.rawHeadYaw))
                .fontWeight(.semibold)
                .foregroundStyle(abs(viewModel.rawHeadYaw) >= 45 ? .green : .secondary)
        }
        Text("turn until one ear hides, then match the angle")
            .font(.caption2).foregroundStyle(.secondary)
    }

    /// Title + reset for the 2D-posture gain block. One slider per posture type
    /// the 2D image can infer; depth-only channels (forward-lean, axial twist)
    /// are intentionally absent.
    @ViewBuilder
    private var postureGainsHeader: some View {
        sectionHeader("2D POSTURE · isolate",
                      reset: {
                          sideLeanGain = Bind.leanRadiansPerMeterDefault
                          headYawGain = Bind.headYawGainDefault
                          headPitchGain = Bind.headPitchGainDefault
                          nodDownBoost = Bind.headPitchDownBoostDefault
                          headRollGain = Bind.headRollGainDefault
                          scaleGain = Float(PostureVisualizationViewModel.Mapping.forwardCreepScaleFactorDefault)
                          leanTurnAtten = Bind.leanTurnAttenPowerDefault
                          turnDecouple = Bind.turnTiltDecoupleDefault
                          tiltFade = Bind.activeTiltTurnFadePowerDefault
                          smoothing = Bind.orientationSmoothTimeDefault
                          jitterFloor = HeadAngleFilterTuning.minCutoffDefault
                          jitterCatchup = HeadAngleFilterTuning.betaDefault
                      },
                      isDefault: sideLeanGain == Bind.leanRadiansPerMeterDefault
                              && headYawGain == Bind.headYawGainDefault
                              && headPitchGain == Bind.headPitchGainDefault
                              && nodDownBoost == Bind.headPitchDownBoostDefault
                              && headRollGain == Bind.headRollGainDefault
                              && scaleGain == Float(PostureVisualizationViewModel.Mapping.forwardCreepScaleFactorDefault)
                              && leanTurnAtten == Bind.leanTurnAttenPowerDefault
                              && turnDecouple == Bind.turnTiltDecoupleDefault
                              && tiltFade == Bind.activeTiltTurnFadePowerDefault
                              && smoothing == Bind.orientationSmoothTimeDefault
                              && jitterFloor == HeadAngleFilterTuning.minCutoffDefault
                              && jitterCatchup == HeadAngleFilterTuning.betaDefault)

        Text("2D only — torso-turn & forward-lean need LiDAR, hidden here")
            .font(.caption2).foregroundStyle(.secondary)
    }

    /// The signed gain sliders. Slide past 0 to flip direction, away from 0 for
    /// intensity. Tap a label to toggle that channel off; tap "iso" to SOLO it
    /// (all others off) and confirm that one posture works alone.
    @ViewBuilder
    private var postureGainSliders: some View {
        gainRow("side lean", value: $sideLeanGain,  range: Self.leanRange,     step: 0.5,  decimals: 1, enabled: debugBinding(\.sideLean),     solo: { soloChannel(\.sideLean) })
        gainRow("head turn", value: $headYawGain,   range: Self.headGainRange, step: 0.05, decimals: 2, enabled: debugBinding(\.headYaw),      solo: { soloChannel(\.headYaw) })
        gainRow("head nod",  value: $headPitchGain, range: Self.headGainRange, step: 0.05, decimals: 2, enabled: debugBinding(\.headPitch),    solo: { soloChannel(\.headPitch) })
        // Extra down-travel for the nod (chin-down only); no toggle — it's a
        // refinement of the head-nod channel above, gated by the same flag.
        gainRow("nod ↓",     value: $nodDownBoost,  range: Self.nodBoostRange,  step: 0.1,  decimals: 1)
        gainRow("head tilt", value: $headRollGain,  range: Self.headGainRange, step: 0.05, decimals: 2, enabled: debugBinding(\.headRoll),     solo: { soloChannel(\.headRoll) })
        gainRow("zoom",      value: $scaleGain,     range: Self.scaleRange,    step: 0.05, decimals: 2, enabled: debugBinding(\.assemblyScale), solo: { soloChannel(\.assemblyScale) })
        // How hard a chair-swivel (head turn) cancels the side lean (no channel
        // toggle — set to 0 to disable).
        gainRow("turn↓lean", value: $leanTurnAtten, range: Self.attenRange,    step: 0.1,  decimals: 1)
        // Fades phantom nod/tilt as the head turns — raise to flatten the "W" of
        // a pure left↔right sweep (overshoot-proof; slightly flattens a circle).
        gainRow("turn↓tilt", value: $tiltFade,      range: Self.tiltFadeRange, step: 0.1,  decimals: 1)
        // Additive turn→nod decouple — defaulted OFF (the fade above is the live
        // knob); kept for a future, shape-matched phantom model.
        gainRow("turn→nod",  value: $turnDecouple,  range: Self.decoupleRange, step: 0.05, decimals: 2)
        // Motion smoothing (head + torso), in SECONDS: 0 = instant snap, higher =
        // more fluid/laggy. dt-aware critically-damped follower over the combined
        // pose, so a nod+turn eases as one pulse-free arc (no channel toggle).
        gainRow("smooth",    value: $smoothing,     range: Self.smoothRange,   step: 0.01, decimals: 2)
        // Source denoise (One Euro on the raw head angles, before gain): "steady"
        // is the still-state smoothing floor (lower = steadier), "catch-up" is how
        // fast it opens up for a real move (higher = snappier). Fixes pitch jitter
        // without the lag a fixed low-pass would add. No channel toggle.
        gainRow("steady",    value: $jitterFloor,   range: Self.jitterFloorRange,   step: 0.1,  decimals: 1)
        gainRow("catch-up",  value: $jitterCatchup, range: Self.jitterCatchupRange, step: 0.01, decimals: 2)
    }

    /// Live raw inputs + source/depth diagnostics for orientation while tuning
    /// (metrics ✗ = no baseline; depth gates the forward-lean & real-twist channels).
    @ViewBuilder
    private var postureDiagnostics: some View {
        HStack(spacing: 10) {
            Text(String(format: "lean %+.3f", viewModel.rawLateralLean))
            Text(String(format: "yaw %+.0f°", viewModel.rawHeadYaw))
            Text(String(format: "pitch %+.0f°", viewModel.rawHeadPitch))
        }
        .foregroundStyle(.secondary)
        HStack(spacing: 8) {
            Text("metrics")
            Text(viewModel.metricsPresent ? "✓" : "✗")
                .fontWeight(.bold)
                .foregroundStyle(viewModel.metricsPresent ? .green : .red)
            Text("depth \(String(describing: appModel.depthConfidence))")
                .foregroundStyle(appModel.depthConfidence == .unavailable ? .red : .green)
        }
        .foregroundStyle(.secondary)
    }

    /// Mirror flip + quick all-on/all-off bulk soloing helpers. Per-channel on/off
    /// lives on each gain label above.
    @ViewBuilder
    private var globalTogglesSection: some View {
        HStack(spacing: 6) {
            chip("mirror", debugBinding(\.mirrored))
            actionChip("all on")  { setAllChannels(true) }
            actionChip("all off") { setAllChannels(false) }
        }
    }

    /// Quaternion head-render knobs (Front Face / TrueDepth path). Distinct block —
    /// these supersede the per-axis Euler gains above when a head quaternion is live.
    /// `axis map` steps through the 24 octahedral candidates so the screen→figure
    /// mapping is dialed by eye; `mirror` flips left/right; `gain`/`max°` set feel.
    @ViewBuilder
    private var quaternionHeadSection: some View {
        sectionHeader("QUAT HEAD · Front Face",
                      reset: {
                          headRotationGain = Bind.headRotationGainDefault
                          headRotationMaxAngle = Bind.headRotationMaxAngleDegreesDefault
                          basisIndex = Bind.headRenderBasisIndexDefault
                      },
                      isDefault: headRotationGain == Bind.headRotationGainDefault
                              && headRotationMaxAngle == Bind.headRotationMaxAngleDegreesDefault
                              && basisIndex == Bind.headRenderBasisIndexDefault)

        // Uniform rotation-angle gain (1.0 faithful) + total-angle clamp (degrees).
        gainRow("gain", value: $headRotationGain,     range: Self.headRotGainRange, step: 0.05, decimals: 2)
        gainRow("max°", value: $headRotationMaxAngle, range: Self.headRotMaxRange,  step: 1,    decimals: 0)

        // Axis-map stepper: walk the 24 candidate bases until a TURN→yaw, NOD→pitch,
        // TILT→roll all read correctly. Wraps at both ends.
        HStack(spacing: 6) {
            Text("axis map").foregroundStyle(.secondary).frame(width: 54, alignment: .leading)
            Button("−") { stepBasis(-1) }
                .buttonStyle(.plain).foregroundStyle(.blue)
                .frame(width: 24)
            Text("\(basisIndex) / \(Bind.headRenderBasisCandidates.count)")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
            Button("+") { stepBasis(1) }
                .buttonStyle(.plain).foregroundStyle(.blue)
                .frame(width: 24)
        }

        HStack(spacing: 6) {
            chip("mirror", debugBinding(\.mirrored))
            Spacer(minLength: 0)
        }

        Text("step axis map until turn→yaw, nod→pitch, tilt→roll; toggle mirror if L/R is flipped")
            .font(.caption2).foregroundStyle(.secondary)
    }

    /// Wrap-around step of the basis index across the 24 candidates, writing through
    /// to the live binding so the figure updates next frame (no rebuild).
    private func stepBasis(_ delta: Int) {
        let count = Bind.headRenderBasisCandidates.count
        guard count > 0 else { return }
        basisIndex = ((basisIndex + delta) % count + count) % count
    }

    var body: some View {
        let styled = VStack(alignment: .leading, spacing: 10) {
            // Touch channelTick so the body re-renders when a toggle/solo/all-off
            // mutates the non-observable static debug flags (see its declaration).
            let _ = channelTick

            calibrationSection

            Divider().overlay(Color.white.opacity(0.2))

            headYawSection

            Divider().overlay(Color.white.opacity(0.2))

            // ── 2D posture display gains ──────────────────────────────
            postureGainsHeader
            postureGainSliders
            postureDiagnostics

            Divider().overlay(Color.white.opacity(0.2))

            // ── Quaternion head (Front Face) knobs ────────────────────
            quaternionHeadSection

            Divider().overlay(Color.white.opacity(0.2))

            globalTogglesSection
        }
        .font(.system(.caption, design: .monospaced))
        .padding(8)
        .frame(maxWidth: 260)
        .background(.ultraThinMaterial)
        .cornerRadius(8)

        // The knob write-throughs are split across two intermediate bindings on
        // purpose: as one ~14-long `.onChange` chain the type-checker timed out.
        // Each `let`/`return` boundary commits to a concrete type, so the solver
        // never faces the whole chain at once.
        let half = styled
            .onChange(of: calibration)   { _, v in HeadYawTuning.oneEarCalibration = v }
            .onChange(of: sideLeanGain)  { _, v in Bind.leanRadiansPerMeter = v }
            .onChange(of: headYawGain)   { _, v in Bind.headYawGain = v }
            .onChange(of: headPitchGain) { _, v in Bind.headPitchGain = v }
            .onChange(of: nodDownBoost)  { _, v in Bind.headPitchDownBoost = v }
            .onChange(of: headRollGain)  { _, v in Bind.headRollGain = v }
            .onChange(of: scaleGain)     { _, v in PostureVisualizationViewModel.Mapping.forwardCreepScaleFactor = Double(v) }
        let most = half
            .onChange(of: leanTurnAtten) { _, v in Bind.leanTurnAttenPower = v }
            .onChange(of: turnDecouple)  { _, v in Bind.turnTiltDecouple = v }
            .onChange(of: tiltFade)      { _, v in Bind.activeTiltTurnFadePower = v }
            .onChange(of: smoothing)     { _, v in Bind.orientationSmoothTime = v }
            .onChange(of: jitterFloor)   { _, v in HeadAngleFilterTuning.minCutoff = v }
            .onChange(of: jitterCatchup) { _, v in HeadAngleFilterTuning.beta = v }
        return most
            .onChange(of: headRotationGain)     { _, v in Bind.headRotationGain = v }
            .onChange(of: headRotationMaxAngle) { _, v in Bind.headRotationMaxAngleDegrees = v }
            .onChange(of: basisIndex)           { _, v in Bind.headRenderBasisIndex = v }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Visualization tuning")
    }

    /// Two-way binding onto a `DebugChannels` flag (a mutable static struct, so we
    /// read/write through the key path; the scene reads `debug` every frame, so a
    /// toggle takes effect immediately — no rebuild).
    private func debugBinding(_ keyPath: WritableKeyPath<PostureVisualizationBinding.DebugChannels, Bool>) -> Binding<Bool> {
        Binding(
            get: { PostureVisualizationBinding.debug[keyPath: keyPath] },
            set: { PostureVisualizationBinding.debug[keyPath: keyPath] = $0 }
        )
    }

    /// A compact tap-to-toggle channel chip — green when the channel is live.
    @ViewBuilder
    private func chip(_ label: String, _ on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            Text(label)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(on.wrappedValue ? Color.green.opacity(0.35) : Color.white.opacity(0.12),
                            in: Capsule())
                .foregroundStyle(on.wrappedValue ? .green : .secondary)
        }
        .buttonStyle(.plain)
    }

    /// A momentary action chip (not a toggle) — for all-on / all-off helpers.
    @ViewBuilder
    private func actionChip(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.white.opacity(0.12), in: Capsule())
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    /// Flip every tunable 2D-posture channel on or off at once (the per-gain
    /// toggles' bulk control), for quick soloing.
    private func setAllChannels(_ on: Bool) {
        PostureVisualizationBinding.debug.sideLean = on
        PostureVisualizationBinding.debug.headYaw = on
        PostureVisualizationBinding.debug.headPitch = on
        PostureVisualizationBinding.debug.headRoll = on
        PostureVisualizationBinding.debug.assemblyScale = on
        channelTick += 1
    }

    /// SOLO one 2D-posture channel: every tunable channel off, then this one on —
    /// one tap to answer "does this posture work on its own?". The depth-only
    /// channels (torso-turn / forward-lean) aren't in the set, so a 2D solo can't
    /// accidentally leave a LiDAR channel live.
    private func soloChannel(_ keyPath: WritableKeyPath<PostureVisualizationBinding.DebugChannels, Bool>) {
        setAllChannels(false)
        PostureVisualizationBinding.debug[keyPath: keyPath] = true
        channelTick += 1
    }

    /// Short coloured label for the live calibration state.
    private func calibLabel(_ s: CalibrationStatus) -> (text: String, tint: Color) {
        switch s {
        case .waiting:            return ("waiting — hold still", .orange)
        case .countdown(let n):   return ("countdown \(n)", .yellow)
        case .sampling:           return ("sampling…", .blue)
        case .validating:         return ("validating…", .blue)
        case .success:            return ("calibrated ✓", .green)
        case .failed(let m):      return ("failed: \(m)", .red)
        }
    }

    /// A subsection title with a right-aligned reset that disables at default.
    @ViewBuilder
    private func sectionHeader(_ title: String, reset: @escaping () -> Void, isDefault: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title).fontWeight(.semibold)
            Spacer(minLength: 12)
            Button("reset", action: reset)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .disabled(isDefault)
        }
    }

    /// One labelled slider + numeric value. `decimals` keeps the readout aligned.
    /// When `enabled` is supplied the label becomes a tap-to-toggle for that
    /// channel — green = live, dim = off — so a gain can be isolated in place
    /// (tap others off until the wrong behaviour disappears). The row dims and the
    /// slider is held while off, but its value is preserved for when it's back on.
    @ViewBuilder
    private func gainRow(_ label: String,
                         value: Binding<Float>,
                         range: ClosedRange<Float>,
                         step: Float,
                         decimals: Int,
                         enabled: Binding<Bool>? = nil,
                         solo: (() -> Void)? = nil) -> some View {
        let isOn = enabled?.wrappedValue ?? true
        HStack(spacing: 6) {
            if let enabled {
                Button { enabled.wrappedValue.toggle(); channelTick += 1 } label: {
                    Text(label)
                        .foregroundStyle(isOn ? .green : .secondary)
                        .frame(width: 54, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                Text(label).foregroundStyle(.secondary).frame(width: 54, alignment: .leading)
            }
            Slider(value: value, in: range, step: step)
                .tint(isOn ? .green : .gray)
                .disabled(!isOn)
            Text(String(format: "%+.\(decimals)f", value.wrappedValue))
                .frame(width: 40, alignment: .trailing)
            if let solo {
                Button(action: solo) {
                    Text("iso")
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(isOn ? 1 : 0.45)
    }
}

#Preview {
    PostureVisualizationCalibrationOverlay(viewModel: PostureVisualizationViewModel(), appModel: AppModel())
        .padding()
        .background(Color(white: 0.06))
}
#endif
