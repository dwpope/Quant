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

    /// The scored head-drop trip point, mirrored here so the `neck` row can flag
    /// (orange) when the carriage metric is currently tripping. Matches
    /// `PostureThresholds().headDropThreshold`'s default — a debug HUD may
    /// reference the default rather than the user's live (possibly retuned) value.
    private let headDropThreshold = 0.06

    /// Live snapshot of the binding's per-channel isolation switches. Set once
    /// (Debug-only) in `PostureVisualizationView`'s scene `make`, so it is
    /// constant for the run — reading it in `body` needs no observation. In
    /// Release it is the all-on default, so `isIsolating` is false and this
    /// panel looks exactly as before (no change to the shipped HUD).
    private var debug: PostureVisualizationBinding.DebugChannels {
        PostureVisualizationBinding.debug
    }

    /// True only when at least one channel is frozen. Gates the mute/highlight
    /// styling so the un-isolated production HUD is left untouched.
    private var isIsolating: Bool {
        let d = debug
        return d.hideShoulderDisc
            || !d.shoulderRotation || !d.sideLean || !d.headForward
            || !d.headYaw || !d.headPitch || !d.headRoll
            || !d.assemblyScale || !d.opacity || !d.stateTint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("VIZ VALUES — raw → mapped")
                    .fontWeight(.semibold)
                if debug.mirrored {
                    Text("MIRROR")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.35), in: Capsule())
                }
            }
            if isIsolating {
                Text("● live · dimmed = frozen by debug")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 2) {
                GridRow {
                    Text("channel").gridColumnAlignment(.leading)
                    Text("raw")
                    Text("→").foregroundStyle(.secondary)
                    Text("mapped")
                }
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

                // HEAD — everything that translates/rotates the head sphere.
                section("HEAD")
                // LIVE head source this frame: GREEN "QUAT" = the decoupled ARFaceAnchor
                // quaternion (figure on the new passthrough); ORANGE "2D" = the legacy
                // Euler fallback (ARFace dropped / non-TrueDepth). If this flips to 2D
                // mid-turn, the snap/dip is the SOURCE HANDOFF, not the render math.
                GridRow {
                    Text("src").gridColumnAlignment(.leading)
                    Text(viewModel.headOrientationQuat != nil ? "QUAT" : "2D")
                        .fontWeight(.bold)
                        .foregroundStyle(viewModel.headOrientationQuat != nil
                            ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
                        .gridCellColumns(3)
                        .gridColumnAlignment(.leading)
                }
                // ARFace pipeline diagnostics (why src is 2D): is the app in .frontFace
                // (faceTrackingActive), did the ARFace session start, are its frames
                // arriving, and is a face ever tracked. All-zero ARFace counters with
                // mode=frontFace ⇒ the provider isn't running / not attached.
                GridRow {
                    Text("mode").gridColumnAlignment(.leading)
                    Text(PostureVisualizationBinding.faceTrackingActive ? "frontFace" : "OTHER")
                        .fontWeight(.bold)
                        .foregroundStyle(PostureVisualizationBinding.faceTrackingActive
                            ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
                        .gridCellColumns(3)
                        .gridColumnAlignment(.leading)
                }
                GridRow {
                    Text("ARFace").gridColumnAlignment(.leading)
                    Text("run:\(ARFaceTrackingService.diagSessionStarted ? "Y" : "N") "
                        + "f:\(ARFaceTrackingService.diagFramesSeen) "
                        + "trk:\(ARFaceTrackingService.diagTrackedSeen)")
                        .foregroundStyle(ARFaceTrackingService.diagTrackedSeen > 0
                            ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
                        .gridCellColumns(3)
                        .gridColumnAlignment(.leading)
                }
                // Grace counter: `since` = frames since the last tracked face (live);
                // `max` = worst gap this session. When `since` climbs orange the head
                // pose is being held from the grace window; if it exceeds the window
                // (90), src flips to 2D. Turn your head, then read `max` — that is the
                // true worst gap, which sizes the window.
                GridRow {
                    Text("gap").gridColumnAlignment(.leading)
                    Text("since:\(ARFaceTrackingService.diagFramesSinceTracked) "
                        + "max:\(ARFaceTrackingService.diagMaxSinceTracked)")
                        .foregroundStyle(ARFaceTrackingService.diagFramesSinceTracked > 0
                            ? AnyShapeStyle(.orange) : AnyShapeStyle(.green))
                        .gridCellColumns(3)
                        .gridColumnAlignment(.leading)
                }
                // Spike S1 (lean-in SNR): metric head-to-camera distance from the
                // ARFace translation the orientation path discards. Read it at
                // neutral / mild / bad and note the flicker at a held pose — this
                // decides whether distance becomes a scored lean-in signal.
                GridRow {
                    Text("dist").gridColumnAlignment(.leading)
                    Text(ARFaceTrackingService.diagHeadDistanceMeters.isNaN
                        ? "--"
                        : String(format: "%.1f cm", ARFaceTrackingService.diagHeadDistanceMeters * 100))
                        .foregroundStyle(ARFaceTrackingService.diagHeadDistanceMeters.isNaN
                            ? AnyShapeStyle(.orange) : AnyShapeStyle(.green))
                        .gridCellColumns(3)
                        .gridColumnAlignment(.leading)
                }
                row("latLean",   raw: viewModel.rawLateralLean,      map: viewModel.sideLeanOffsetPoints,    mapUnit: "pt",
                    active: debug.sideLean)
                row("headFwd",   raw: viewModel.rawHeadForwardOffset, map: viewModel.headForwardOffsetPoints, mapUnit: "pt",
                    active: debug.headForward)
                // Neck carriage → scored head-drop. raw = ear-height off the sample
                // (PoseSample.neckHeight); mapped = the baseline-relative deviation the
                // engine scores (RawMetrics.headDrop). Orange when it exceeds the
                // headDropThreshold — i.e. the neck metric is tripping *now*. This is a
                // scored 2D metric mirror, not an isolatable viz channel, so it stays
                // `active` (never dimmed) and reuses the standard clipped→orange cue.
                row("neck",      raw: viewModel.rawNeckHeight,        map: viewModel.neckDropScored,          mapUnit: "",
                    clipped: viewModel.neckDropScored > headDropThreshold)

                // Capped angles: raw column is the *pre-clamp* amplified value;
                // a gap vs. the mapped column means the cap is clipping now.
                row("yaw",   raw: viewModel.unclampedYawDegrees,   rawUnit: "°", map: viewModel.headYawDegrees,   mapUnit: "°",
                    clipped: abs(viewModel.unclampedYawDegrees)   > Map.yawCapDegrees,
                    active: debug.headYaw)
                row("pitch", raw: viewModel.unclampedPitchDegrees, rawUnit: "°", map: viewModel.headPitchDegrees, mapUnit: "°",
                    clipped: abs(viewModel.unclampedPitchDegrees) > Map.pitchCapDegrees,
                    active: debug.headPitch)
                row("roll",  raw: viewModel.unclampedRollDegrees,  rawUnit: "°", map: viewModel.headRollDegrees,  mapUnit: "°",
                    clipped: abs(viewModel.unclampedRollDegrees)  > Map.rollCapDegrees,
                    active: debug.headRoll)

                // Raw head-geometry inputs (PoseSample.head*, pre-amplify) that now
                // drive yaw/pitch/roll — the real upstream the proxies replaced.
                row("rawYaw",   raw: viewModel.rawHeadYaw,   rawUnit: "°", map: nil, mapUnit: "",
                    active: debug.headYaw)
                row("rawPitch", raw: viewModel.rawHeadPitch, rawUnit: "°", map: nil, mapUnit: "",
                    active: debug.headPitch)
                row("rawRoll",  raw: viewModel.rawHeadRoll,  rawUnit: "°", map: nil, mapUnit: "",
                    active: debug.headRoll)

                // TORSO — the shoulder disc (rotation only).
                section("TORSO")
                row("twist",     raw: viewModel.rawTwist,            map: viewModel.shoulderRotationDegrees, mapUnit: "°",
                    active: debug.shoulderRotation && !debug.hideShoulderDisc)

                // ASSEMBLY — scale/opacity/tint act on the whole rig (both).
                section("ASSEMBLY — head + torso")
                row("fwdCreep",  raw: viewModel.rawForwardCreep,     map: viewModel.assemblyScale,           mapUnit: "×", mapDecimals: 3,
                    active: debug.assemblyScale)

                GridRow {
                    nameCell("opacity", active: debug.opacity)
                    Text("—").foregroundStyle(.secondary)
                    Text("→").foregroundStyle(.secondary)
                    Text(fmt(viewModel.opacity, decimals: 2))
                }
                .opacity(isIsolating && !debug.opacity ? 0.4 : 1)
                .fontWeight(isIsolating && debug.opacity ? .semibold : .regular)

                GridRow {
                    nameCell("state", active: debug.stateTint)
                    HStack(spacing: 4) {
                        Circle().fill(viewModel.stateColor).frame(width: 7, height: 7)
                        Text(viewModel.isCalibrating ? "calib" : "—")
                            .foregroundStyle(.secondary)
                    }
                    .gridCellColumns(3)
                    .gridColumnAlignment(.leading)
                }
                .opacity(isIsolating && !debug.stateTint ? 0.4 : 1)
                .fontWeight(isIsolating && debug.stateTint ? .semibold : .regular)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Visualization tuning values")
    }

    /// A spanning section divider inside the grid (HEAD / TORSO / ASSEMBLY).
    /// One cell across all four columns so the heading sits flush-left above
    /// its group. Structural, never a channel, so it is never dimmed even while
    /// isolating — it must stay readable as the map of where you are.
    @ViewBuilder
    private func section(_ title: String) -> some View {
        GridRow {
            Text(title)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .gridCellColumns(4)
                .gridColumnAlignment(.leading)
                .padding(.top, 4)
        }
    }

    /// First grid cell: the channel name, prefixed by a green dot on the live
    /// channel (and a reserved-width clear dot on frozen ones, so columns stay
    /// aligned) while isolating. No dot at all when not isolating → unchanged.
    @ViewBuilder
    private func nameCell(_ name: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            if isIsolating {
                Circle()
                    .fill(active ? Color.green : Color.clear)
                    .frame(width: 5, height: 5)
            }
            Text(name)
        }
        .gridColumnAlignment(.leading)
    }

    /// One raw→mapped line. `clipped` tints the whole row orange to flag a cap
    /// that is currently clamping; `map == nil` renders a raw-only channel (an
    /// input that feeds another channel's derivation). `active` reflects this
    /// row's `PostureVisualizationBinding.debug` channel: while isolating, a
    /// frozen row is dimmed and bold-marked the live one; with nothing frozen
    /// every row is `active` so the appearance is identical to before.
    @ViewBuilder
    private func row(
        _ name: String,
        raw: Double,
        rawUnit: String = "",
        rawDecimals: Int = 3,
        map: Double?,
        mapUnit: String,
        mapDecimals: Int = 1,
        clipped: Bool = false,
        active: Bool = true
    ) -> some View {
        GridRow {
            nameCell(name, active: active)
            Text(fmt(raw, decimals: rawDecimals) + rawUnit)
            Text("→").foregroundStyle(.secondary)
            if let map {
                Text(fmt(map, decimals: mapDecimals) + mapUnit)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(clipped ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
        .opacity(isIsolating && !active ? 0.4 : 1)
        .fontWeight(isIsolating && active ? .semibold : .regular)
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
