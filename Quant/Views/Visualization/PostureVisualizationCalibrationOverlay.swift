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
    @State private var headRollGain: Float = Bind.headRollGain
    @State private var scaleGain: Float = Float(PostureVisualizationViewModel.Mapping.forwardCreepScaleFactor)

    /// Head-yaw `k` (one-ear detection calibration) bounds — device-tuned to ≈8.0.
    private static let yawRange: ClosedRange<Float> = 1.0...12.0

    /// Side-lean gain bounds. **Signed**, straddling 0, so the slider both flips
    /// direction (past 0) and sets intensity. Wide because the lean signal is a
    /// small normalized shoulder shift (~0.05–0.1) attenuated ×0.1 by the legacy
    /// points→metres chain (output capped at `leanCapRadians`, so over-driving
    /// just saturates).
    private static let leanRange: ClosedRange<Float> = -100.0...100.0

    /// Head display-gain bounds. **Signed** so each head axis can be flipped or
    /// damped/boosted; 1.0 (yaw ≈ −0.6) is the as-shaped angle.
    private static let headGainRange: ClosedRange<Float> = -3.0...3.0

    /// Proximity (lean-in) zoom bounds — unsigned; 0 = no scale response.
    private static let scaleRange: ClosedRange<Float> = 0.0...2.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Calibration ───────────────────────────────────────────
            // Lean/twist/creep are measured relative to a calibration baseline;
            // with none, they read 0 no matter the gain (head angles bypass it).
            // The viz shows no calibration prompt, so surface it here.
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

            Divider().overlay(Color.white.opacity(0.2))

            // ── Head yaw ──────────────────────────────────────────────
            sectionHeader("HEAD-YAW CALIB",
                          reset: { calibration = HeadYawTuning.oneEarCalibrationDefault },
                          isDefault: calibration == HeadYawTuning.oneEarCalibrationDefault)

            // The knob: k (E₀/d). Step matches the eyeball precision you can judge.
            gainRow("k", value: $calibration, range: Self.yawRange, step: 0.05, decimals: 2)

            // Live feedback: raw head-yaw (the signal k scales). Turn to a known
            // angle and tune k until this matches it. Only meaningful past the
            // ear-occlusion boundary — below it both ears drive the asin path.
            HStack(spacing: 6) {
                Text("rawYaw").foregroundStyle(.secondary)
                Text("→").foregroundStyle(.secondary)
                Text(String(format: "%+.1f°", viewModel.rawHeadYaw))
                    .fontWeight(.semibold)
                    .foregroundStyle(abs(viewModel.rawHeadYaw) >= 45 ? .green : .secondary)
            }
            Text("turn until one ear hides, then match the angle")
                .font(.caption2).foregroundStyle(.secondary)

            Divider().overlay(Color.white.opacity(0.2))

            // ── 2D posture display gains ──────────────────────────────
            // One slider per posture type the 2D image can infer. Depth-only
            // channels (forward-lean, axial twist) are intentionally absent.
            sectionHeader("2D POSTURE GAINS",
                          reset: {
                              sideLeanGain = Bind.leanRadiansPerMeterDefault
                              headYawGain = Bind.headYawGainDefault
                              headPitchGain = Bind.headPitchGainDefault
                              headRollGain = Bind.headRollGainDefault
                              scaleGain = Float(PostureVisualizationViewModel.Mapping.forwardCreepScaleFactorDefault)
                          },
                          isDefault: sideLeanGain == Bind.leanRadiansPerMeterDefault
                                  && headYawGain == Bind.headYawGainDefault
                                  && headPitchGain == Bind.headPitchGainDefault
                                  && headRollGain == Bind.headRollGainDefault
                                  && scaleGain == Float(PostureVisualizationViewModel.Mapping.forwardCreepScaleFactorDefault))

            // Signed gains: slide past 0 to flip direction, away from 0 for intensity.
            gainRow("side lean", value: $sideLeanGain,  range: Self.leanRange,     step: 0.5,  decimals: 1)
            gainRow("head turn", value: $headYawGain,   range: Self.headGainRange, step: 0.05, decimals: 2)
            gainRow("head nod",  value: $headPitchGain, range: Self.headGainRange, step: 0.05, decimals: 2)
            gainRow("head tilt", value: $headRollGain,  range: Self.headGainRange, step: 0.05, decimals: 2)
            gainRow("zoom",      value: $scaleGain,     range: Self.scaleRange,    step: 0.05, decimals: 2)

            // Live raw inputs (signed) for orientation while tuning.
            HStack(spacing: 10) {
                Text(String(format: "lean %+.3f", viewModel.rawLateralLean))
                Text(String(format: "yaw %+.0f°", viewModel.rawHeadYaw))
                Text(String(format: "pitch %+.0f°", viewModel.rawHeadPitch))
            }
            .foregroundStyle(.secondary)
            // Source/depth diagnostic: metrics ✗ = no baseline; depth gates the
            // (absent) forward-lean + real-twist channels.
            HStack(spacing: 8) {
                Text("metrics")
                Text(viewModel.metricsPresent ? "✓" : "✗")
                    .fontWeight(.bold)
                    .foregroundStyle(viewModel.metricsPresent ? .green : .red)
                Text("depth \(String(describing: appModel.depthConfidence))")
                    .foregroundStyle(appModel.depthConfidence == .unavailable ? .red : .green)
            }
            .foregroundStyle(.secondary)

            Divider().overlay(Color.white.opacity(0.2))

            // ── Channel isolation ─────────────────────────────────────
            // Solo one 2D channel (others off) to verify its direction in isolation.
            Text("CHANNELS  tap to toggle").fontWeight(.semibold)
            HStack(spacing: 6) {
                chip("mirror", debugBinding(\.mirrored))
                chip("lean",   debugBinding(\.sideLean))
                chip("zoom",   debugBinding(\.assemblyScale))
            }
            HStack(spacing: 6) {
                chip("yaw",    debugBinding(\.headYaw))
                chip("pitch",  debugBinding(\.headPitch))
                chip("roll",   debugBinding(\.headRoll))
            }
        }
        .font(.system(.caption, design: .monospaced))
        .padding(8)
        .frame(maxWidth: 260)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .onChange(of: calibration)   { _, v in HeadYawTuning.oneEarCalibration = v }
        .onChange(of: sideLeanGain)  { _, v in Bind.leanRadiansPerMeter = v }
        .onChange(of: headYawGain)   { _, v in Bind.headYawGain = v }
        .onChange(of: headPitchGain) { _, v in Bind.headPitchGain = v }
        .onChange(of: headRollGain)  { _, v in Bind.headRollGain = v }
        .onChange(of: scaleGain)     { _, v in PostureVisualizationViewModel.Mapping.forwardCreepScaleFactor = Double(v) }
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
    @ViewBuilder
    private func gainRow(_ label: String, value: Binding<Float>, range: ClosedRange<Float>, step: Float, decimals: Int) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.secondary)
            Slider(value: value, in: range, step: step).tint(.green)
            Text(String(format: "%+.\(decimals)f", value.wrappedValue))
                .frame(width: 46, alignment: .trailing)
        }
    }
}

#Preview {
    PostureVisualizationCalibrationOverlay(viewModel: PostureVisualizationViewModel(), appModel: AppModel())
        .padding()
        .background(Color(white: 0.06))
}
#endif
