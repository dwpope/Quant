#if DEBUG
import SwiftUI
import PostureLogic

/// Dev-only on-device slider for the one-ear head-yaw calibration
/// (`HeadYawTuning.oneEarCalibration`, the `k = E₀/d` factor in
/// `PoseDepthFusion.oneEarYaw`). Lets you dial the proportional turn estimate by
/// eye against known angles without a rebuild.
///
/// **Scaffolding, not product**: the whole file is `#if DEBUG`, so it is stripped
/// from Release / TestFlight (matching `PostureVisualizationDevNotes`). It writes
/// the shared `static var` directly — see the concurrency note on `HeadYawTuning`;
/// the unsynchronized scalar write from the main thread is a benign debug race.
///
/// The panel mirrors the rig's other HUDs (monospaced, ultra-thin material) and
/// shows the **live raw head-yaw** beside the knob so you see the effect as you
/// turn: occlude one ear (a strong turn), watch `rawYaw` track your real angle,
/// and nudge `k` until the figure matches. Higher `k` ⇒ a given turn reads bigger.
struct PostureVisualizationCalibrationOverlay: View {

    @ObservedObject var viewModel: PostureVisualizationViewModel

    /// Source of truth for the slider; `HeadYawTuning.oneEarCalibration` is a
    /// plain `static var` (not observable), so we drive it from `@State` and
    /// write through on change rather than binding to it directly.
    @State private var calibration: Float = HeadYawTuning.oneEarCalibration

    /// Slider bounds. Spans well below/above the device-tuned default (≈6.0) so
    /// both a flatter mapping and headroom past 6 are reachable without code edits
    /// (the first device pass railed at the old 6.0 max — keep the optimum off the
    /// rail so it stays verifiable).
    private static let range: ClosedRange<Float> = 1.0...12.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("HEAD-YAW CALIB").fontWeight(.semibold)
                Spacer(minLength: 12)
                Button("reset") { calibration = HeadYawTuning.oneEarCalibrationDefault }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .disabled(calibration == HeadYawTuning.oneEarCalibrationDefault)
            }

            // The knob: k (E₀/d). Step matches the eyeball precision you can judge.
            HStack(spacing: 8) {
                Text("k").foregroundStyle(.secondary)
                Slider(value: $calibration, in: Self.range, step: 0.05)
                    .tint(.green)
                Text(String(format: "%.2f", calibration))
                    .frame(width: 38, alignment: .trailing)
            }

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
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(8)
        .frame(maxWidth: 260)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .onChange(of: calibration) { _, newValue in
            HeadYawTuning.oneEarCalibration = newValue
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Head-yaw calibration")
    }
}

#Preview {
    PostureVisualizationCalibrationOverlay(viewModel: PostureVisualizationViewModel())
        .padding()
        .background(Color(white: 0.06))
}
#endif
