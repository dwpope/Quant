//
//  ContentView.swift
//  QuantWatch Watch App
//
//  Created by Dave Pope on 13/02/2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var sessionDelegate: WatchSessionDelegate
    @ObservedObject var wristSession = WristNudgeSession.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Slouching or not. Re-read every few seconds, so a phone that has gone
                    // quiet stops showing its last word as now.
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        PostureGlanceView(look: PostureLook(
                            sessionDelegate.postureGlance,
                            receivedAt: sessionDelegate.postureGlanceReceivedAt,
                            now: context.date), now: context.date)
                    }

                    Divider()

                    // Connection status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(sessionDelegate.isConnected ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(sessionDelegate.isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                    }

                    // Whether nudges arrive on time: the app kept running an hour at a time.
                    Text(WristNudgeSession.statusLine(for: wristSession.state))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    switch wristSession.state {
                    case .off, .unavailable:
                        Button("Keep nudges on time") { wristSession.appBecameActive() }
                            .font(.caption)
                    case .starting, .on:
                        EmptyView()
                    }

                    // Last nudge received
                    if let lastNudge = sessionDelegate.lastNudgeTime {
                        Text("Last nudge:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(lastNudge, style: .time)
                            .font(.caption)
                        if let line = sessionDelegate.lastNudgeBody {
                            Text(line)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        Text("No nudges received")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    silenceSection

                    Divider()

                    // Remote for Jev captures, so tapping never moves the posture being captured.
                    NavigationLink {
                        JevRemoteView(session: sessionDelegate)
                    } label: {
                        Label("Jev capture", systemImage: "hand.tap")
                    }

                    // Calibrate button
                    Button {
                        sessionDelegate.sendCalibrateRequest()
                    } label: {
                        Label("Calibrate", systemImage: "scope")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!sessionDelegate.isConnected)

                    // Settings link
                    NavigationLink {
                        WatchCalibrationSettingsView(sessionDelegate: sessionDelegate)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                .padding()
            }
        }
    }
}

extension ContentView {
    /// Silence nudges for a while, or resume them. The phone holds the silence.
    @ViewBuilder
    var silenceSection: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if NudgeSilence.isSilenced(until: sessionDelegate.nudgesSilencedUntil, now: context.date),
               let until = sessionDelegate.nudgesSilencedUntil {
                VStack(spacing: 4) {
                    Label("Silenced until \(until.formatted(date: .omitted, time: .shortened))",
                          systemImage: "bell.slash.fill")
                        .font(.caption2)
                    Button("Resume nudges") { sessionDelegate.resumeNudges() }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .disabled(!sessionDelegate.isPhoneReachable)
                }
            } else {
                NavigationLink {
                    SilenceNudgesView(sessionDelegate: sessionDelegate)
                } label: {
                    Label("Silence nudges", systemImage: "bell.slash")
                }
                .disabled(!sessionDelegate.isPhoneReachable)
            }
        }
    }
}

/// Your posture, as the phone last reported it (2026-10-11).
struct PostureGlanceView: View {
    let look: PostureLook
    var now: Date = Date()

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
            Text(look.headline)
                .font(.headline)
                .foregroundStyle(color)
            if let since {
                // Counts up on its own.
                Text("for \(Text(since, style: .timer))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            // The countdown to the nudge (2026-10-13). Counts down on its own between the
            // phone's messages; the view is re-read every few seconds, which turns it to "due".
            switch look.countdown(now: now) {
            case .until(let nudgeAt):
                Text("nudge in \(Text(timerInterval: now...nudgeAt, countsDown: true))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(color)
            case .due:
                Text("nudge due")
                    .font(.caption)
                    .foregroundStyle(color)
            case nil:
                EmptyView()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var since: Date? {
        switch look {
        case .slouching(let since, _, _): return since
        case .headTurned(let since, _): return since
        default: return nil
        }
    }

    private var symbol: String {
        switch look {
        case .sittingWell: return "checkmark.circle.fill"
        case .slouching(_, let sustained, _):
            return sustained ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill"
        case .headTurned: return "arrow.left.arrow.right.circle.fill"
        case .notInView: return "person.slash"
        case .calibrating: return "scope"
        case .cameraPaused: return "video.slash"
        case .waitingForPhone: return "iphone.slash"
        }
    }

    /// The phone's colours: green, yellow while slouching, red once it's long enough to nudge.
    private var color: Color {
        switch look {
        case .sittingWell: return .green
        case .slouching(_, let sustained, _): return sustained ? .red : .yellow
        case .headTurned: return .yellow
        case .notInView, .calibrating, .cameraPaused, .waitingForPhone: return .secondary
        }
    }
}

/// How long to silence nudges for.
struct SilenceNudgesView: View {
    @ObservedObject var sessionDelegate: WatchSessionDelegate
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(NudgeSilence.options, id: \.minutes) { option in
            Button(option.label) {
                sessionDelegate.silenceNudges(minutes: option.minutes)
                dismiss()
            }
        }
        .navigationTitle("Silence for")
    }
}

struct WatchCalibrationSettingsView: View {
    @ObservedObject var sessionDelegate: WatchSessionDelegate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Position Sensitivity
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Position")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.3f", sessionDelegate.maxPositionVariance))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    Slider(value: $sessionDelegate.maxPositionVariance, in: 0.01...0.15, step: 0.005) {
                        Text("Position")
                    } onEditingChanged: { editing in
                        if !editing { sessionDelegate.sendSettings() }
                    }
                }

                // Angle Sensitivity
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Angle")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.1f\u{00B0}", sessionDelegate.maxAngleVariance))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    Slider(value: $sessionDelegate.maxAngleVariance, in: 1.0...15.0, step: 0.5) {
                        Text("Angle")
                    } onEditingChanged: { editing in
                        if !editing { sessionDelegate.sendSettings() }
                    }
                }

                // Hold Duration
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Hold")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.1fs", sessionDelegate.samplingDuration))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    Slider(value: $sessionDelegate.samplingDuration, in: 2.0...10.0, step: 0.5) {
                        Text("Hold")
                    } onEditingChanged: { editing in
                        if !editing { sessionDelegate.sendSettings() }
                    }
                }

                // Countdown Duration
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Countdown")
                            .font(.caption)
                        Spacer()
                        Text("\(sessionDelegate.countdownDuration)s")
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(sessionDelegate.countdownDuration) },
                            set: { sessionDelegate.countdownDuration = Int($0) }
                        ),
                        in: 1...5,
                        step: 1
                    ) {
                        Text("Countdown")
                    } onEditingChanged: { editing in
                        if !editing { sessionDelegate.sendSettings() }
                    }
                }
            }
            .padding()

            Divider()
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 16) {
                Text("Posture Detection")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Forward Lean
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Fwd Lean")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.3f", sessionDelegate.forwardCreepThreshold))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    Slider(value: $sessionDelegate.forwardCreepThreshold, in: WatchSettingLimits.forwardCreep,
                           step: WatchSettingLimits.forwardCreepStep) {
                        Text("Forward")
                    } onEditingChanged: { editing in
                        if !editing { sessionDelegate.sendSettings() }
                    }
                }

                // Twist
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Twist")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.0f\u{00B0}", sessionDelegate.twistThreshold))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    Slider(value: $sessionDelegate.twistThreshold, in: WatchSettingLimits.twist,
                           step: WatchSettingLimits.twistStep) {
                        Text("Twist")
                    } onEditingChanged: { editing in
                        if !editing { sessionDelegate.sendSettings() }
                    }
                }

                // Side Lean
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Side Lean")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.2f", sessionDelegate.sideLeanThreshold))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    Slider(value: $sessionDelegate.sideLeanThreshold, in: WatchSettingLimits.sideLean,
                           step: WatchSettingLimits.sideLeanStep) {
                        Text("Side Lean")
                    } onEditingChanged: { editing in
                        if !editing { sessionDelegate.sendSettings() }
                    }
                }

                // Drift Grace Period
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Grace")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.0fs", sessionDelegate.driftingToBadThreshold))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    Slider(value: $sessionDelegate.driftingToBadThreshold, in: 10...300, step: 5) {
                        Text("Grace")
                    } onEditingChanged: { editing in
                        if !editing { sessionDelegate.sendSettings() }
                    }
                }

                Button("Reset Posture Defaults") {
                    sessionDelegate.resetPostureSettings()
                }
                .font(.caption)
            }
            .padding()
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    ContentView(sessionDelegate: WatchSessionDelegate())
}
