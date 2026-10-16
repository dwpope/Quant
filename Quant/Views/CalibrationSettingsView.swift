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
                        if ARFaceTrackingService.isFaceTrackingSupported {
                            Text("Front (Face)").tag(CameraMode.frontFace)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Camera")
                } footer: {
                    Text("Rear uses LiDAR depth when available. Front (2D) uses pose only. Front (Face) uses TrueDepth for an accurate head pose. Switching requires recalibration.")
                }

                Section {
                    SettingSlider(
                        title: "Position Sensitivity",
                        value: String(format: "%.3f", appModel.maxPositionVariance),
                        amount: $appModel.maxPositionVariance, range: 0.01...0.15, step: 0.005,
                        caption: "How still you need to be during calibration")

                    SettingSlider(
                        title: "Angle Sensitivity",
                        value: String(format: "%.1f", appModel.maxAngleVariance) + "\u{00B0}",
                        amount: $appModel.maxAngleVariance, range: 1.0...15.0, step: 0.5,
                        caption: "Torso angle tolerance during calibration")
                } header: {
                    Text("Sensitivity")
                } footer: {
                    Text("Higher values make calibration easier to pass.")
                }

                Section {
                    SettingSlider(
                        title: "Hold Duration",
                        value: String(format: "%.1fs", appModel.samplingDuration),
                        amount: $appModel.samplingDuration, range: 2.0...10.0, step: 0.5,
                        caption: "How long to hold still while sampling")

                    SettingSlider(
                        title: "Countdown",
                        value: "\(appModel.countdownDuration)s",
                        amount: Binding(
                            get: { Double(appModel.countdownDuration) },
                            set: { appModel.countdownDuration = Int($0) }
                        ),
                        range: 1...5, step: 1,
                        caption: "Seconds before sampling begins")
                } header: {
                    Text("Timing")
                }

                Section {
                    Button("Reset to Defaults") {
                        appModel.resetCalibrationSettings()
                    }
                }

                Section {
                    SettingSlider(
                        title: "Forward Lean",
                        value: String(format: "%.2f", appModel.forwardCreepThreshold),
                        amount: $appModel.forwardCreepThreshold, range: 0.03...0.30, step: 0.01,
                        caption: "How far forward before drifting",
                        onEditingChanged: { editing in if !editing { appModel.syncSettingsToWatch() } })

                    SettingSlider(
                        title: "Twist",
                        value: String(format: "%.0f", appModel.twistThreshold) + "\u{00B0}",
                        amount: $appModel.twistThreshold, range: 5.0...45.0, step: 1.0,
                        caption: "Shoulder rotation tolerance",
                        onEditingChanged: { editing in if !editing { appModel.syncSettingsToWatch() } })

                    SettingSlider(
                        title: "Side Lean",
                        value: String(format: "%.2f", appModel.sideLeanThreshold),
                        amount: $appModel.sideLeanThreshold, range: 0.03...0.25, step: 0.01,
                        caption: "Lateral lean tolerance",
                        onEditingChanged: { editing in if !editing { appModel.syncSettingsToWatch() } })

                    SettingSlider(
                        title: "Drift Grace Period",
                        value: String(format: "%.0fs", appModel.driftingToBadThreshold),
                        amount: $appModel.driftingToBadThreshold, range: 10...300, step: 5,
                        caption: "Seconds before drifting becomes bad",
                        onEditingChanged: { editing in if !editing { appModel.syncSettingsToWatch() } })
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

                Section {
                    NavigationLink("Posture Thresholds") {
                        ThresholdsSettingsView()
                    }
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Fine-tune individual posture metrics and nudge timing.")
                }

                Section {
                    NavigationLink("Stored Data") {
                        StoredDataView()
                    }
                } footer: {
                    Text("What the app keeps on this iPhone, and deleting older data.")
                }

                Section {
                    Toggle("Training mode", isOn: $appModel.isTrainingModeEnabled)
                } footer: {
                    Text("Captures labeling data for detector tuning.")
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
