//
//  CalibrationSettingsView.swift
//  Quant
//

import SwiftUI

struct CalibrationSettingsView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Camera", selection: Binding(
                        get: { appModel.cameraMode },
                        set: { newMode in
                            Task { await appModel.switchCameraMode(to: newMode) }
                        }
                    )) {
                        Text("Rear (Depth)").tag(CameraMode.rearDepth)
                        Text("Front (2D)").tag(CameraMode.front2D)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Camera")
                } footer: {
                    Text("Rear uses LiDAR depth when available. Front uses 2D pose only. Switching requires recalibration.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Position Sensitivity")
                            Spacer()
                            Text(String(format: "%.3f", appModel.maxPositionVariance))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $appModel.maxPositionVariance, in: 0.01...0.15, step: 0.005)
                        Text("How still you need to be during calibration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Angle Sensitivity")
                            Spacer()
                            Text(String(format: "%.1f", appModel.maxAngleVariance) + "\u{00B0}")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $appModel.maxAngleVariance, in: 1.0...15.0, step: 0.5)
                        Text("Torso angle tolerance during calibration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Sensitivity")
                } footer: {
                    Text("Higher values make calibration easier to pass.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Hold Duration")
                            Spacer()
                            Text(String(format: "%.1fs", appModel.samplingDuration))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $appModel.samplingDuration, in: 2.0...10.0, step: 0.5)
                        Text("How long to hold still while sampling")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Countdown")
                            Spacer()
                            Text("\(appModel.countdownDuration)s")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(appModel.countdownDuration) },
                                set: { appModel.countdownDuration = Int($0) }
                            ),
                            in: 1...5,
                            step: 1
                        )
                        Text("Seconds before sampling begins")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Timing")
                }

                Section {
                    Button("Reset to Defaults") {
                        appModel.resetCalibrationSettings()
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Forward Lean")
                            Spacer()
                            Text(String(format: "%.2f", appModel.forwardCreepThreshold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $appModel.forwardCreepThreshold, in: 0.03...0.30, step: 0.01) {
                            Text("Forward Lean")
                        } onEditingChanged: { editing in
                            if !editing { appModel.syncSettingsToWatch() }
                        }
                        Text("How far forward before drifting")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Twist")
                            Spacer()
                            Text(String(format: "%.0f", appModel.twistThreshold) + "\u{00B0}")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $appModel.twistThreshold, in: 5.0...45.0, step: 1.0) {
                            Text("Twist")
                        } onEditingChanged: { editing in
                            if !editing { appModel.syncSettingsToWatch() }
                        }
                        Text("Shoulder rotation tolerance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Side Lean")
                            Spacer()
                            Text(String(format: "%.2f", appModel.sideLeanThreshold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $appModel.sideLeanThreshold, in: 0.03...0.25, step: 0.01) {
                            Text("Side Lean")
                        } onEditingChanged: { editing in
                            if !editing { appModel.syncSettingsToWatch() }
                        }
                        Text("Lateral lean tolerance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Drift Grace Period")
                            Spacer()
                            Text(String(format: "%.0fs", appModel.driftingToBadThreshold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $appModel.driftingToBadThreshold, in: 10...300, step: 5) {
                            Text("Drift Grace Period")
                        } onEditingChanged: { editing in
                            if !editing { appModel.syncSettingsToWatch() }
                        }
                        Text("Seconds before drifting becomes bad")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Posture Detection")
                } footer: {
                    Text("Higher values make posture detection more lenient.")
                }

                Section {
                    Button("Reset Posture to Defaults") {
                        appModel.resetPostureSettings()
                    }
                }
            }
            .navigationTitle("Calibration Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    CalibrationSettingsView()
        .environmentObject(AppModel())
}
