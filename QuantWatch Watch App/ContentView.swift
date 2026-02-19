//
//  ContentView.swift
//  QuantWatch Watch App
//
//  Created by Dave Pope on 13/02/2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var sessionDelegate: WatchSessionDelegate

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Image(systemName: "figure.stand")
                        .imageScale(.large)
                        .foregroundStyle(.tint)

                    Text("Quant")
                        .font(.headline)

                    Divider()

                    // Connection status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(sessionDelegate.isConnected ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(sessionDelegate.isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                    }

                    // Last nudge received
                    if let lastNudge = sessionDelegate.lastNudgeTime {
                        Text("Last nudge:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(lastNudge, style: .time)
                            .font(.caption)
                    } else {
                        Text("No nudges received")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

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
        }
        .navigationTitle("Calibration")
    }
}

#Preview {
    ContentView(sessionDelegate: WatchSessionDelegate())
}
