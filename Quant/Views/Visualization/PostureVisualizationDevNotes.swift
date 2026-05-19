#if DEBUG
import SwiftUI

/// Dev-only changelog + open-action list for the posture-visualization tuning
/// rig. **Scaffolding, not product**: the whole file is `#if DEBUG`, so it is
/// stripped from the Release / TestFlight build the nightly auto-build ships —
/// even though that routine commits this repo. Surfaced in-app behind the ⓘ
/// button in `PostureVisualizationView` so the running session always carries
/// its own "what changed / what's left" memo across rebuilds.
///
/// Maintenance contract: whenever you change the tuning rig, add a line to
/// `changes` (and, if it opens or closes a decision, to `toAction`) and bump
/// `lastUpdated`. Keep entries terse — this is a scan target, not a doc.
enum PostureVisualizationDevNotes {

    static let lastUpdated = "2026-05-18"

    /// What this tuning session has already changed.
    static let changes: [String] = [
        "Per-channel isolation switches added (PostureVisualizationBinding.debug / DebugChannels) — freeze any channel, tune one at a time.",
        "Current debug config: shoulder disc hidden, only HEAD YAW live; every other channel frozen at rest.",
        "Tuning HUD: live channel shown green/bold, frozen channels dimmed; rows grouped HEAD / TORSO / ASSEMBLY.",
        "Left<->right MIRROR toggle added (debug.mirrored) — currently ON. Flips only side-lean, head yaw, head roll, disc twist.",
        "hideGhost + hideHeadBand switches added — currently ON: the faint baseline ghost and the z-fighting tone-divide band are removed for a clean yaw read.",
        "All of the above is #if DEBUG-gated in PostureVisualizationView -> cannot ship via TestFlight even though the repo is auto-committed.",
    ]

    /// Decisions still open / cleanup still owed.
    static let toAction: [String] = [
        "Head YAW is sourced from PoseSample.shoulderTwist, NOT real head turn. Decide whether to re-source it from a head-derived signal — a mapping change in PostureVisualizationViewModel, not a constant tweak.",
        "Head ROLL & PITCH use absolute geometry, not calibration-relative — the likely cause of the original permanently-tilted/buggy look. Consider zeroing them against the ghost baseline at calibration.",
        "Tune the remaining axes one at a time (sideLean, headForward, pitch, roll, twist); flip each flag back to true once dialled in.",
        "Decide if MIRROR is permanent product behaviour -> if so, drop the debug.mirrored guard in apply() and always call mirror(t).",
        "metersPerPoint (0.001) and the Mapping amplification/cap constants are still design starting values — confirm by eye during demo recording.",
        "When tuning is finished: reset DebugChannels to defaults and delete the #if DEBUG block in PostureVisualizationView.",
    ]
}

/// Scrollable dev-notes panel shown behind the ⓘ button. Mirrors the visual
/// language of `PostureVisualizationValuesOverlay` (monospaced, ultra-thin
/// material) so the two HUDs read as one toolset.
struct PostureVisualizationNotesOverlay: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("DEV NOTES · updated \(PostureVisualizationDevNotes.lastUpdated)")
                    .fontWeight(.semibold)

                Text("CHANGED")
                    .font(.caption2).fontWeight(.bold).foregroundStyle(.secondary)
                ForEach(Array(PostureVisualizationDevNotes.changes.enumerated()), id: \.offset) { _, line in
                    bullet("✓", line, tint: .green)
                }

                Text("TO ACTION")
                    .font(.caption2).fontWeight(.bold).foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(Array(PostureVisualizationDevNotes.toAction.enumerated()), id: \.offset) { _, line in
                    bullet("•", line, tint: .orange)
                }
            }
            .padding(10)
        }
        .font(.system(.caption2, design: .monospaced))
        .frame(maxWidth: 340, maxHeight: 420)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Visualization dev notes")
    }

    @ViewBuilder
    private func bullet(_ symbol: String, _ text: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(symbol).foregroundStyle(tint)
            Text(text)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
