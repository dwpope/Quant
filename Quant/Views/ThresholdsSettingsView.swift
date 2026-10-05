import SwiftUI

struct ThresholdsSettingsView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Forward Creep")
                        Spacer()
                        Text(String(format: "%.3f", appModel.forwardCreepThreshold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $appModel.forwardCreepThreshold, in: 0.01...0.10, step: 0.005)
                    Text("Distance threshold for forward lean detection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Twist")
                        Spacer()
                        Text(String(format: "%.0f\u{00B0}", appModel.twistThreshold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $appModel.twistThreshold, in: 5...30, step: 1)
                    Text("Shoulder rotation angle threshold")
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
                    Slider(value: $appModel.sideLeanThreshold, in: 0.02...0.20, step: 0.01)
                    Text("Lateral lean distance threshold")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Head Drop")
                        Spacer()
                        Text(String(format: "%.3f", appModel.headDropThreshold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $appModel.headDropThreshold, in: 0.005...0.05, step: 0.0025)
                    Text("How far your head can drop towards your shoulders, in shoulder widths, before it counts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Shoulder Rounding")
                        Spacer()
                        Text(String(format: "%.0f\u{00B0}", appModel.shoulderRoundingThreshold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $appModel.shoulderRoundingThreshold, in: 3...20, step: 1)
                    Text("Shoulder rounding angle threshold")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Posture Thresholds")
            } footer: {
                Text("Lower values make detection more sensitive.")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Slouch Duration")
                        Spacer()
                        Text(String(format: "%.0f sec", appModel.slouchDurationBeforeNudge))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $appModel.slouchDurationBeforeNudge, in: 60...600, step: 10)
                    Text("Seconds of bad posture before a nudge fires")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Nudge Cooldown")
                        Spacer()
                        Text(String(format: "%.0f sec", appModel.nudgeCooldown))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $appModel.nudgeCooldown, in: 60...1800, step: 30)
                    Text("Minimum seconds between nudges")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Max Nudges/Hour")
                        Spacer()
                        Text(appModel.maxNudgesPerHour == 0 ? "No limit" : "\(appModel.maxNudgesPerHour)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(appModel.maxNudgesPerHour) },
                            set: { appModel.maxNudgesPerHour = Int($0) }
                        ),
                        in: 0...10,
                        step: 1
                    )
                    Text("Maximum nudge alerts per hour. 0 is no limit: the cooldown spaces them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Timing")
            }

            Section {
                Button("Reset to Defaults") {
                    appModel.resetPostureSettings()
                }
            }
        }
        .navigationTitle("Posture Thresholds")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ThresholdsSettingsView()
            .environmentObject(AppModel())
    }
}
