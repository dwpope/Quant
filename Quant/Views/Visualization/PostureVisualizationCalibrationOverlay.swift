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

    private typealias Bind = PostureVisualizationBinding

    /// Sources of truth for the sliders. Each backing knob is a plain `static var`
    /// (not observable), so we drive it from `@State` and write through on change
    /// rather than binding to it directly.
    @State private var calibration: Float = HeadYawTuning.oneEarCalibration
    @State private var sideLeanGain: Float = Bind.leanRadiansPerMeter
    @State private var fwdLeanGain: Float = Bind.forwardLeanRadiansPerMeter

    /// Head-yaw `k` bounds. Spans well below/above the device-tuned default (≈8.0)
    /// so a flatter mapping and headroom past it are both reachable without code
    /// edits (the first device pass railed at the old 6.0 max — keep the optimum
    /// off the rail so it stays verifiable).
    private static let yawRange: ClosedRange<Float> = 1.0...12.0

    /// Lean-gain bounds. **Signed**, straddling 0, so the same slider both flips
    /// the lean direction (slide past 0) and sets its intensity. Wide because the
    /// lean signal is a small normalized shoulder shift (~0.05–0.1) attenuated ×0.1
    /// by the legacy points→metres chain, so visible tilt needs a large gain (the
    /// output is capped at `leanCapRadians`, so over-driving just saturates).
    private static let leanRange: ClosedRange<Float> = -100.0...100.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

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

            // ── Lean ──────────────────────────────────────────────────
            sectionHeader("LEAN GAINS  rad/m",
                          reset: {
                              sideLeanGain = Bind.leanRadiansPerMeterDefault
                              fwdLeanGain = Bind.forwardLeanRadiansPerMeterDefault
                          },
                          isDefault: sideLeanGain == Bind.leanRadiansPerMeterDefault
                                  && fwdLeanGain == Bind.forwardLeanRadiansPerMeterDefault)

            // Signed: slide past 0 to flip direction, away from 0 for intensity.
            gainRow("side", value: $sideLeanGain, range: Self.leanRange, step: 0.25, decimals: 2)
            gainRow("fwd",  value: $fwdLeanGain,  range: Self.leanRange, step: 0.25, decimals: 2)

            // Live raw lean inputs — for orientation while you lean to test sign.
            HStack(spacing: 10) {
                Text(String(format: "latLean %+.2f", viewModel.rawLateralLean))
                Text(String(format: "fwd %+.2f", viewModel.rawHeadForwardOffset))
            }
            .foregroundStyle(.secondary)
            Text("lean left/right & fwd/back; flip a sign if it reads backwards")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(8)
        .frame(maxWidth: 260)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .onChange(of: calibration) { _, v in HeadYawTuning.oneEarCalibration = v }
        .onChange(of: sideLeanGain) { _, v in Bind.leanRadiansPerMeter = v }
        .onChange(of: fwdLeanGain)  { _, v in Bind.forwardLeanRadiansPerMeter = v }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Visualization tuning")
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
    PostureVisualizationCalibrationOverlay(viewModel: PostureVisualizationViewModel())
        .padding()
        .background(Color(white: 0.06))
}
#endif
