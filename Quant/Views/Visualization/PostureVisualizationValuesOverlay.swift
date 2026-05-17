import SwiftUI

/// Developer-only tuning HUD for the RealityKit posture visualization.
///
/// The visualization is otherwise *purely graphical* — colour, geometry, scale
/// and opacity carry all state, by design. That makes it hard to refine the
/// `PostureVisualizationViewModel.Mapping` constants by eye: you can see the
/// head move but not *how much* signal produced *how much* motion. This panel
/// closes that gap by printing, every frame, each channel's **raw upstream
/// input** next to the **mapped display value** the binding actually applies.
///
/// It reads the same `@Published` properties the `RealityView` binds from, so
/// the numbers are guaranteed in lock-step with the entities — this is a
/// read-only mirror, never a second source of truth, and it cannot perturb the
/// scene. Toggled from `PostureVisualizationView`; not shipped to end users.
///
/// A row turns **orange** when its pre-clamp angle exceeds the per-axis cap,
/// i.e. the cap is currently clipping — the clearest cue that a `*CapDegrees`
/// (or the shared amplification) wants retuning.
struct PostureVisualizationValuesOverlay: View {

    @ObservedObject var viewModel: PostureVisualizationViewModel

    private typealias Map = PostureVisualizationViewModel.Mapping

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VIZ VALUES — raw → mapped")
                .fontWeight(.semibold)

            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 2) {
                GridRow {
                    Text("channel").gridColumnAlignment(.leading)
                    Text("raw")
                    Text("→").foregroundStyle(.secondary)
                    Text("mapped")
                }
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

                row("twist",     raw: viewModel.rawTwist,            map: viewModel.shoulderRotationDegrees, mapUnit: "°")
                row("latLean",   raw: viewModel.rawLateralLean,      map: viewModel.sideLeanOffsetPoints,    mapUnit: "pt")
                row("fwdCreep",  raw: viewModel.rawForwardCreep,     map: viewModel.assemblyScale,           mapUnit: "×", mapDecimals: 3)
                row("headFwd",   raw: viewModel.rawHeadForwardOffset, map: viewModel.headForwardOffsetPoints, mapUnit: "pt")

                // Capped angles: raw column is the *pre-clamp* amplified value;
                // a gap vs. the mapped column means the cap is clipping now.
                row("yaw",   raw: viewModel.unclampedYawDegrees,   rawUnit: "°", map: viewModel.headYawDegrees,   mapUnit: "°",
                    clipped: abs(viewModel.unclampedYawDegrees)   > Map.yawCapDegrees)
                row("pitch", raw: viewModel.unclampedPitchDegrees, rawUnit: "°", map: viewModel.headPitchDegrees, mapUnit: "°",
                    clipped: abs(viewModel.unclampedPitchDegrees) > Map.pitchCapDegrees)
                row("roll",  raw: viewModel.unclampedRollDegrees,  rawUnit: "°", map: viewModel.headRollDegrees,  mapUnit: "°",
                    clipped: abs(viewModel.unclampedRollDegrees)  > Map.rollCapDegrees)

                row("shTwist",  raw: viewModel.rawShoulderTwist, rawUnit: "°", map: nil, mapUnit: "")

                GridRow {
                    Text("opacity").gridColumnAlignment(.leading)
                    Text("—").foregroundStyle(.secondary)
                    Text("→").foregroundStyle(.secondary)
                    Text(fmt(viewModel.opacity, decimals: 2))
                }

                GridRow {
                    Text("state").gridColumnAlignment(.leading)
                    HStack(spacing: 4) {
                        Circle().fill(viewModel.stateColor).frame(width: 7, height: 7)
                        Text(viewModel.isCalibrating ? "calib" : "—")
                            .foregroundStyle(.secondary)
                    }
                    .gridCellColumns(3)
                    .gridColumnAlignment(.leading)
                }
            }
        }
        .font(.system(.caption, design: .monospaced))
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Visualization tuning values")
    }

    /// One raw→mapped line. `clipped` tints the whole row to flag a cap that is
    /// currently clamping; `map == nil` renders a raw-only channel (no mapped
    /// counterpart, e.g. an input that feeds another channel's derivation).
    @ViewBuilder
    private func row(
        _ name: String,
        raw: Double,
        rawUnit: String = "",
        rawDecimals: Int = 3,
        map: Double?,
        mapUnit: String,
        mapDecimals: Int = 1,
        clipped: Bool = false
    ) -> some View {
        GridRow {
            Text(name).gridColumnAlignment(.leading)
            Text(fmt(raw, decimals: rawDecimals) + rawUnit)
            Text("→").foregroundStyle(.secondary)
            if let map {
                Text(fmt(map, decimals: mapDecimals) + mapUnit)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(clipped ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
    }

    /// Fixed-width-ish numeric formatting; keeps signs aligned in the mono grid.
    private func fmt(_ v: Double, decimals: Int) -> String {
        String(format: "%+.\(decimals)f", v)
    }
}

#Preview {
    PostureVisualizationValuesOverlay(viewModel: PostureVisualizationViewModel())
        .padding()
        .background(Color(white: 0.06))
}
