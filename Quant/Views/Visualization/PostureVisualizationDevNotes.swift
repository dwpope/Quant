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

    static let lastUpdated = "2026-06-19"

    /// What this tuning session has already changed.
    static let changes: [String] = [
        "W FIX, take 2 — FADE not ADD (2026-06-19): the additive turn→nod decouple couldn't flatten the W on device (raising it bulged the mid-turn, both signs worse) — its fixed sin|yaw| shape didn't match the device's phantom, and an additive term overshoots. Switched to a MULTIPLICATIVE knob: tiltTurnFadePower = exponent on the cos(yaw) tilt-fade (yawAtten = cos(yaw)^p), default 2.0. >1 fades the phantom nod/tilt harder as the head turns — monotone, can only drive toward flat, CAN'T bulge. Trade: also fades a real nod when turned, so a circle flattens slightly at its L/R (set 1.0 for fully round + full W, ~4 for flat turn). 'turn↓tilt' slider (1–6). turnTiltDecouple now defaults 0 (off), slider kept for a future shape-matched model. Fades phantom ROLL too (one knob, both axes).",
        "TURN→NOD DECOUPLE (2026-06-19): a pure left↔right sweep traced a 'W' — 2D pose cross-couples a turn into a phantom nod (~−20° pitch), and the cos(yaw) fade only cancels it at the turn extremes, so the residual peaks at mid-turn (dip mid-left + mid-right = W). Fix: Bind.turnTiltDecouple adds a turn-correlated pitch bias (∝ sin|yaw|, even) to the RAW pitch before shapeHeadTilt, riding the same pipeline as the phantom. Additive + yaw-keyed so it does NOT scale down a real nod (unlike strengthening the fade) — kills the W AND keeps the circle round. 'turn→nod' slider, SIGNED (-0.6…0.6 rad @ full turn), default 0.15 = est. starting point, NOT device-confirmed: dial flat, flip sign if the W deepens. (The 6°→2° deadzone drop earlier let more phantom through, making the W more visible — this is the proper cancel.)",
        "ROUND HEAD-CIRCLE (2026-06-19): removed the two shape-distorting asymmetries so a physical head-circle renders round. (1) headPitchDownBoost default 6.0→1.0 — an axis-asymmetric nod gain can't make a round circle (chin-down half stretched ~6× the chin-up half); the 6× emphasis is still on the 'nod ↓' slider for whoever wants forward-head emphasis over roundness. (2) headTiltDeadzoneRadians 6°→2° — yaw has no deadzone, so the wider pitch/roll deadzone made small circles start flat-horizontal then pop vertical; the new orientationSmoothing slerp absorbs the jitter the wide deadzone masked. Remaining roundness trim (turn-vs-nod SIZE match) is empirical — use the head turn / head nod sliders; the cos(yaw) tilt-fade still flattens large-circle diagonals slightly by design (anti-phantom-tilt on pure turns).",
        "MOTION SMOOTHING: head + torso orientation now temporally smoothed — apply() slerps the previous rendered pose toward the freshly-resolved target each frame (RuntimeCache.smoothedHead/smoothedTorso persist across frames) instead of snapping. Smooths the COMBINED quaternion, so a nod+turn (head 'circle') eases along the shortest arc and traces a curve rather than each axis jerking. Bind.orientationSmoothing = per-frame slerp weight (1.0 = old snap, 0.25 default ≈60 ms follow @60 fps); 'smooth' slider (0.05–1.0). Fixes the abrupt, non-fluid, non-circular feel.",
        "Head YAW is now PROPORTIONAL past ear occlusion: PoseDepthFusion.oneEarYaw scales the turn off the eyes (θ=atan(k·noseOffset/eyeSep)) instead of snapping to ±60°. Tune k live via the slider (bottom-right ▭ button) — HeadYawTuning.oneEarCalibration, device-tuned default 8.0 (anatomical ideal ≈2.7; Vision keypoints push it higher).",
        "Side lean is now DIRECTIONAL: added RawMetrics.lateralLeanSigned (no abs; abs metric kept for scoring) so the figure leans toward the real side. Confirmed good on device at gain 70 (latLean≈0.059 full lean). Twist also signed (twistSigned) BUT shoulderTwist is shoulder TILT not axial rotation, so it can't read a real twist in 2D.",
        "DEPTH-GATED CHANNELS: forward-lean pitch (headForwardOffset, depth-only) and axial twist are now gated on viewModel.depthActive (pose.depthMode==.depthFusion). Off in 2D so the figure doesn't misbehave on signals it can't see; auto-on under LiDAR. Side lean + head + scale are true 2D and stay live. NOTE: posture SCORING is fully 2D and does NOT use headForwardOffset — dropping these from the viz costs monitoring nothing (PostureEngine thresholds: forwardCreep/twist/lateralLean/headDrop/shoulderRounding).",
        "Tuning panel now focuses on the 2D-inferrable posture types: sliders for side lean, head turn (Bind.headYawGain), head nod (headPitchGain), head tilt (headRollGain), zoom (Mapping.forwardCreepScaleFactor) — all signed display gains, write-through to static vars. Depth-only fwd/twist sliders removed (channels remain in code, depth-gated). Each gain LABEL is a tap-to-toggle for its channel (green=on, dim=off) so a misbehaving gain can be isolated in place; plus mirror + all-on/all-off chips.",
        "Per-posture SOLO: each 2D gain row has an 'iso' button (soloChannel) — one tap switches every other tunable channel off and leaves only this one on, to confirm a posture works in isolation. Depth-only channels (torso-turn/forward-lean) are intentionally NOT in the solo set and not shown on the panel (they need LiDAR; 'torso turning does nothing in 2D' is by design, not a bug). A channelTick @State now nudges the panel so label/iso colours refresh immediately when the non-observable static debug flags flip.",
        "2D gains baked from device tuning (2026-06-19): side lean 70→20 (70 over-tilted), head turn -0.6 (kept), head NOD -6.0 base (reversed from +1.0; headGainRange widened to ±6), head TILT +1.0→-3.0 (reversed), zoom 0.5 (kept). All confirmed correct in isolation via the 'iso' solos.",
        "Asymmetric NOD: the forward (chin-DOWN) nod gets a separate headPitchDownBoost multiplier (default 6.0 ⇒ ≈-36 effective down — the 2D pitch signal is small so it needs a big multiplier) so a forward nod travels further than the chin-up/back move (base -6, which read fine). 'nod ↓' slider (1–8×) tunes it; gated by the same head-nod channel flag (no own toggle).",
        "Side lean is now faded by cos(headYaw)^leanTurnAttenPower (default 1.0, slider 'turn↓lean') so a CHAIR SWIVEL — which shifts the shoulder midpoint like a lean but also turns the face — cancels the lean instead of faking one. Facing camera (yaw≈0) keeps full lean; turned away cancels it. Viz-only; the same false-positive still exists in PostureEngine.lateralLean scoring (separate task).",
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
