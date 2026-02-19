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
