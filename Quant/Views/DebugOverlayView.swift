//
//  DebugOverlayView.swift
//  Quant
//
//  Created for Ticket 1.4 - Debug UI v1 (Minimal)
//

import SwiftUI
import PostureLogic

struct DebugOverlayView: View {
    @ObservedObject var appModel: AppModel

    /// Filename of the most recently exported session, shown after a recording stops so it is
    /// clear something was actually written and retrievable.
    @State private var lastExport: URL?

    /// True while a Jev call is in flight, so the button cannot be double-tapped into two
    /// concurrent requests against a paid API.
    @State private var jevBusy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Camera mode
            HStack(spacing: 4) {
                Image(systemName: appModel.cameraMode == .rearDepth ? "camera.fill" : "camera.rotate")
                    .font(.system(size: 10))
                Text("Cam: \(appModel.cameraMode.rawValue)")
            }

            // Mode indicator with color
            HStack(spacing: 4) {
                Circle()
                    .fill(modeColor)
                    .frame(width: 6, height: 6)
                Text("Mode: \(appModel.currentMode.rawValue)")
            }

            // Depth confidence with icon
            HStack(spacing: 4) {
                depthIcon
                Text("Depth: \(appModel.depthConfidence.rawValue)")
            }

            // Tracking quality with color
            HStack(spacing: 4) {
                Circle()
                    .fill(trackingColor)
                    .frame(width: 6, height: 6)
                Text("Tracking: \(appModel.trackingQuality.rawValue)")
            }

            // Pose detection diagnostics
            Text("Pose conf: \(appModel.poseConfidence, specifier: "%.2f")")
            Text("Keypoints: \(appModel.poseKeypointCount)")
            Text("Missing: \(appModel.missingCriticalJoints)")

            // FPS
            Text("FPS: \(appModel.fps, specifier: "%.1f")")

            // Thermal level
            if appModel.thermalLevel != .nominal {
                HStack(spacing: 4) {
                    Image(systemName: "thermometer.sun.fill")
                        .foregroundStyle(appModel.thermalLevel == .critical ? .red : .orange)
                        .font(.system(size: 10))
                    Text("Thermal: \(thermalLabel)")
                }
            }

            Divider()

            // Posture state with color indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(postureColor)
                    .frame(width: 6, height: 6)
                Text("Posture: \(postureLabel)")
            }

            Divider()

            // Nudge decision with color indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(nudgeColor)
                    .frame(width: 6, height: 6)
                Text("Nudge: \(nudgeLabel)")
            }

            // Audio feedback status (Ticket 4.2)
            // Shows whether the audio cue is enabled and how many times it has played.
            // Useful for verifying that nudges actually trigger audio during testing.
            HStack(spacing: 4) {
                Image(systemName: appModel.audioService.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .foregroundStyle(appModel.audioService.isEnabled ? .green : .red)
                    .font(.system(size: 10))
                Text("Audio: \(audioStatusLabel)")
            }

            // Watch connectivity status (Ticket 4.4)
            HStack(spacing: 4) {
                Image(systemName: appModel.watchService.isPaired ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                    .foregroundStyle(appModel.watchService.isReachable ? .green : (appModel.watchService.isPaired ? .yellow : .red))
                    .font(.system(size: 10))
                Text("Watch: \(watchStatusLabel)")
            }

            Divider()

            // Sip detector state
            let sipDebug = appModel.sipDetector.debugState
            HStack(spacing: 4) {
                Circle()
                    .fill(sipStateColor(sipDebug["state"] as? String))
                    .frame(width: 6, height: 6)
                Text("Sip: \(sipDebug["state"] as? String ?? "?")")
            }
            Text("Prox: \(sipDebug["proximityScore"] as? String ?? "?")  Vel: \(sipDebug["velocityScore"] as? String ?? "?")")
            Text("Sips today: \(appModel.sipStore.sipCount)")

            // Sip thresholds (current, may be calibrated or default)
            let st = appModel.sipDetector.thresholds
            Text("Thr prox: \(st.proximityThreshold, specifier: "%.3f")  vel: \(st.velocityThreshold, specifier: "%.4f")")
            Text("Thr dur: \(st.minDuration, specifier: "%.1f")–\(st.maxDuration, specifier: "%.1f")s  cd: \(st.cooldownDuration, specifier: "%.0f")s")

            if appModel.isTrainingModeEnabled {
                Text("Training buffer: \(appModel.sipTrainingBuffer.frames.count)f")
                Text("Pending labels: \(appModel.activeSipLabelItem == nil ? 0 : 1)")
            }

            Divider()

            // MARK: - Posture session recording (Jev Step 3a)
            //
            // `AppModel.startRecording()`/`stopRecording()` and `RecorderService.addTag` were
            // written, tested, and then never called from anywhere in the app — so no posture
            // session had ever been recorded and no posture label had ever been captured. This
            // is the missing trigger. All logic lives in AppModel, which is unit-tested in
            // QuantTests/RecordingWiringTests; this view only calls it.
            HStack(spacing: 6) {
                Button(appModel.isRecording ? "Stop rec" : "Record") {
                    if appModel.isRecording {
                        lastExport = appModel.stopRecording()
                    } else {
                        lastExport = nil
                        appModel.startRecording()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(appModel.isRecording ? .red : .accentColor)

                if appModel.isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text("REC")
                }
            }

            if appModel.isRecording {
                // Surfaced while it can still be acted on: a session recorded without a
                // baseline can never be replayed against the threshold engine, and the
                // baseline cannot be reconstructed after the fact. If this warns, recalibrate
                // before recording anything worth keeping.
                if appModel.baseline == nil {
                    Text("no baseline - not replayable")
                        .foregroundStyle(.orange)
                } else {
                    Text("baseline captured")
                        .foregroundStyle(.secondary)
                }

                // A Menu rather than a row of six buttons: the HUD column is narrow, and a
                // crowded HStack compresses text controls to one character wide (see the
                // haptic picker in ContentView for what that looks like).
                Menu("Tag posture...") {
                    ForEach(TagLabel.allCases, id: \.self) { label in
                        Button(label.rawValue) { appModel.tagCurrentSession(label) }
                    }
                }
                .menuStyle(.borderlessButton)
            }

            if let lastExport {
                Text("saved \(lastExport.lastPathComponent)")
                    .foregroundStyle(.green)
            }

            Divider()

            // MARK: - Jev classifier (step 3b, opt-in, off by default)
            //
            // This SHIPS to TestFlight. The `#if DEBUG` gate around it was removed on 2026-09-24
            // so the experiment can be run on a device remotely — so a tester can reach this
            // control, and enabling it sends camera-derived numbers to a US-hosted service.
            //
            // The protection is no longer structural, it is a default: `useJevClassifier` is
            // false until someone flips this switch, and the README's privacy section says so in
            // user-facing terms. Nothing is sent on launch, on calibration, or on any automatic
            // schedule — only on an explicit tap of "Classify now".
            //
            // Still true and worth keeping: no credential ships. The Worker owns the TypeSafe
            // token, so what a shipped binary exposes is an endpoint URL, never a key.
            //
            // Manual trigger rather than a timer: Dave is present and IS the ground truth, so a
            // classification is most useful the moment he has deliberately assumed a posture.
            // An auto-interval can come later; it is not what makes the first experiment useful.
            Toggle("Jev classifier", isOn: $appModel.useJevClassifier)
                .toggleStyle(.switch)
                .controlSize(.mini)

            if appModel.useJevClassifier {
                HStack(spacing: 6) {
                    Button(jevBusy ? "..." : "Classify now") {
                        jevBusy = true
                        Task {
                            await appModel.classifyWithJevIfDue()
                            jevBusy = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(jevBusy)

                    Text("thr: \(thresholdSummary)")
                        .foregroundStyle(.secondary)
                }

                // Why the button will do nothing, shown BEFORE it is tapped. `jevGate` is a pure
                // query precisely so it can be read from here on every redraw.
                if case .ready = appModel.jevGate() {
                    EmptyView()
                } else {
                    Text(appModel.jevGate().message)
                        .foregroundStyle(.orange)
                }

                // Deliberately labelled as two different kinds of answer. The threshold engine
                // reports a temporal STATE (good/drifting/bad); Jev reports a morphological
                // CLASS (slouch/lean/chair_swivel). Rendering them as a like-for-like comparison
                // would be a category error, so the row says which is which and the adjudication
                // is left to the human.
                if let verdict = appModel.latestJevVerdict {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(jevClassColor(verdict.posture))
                            .frame(width: 6, height: 6)
                        Text("jev: \(verdict.posture) \(Int((verdict.confidence * 100).rounded()))%")
                        if let at = appModel.latestJevVerdictAt {
                            // Surfaced because the call is interval-driven and takes 130-475ms,
                            // so this verdict is always from an older frame than the threshold
                            // state beside it.
                            Text(String(format: "%.0fs old", Date().timeIntervalSince(at)))
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(topProbabilities(verdict), id: \.key) { entry in
                        HStack(spacing: 0) {
                            Text(entry.key)
                                .frame(width: 90, alignment: .leading)
                            Text(String(format: "%.2f", entry.value))
                                .frame(width: 45, alignment: .trailing)
                        }
                        .foregroundStyle(.secondary)
                    }

                    // The one-tap adjudication. This IS step 3c's labelling affordance, not a
                    // throwaway debug control, which is why the record it writes carries the
                    // payload and the baseline rather than just a preference.
                    if let id = appModel.jevComparisonStore.comparisons.last?.id {
                        HStack(spacing: 4) {
                            Button("jev ok") {
                                appModel.jevComparisonStore.setUserVerdict(
                                    id: id, verdict: .jevWasRight, trueClass: nil)
                            }
                            Button("thr ok") {
                                appModel.jevComparisonStore.setUserVerdict(
                                    id: id, verdict: .thresholdsWereRight, trueClass: nil)
                            }
                            Menu("both wrong") {
                                ForEach(TagLabel.allCases, id: \.self) { label in
                                    Button(label.rawValue) {
                                        appModel.jevComparisonStore.setUserVerdict(
                                            id: id, verdict: .bothWrong, trueClass: label)
                                    }
                                }
                            }
                            .menuStyle(.borderlessButton)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    Text("judged \(appModel.jevComparisonStore.adjudicatedCount)/\(appModel.jevComparisonStore.comparisons.count)")
                        .foregroundStyle(.secondary)
                }

                if let error = appModel.latestJevError {
                    Text("jev: \(error)")
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            // Column headers
            HStack(spacing: 0) {
                Text("Metric")
                    .frame(width: 70, alignment: .leading)
                Text("Raw")
                    .frame(width: 55, alignment: .trailing)
                Text("Cal")
                    .frame(width: 55, alignment: .trailing)
            }
            .fontWeight(.semibold)

            // Head Y — raw absolute position vs calibrated delta (headDrop)
            HStack(spacing: 0) {
                Text("Head Y")
                    .frame(width: 70, alignment: .leading)
                Text(poseScalar(appModel.latestSample?.headPosition.y, "%.3f"))
                    .frame(width: 55, alignment: .trailing)
                Text(metricValue(appModel.latestMetrics?.headDrop))
                    .frame(width: 55, alignment: .trailing)
                    .foregroundStyle(metricColor(appModel.latestMetrics?.headDrop,
                                                  threshold: appModel.postureThresholds.headDropThreshold))
            }

            // Shoulder Width — raw absolute vs calibrated delta (forwardCreep)
            HStack(spacing: 0) {
                Text("Fwd Crp")
                    .frame(width: 70, alignment: .leading)
                Text(poseScalar(appModel.latestSample?.shoulderWidthRaw, "%.3f"))
                    .frame(width: 55, alignment: .trailing)
                Text(metricValue(appModel.latestMetrics?.forwardCreep))
                    .frame(width: 55, alignment: .trailing)
                    .foregroundStyle(metricColor(appModel.latestMetrics?.forwardCreep,
                                                  threshold: appModel.postureThresholds.forwardCreepThreshold))
            }

            // Torso Angle — raw absolute vs calibrated delta (shoulderRounding)
            HStack(spacing: 0) {
                Text("Torso")
                    .frame(width: 70, alignment: .leading)
                Text(poseAngle(appModel.latestSample?.torsoAngle))
                    .frame(width: 55, alignment: .trailing)
                Text(metricValue(appModel.latestMetrics?.shoulderRounding, suffix: "°"))
                    .frame(width: 55, alignment: .trailing)
                    .foregroundStyle(metricColor(appModel.latestMetrics?.shoulderRounding,
                                                  threshold: appModel.postureThresholds.shoulderRoundingThreshold))
            }

            // Lateral Lean — raw shoulder midpoint X vs calibrated delta
            HStack(spacing: 0) {
                Text("Lean")
                    .frame(width: 70, alignment: .leading)
                Text(poseScalar(appModel.latestSample?.shoulderMidpoint.x, "%.3f"))
                    .frame(width: 55, alignment: .trailing)
                Text(metricValue(appModel.latestMetrics?.lateralLean))
                    .frame(width: 55, alignment: .trailing)
                    .foregroundStyle(metricColor(appModel.latestMetrics?.lateralLean,
                                                  threshold: appModel.postureThresholds.sideLeanThreshold))
            }

            // Twist — raw absolute vs calibrated
            HStack(spacing: 0) {
                Text("Twist")
                    .frame(width: 70, alignment: .leading)
                Text(poseAngle(appModel.latestSample?.shoulderTwist))
                    .frame(width: 55, alignment: .trailing)
                Text(metricValue(appModel.latestMetrics?.twist, suffix: "°"))
                    .frame(width: 55, alignment: .trailing)
                    .foregroundStyle(metricColor(appModel.latestMetrics?.twist,
                                                  threshold: appModel.postureThresholds.twistThreshold))
            }

            Divider()

            // Head angles — true head geometry from facial keypoints
            // (PoseSample.head*, degrees). Raw on-device readout for Stage 1b
            // tuning; there is no calibrated head metric yet (head-posture judging
            // is a future stage), so the Cal column is intentionally blank.
            HStack(spacing: 0) {
                Text("Head Yaw")
                    .frame(width: 70, alignment: .leading)
                Text(poseAngle(appModel.latestSample?.headYaw))
                    .frame(width: 55, alignment: .trailing)
                Text("—")
                    .frame(width: 55, alignment: .trailing)
            }
            HStack(spacing: 0) {
                Text("Head Pit")
                    .frame(width: 70, alignment: .leading)
                Text(poseAngle(appModel.latestSample?.headPitch))
                    .frame(width: 55, alignment: .trailing)
                Text("—")
                    .frame(width: 55, alignment: .trailing)
            }
            HStack(spacing: 0) {
                Text("Head Rol")
                    .frame(width: 70, alignment: .leading)
                Text(poseAngle(appModel.latestSample?.headRoll))
                    .frame(width: 55, alignment: .trailing)
                Text("—")
                    .frame(width: 55, alignment: .trailing)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    // MARK: - Posture State Display

    /// Color indicator for the current posture state:
    /// - Green = good posture
    /// - Yellow = drifting (starting to slouch, but not long enough to nudge)
    /// - Red = bad (sustained poor posture)
    /// - Gray = absent or calibrating (not actively tracking)
    private var postureColor: Color {
        switch appModel.postureState {
        case .good:
            return .green
        case .drifting:
            return .yellow
        case .bad:
            return .red
        case .absent, .calibrating:
            return .gray
        }
    }

    private var thermalLabel: String {
        switch appModel.thermalLevel {
        case .nominal: return "Nominal"
        case .fair: return "Fair (5 FPS)"
        case .serious: return "Serious (3 FPS)"
        case .critical: return "Critical (paused)"
        }
    }

    /// Human-readable label for the posture state, including timing info
    /// for drifting and bad states so you can watch the state machine in action.
    private var postureLabel: String {
        switch appModel.postureState {
        case .absent:
            return "Absent"
        case .calibrating:
            return "Calibrating"
        case .good:
            return "Good"
        case .drifting(let since):
            let duration = Date().timeIntervalSince1970 - since
            return String(format: "Drifting (%.0fs)", duration)
        case .bad(let since):
            let duration = Date().timeIntervalSince1970 - since
            return String(format: "Bad (%.0fs)", duration)
        }
    }

    // MARK: - Nudge Decision Display

    /// Color indicator for the nudge decision:
    /// - Red = fire! A nudge is being delivered right now.
    /// - Orange = pending — bad posture detected, counting down.
    /// - Yellow = suppressed — would nudge but blocked by a rule.
    /// - Gray = none — nothing to report (posture is fine).
    private var nudgeColor: Color {
        switch appModel.nudgeDecision {
        case .fire:
            return .red
        case .pending:
            return .orange
        case .suppressed:
            return .yellow
        case .none:
            return .gray
        }
    }

    /// Human-readable label for the nudge decision.
    /// Shows the reason and countdown for pending/suppressed states
    /// so you can watch the nudge logic working in real time.
    private var nudgeLabel: String {
        switch appModel.nudgeDecision {
        case .none:
            return "None"
        case .fire(let reason):
            return "FIRE (\(reason.rawValue))"
        case .pending(_, let remaining):
            return String(format: "Pending (%.0fs)", remaining)
        case .suppressed(let reason):
            return "Suppressed (\(reason.rawValue))"
        }
    }

    /// Human-readable label for the audio feedback status.
    ///
    /// Shows one of:
    /// - "Off" — audio feedback is disabled
    /// - "Ready" — enabled but hasn't played yet this session
    /// - "Played (N)" — enabled and has played N times this session
    ///
    /// This helps during testing: you can trigger a nudge and immediately
    /// see the play count increment to confirm audio delivery worked.
    private var audioStatusLabel: String {
        if !appModel.audioService.isEnabled {
            return "Off"
        }
        if appModel.audioService.totalPlays == 0 {
            return "Ready"
        }
        return "Played (\(appModel.audioService.totalPlays))"
    }

    /// Human-readable label for the Watch connectivity status.
    ///
    /// Shows one of:
    /// - "Unpaired" — no Watch paired with this iPhone
    /// - "Paired" — Watch paired but not currently reachable
    /// - "Reachable" — Watch paired and reachable, no nudges sent yet
    /// - "Sent (N)" — Watch reachable and N nudges sent this session
    private var watchStatusLabel: String {
        if !appModel.watchService.isPaired {
            return "Unpaired"
        }
        if !appModel.watchService.isReachable {
            return "Paired"
        }
        if appModel.watchService.totalSent == 0 {
            return "Reachable"
        }
        return "Sent (\(appModel.watchService.totalSent))"
    }

    private var modeColor: Color {
        switch appModel.currentMode {
        case .depthFusion:
            return .green
        case .twoDOnly:
            return .orange
        }
    }

    private var trackingColor: Color {
        switch appModel.trackingQuality {
        case .good:
            return .green
        case .degraded:
            return .orange
        case .lost:
            return .red
        }
    }

    private func posePair(_ v: SIMD3<Float>?) -> String {
        guard let v = v else { return "(--, --)" }
        return String(format: "(%.2f, %.2f)", v.x, v.y)
    }

    private func poseAngle(_ v: Float?) -> String {
        guard let v = v else { return "--" }
        return String(format: "%.1f°", v)
    }

    private func poseScalar(_ v: Float?, _ fmt: String) -> String {
        guard let v = v else { return "--" }
        return String(format: fmt, v)
    }

    private func metricValue(_ value: Float?, suffix: String = "") -> String {
        guard let v = value else { return "--" }
        let sign = v >= 0 ? "+" : ""
        return String(format: "\(sign)%.3f\(suffix)", v)
    }

    private func metricColor(_ value: Float?, threshold: Float) -> Color {
        guard let v = value else { return .gray }
        let ratio = abs(v) / threshold
        if ratio >= 1.0 { return .red }
        if ratio >= 0.5 { return .yellow }
        return .green
    }

    private var depthIcon: some View {
        Group {
            switch appModel.depthConfidence {
            case .high:
                Image(systemName: "l.joystick.tilt.up.fill")
                    .foregroundStyle(.green)
            case .medium:
                Image(systemName: "l.joystick.tilt.up")
                    .foregroundStyle(.yellow)
            case .low:
                Image(systemName: "l.joystick.tilt.down")
                    .foregroundStyle(.orange)
            case .unavailable:
                Image(systemName: "l.joystick")
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 10))
    }

    /// The threshold side, compressed to one token. Not a class — a temporal state.
    private var thresholdSummary: String {
        switch appModel.postureState {
        case .absent:              return "absent"
        case .calibrating:         return "calib"
        case .good:                return "good"
        case .drifting(let since): return String(format: "drift %.0fs", Date().timeIntervalSince1970 - since)
        case .bad(let since):      return String(format: "bad %.0fs", Date().timeIntervalSince1970 - since)
        }
    }

    /// Green for the two classes that mean "not bad posture" — including chair_swivel, which is
    /// the whole point of the experiment: the lean metric is documented as flagging a swivel as
    /// bad, so seeing it come back green here is the single most informative observation.
    private func jevClassColor(_ posture: String) -> Color {
        switch posture {
        case "good_posture", "chair_swivel": return .green
        case "slouch", "lean":               return .red
        default:                             return .yellow
        }
    }

    private func topProbabilities(_ verdict: JevVerdict) -> [(key: String, value: Double)] {
        verdict.probabilities
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (key: $0.key, value: $0.value) }
    }

    private func sipStateColor(_ state: String?) -> Color {
        switch state {
        case "idle":      return .secondary
        case "candidate": return .yellow
        default:
            if let s = state, s.hasPrefix("cooldown") { return .blue }
            return .secondary
        }
    }
}

#Preview {
    DebugOverlayView(appModel: AppModel())
}
