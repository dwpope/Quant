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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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

            // Pose sample readout
            Text("Head: \(posePair(appModel.latestSample?.headPosition))")
            Text("L Shldr: \(posePair(appModel.latestSample?.leftShoulder))")
            Text("R Shldr: \(posePair(appModel.latestSample?.rightShoulder))")
            Text("Torso: \(poseAngle(appModel.latestSample?.torsoAngle))")
            Text("Twist: \(poseAngle(appModel.latestSample?.shoulderTwist))")
            Text("Shldr W: \(poseScalar(appModel.latestSample?.shoulderWidthRaw, "%.3f"))")
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
}

#Preview {
    DebugOverlayView(appModel: AppModel())
}
