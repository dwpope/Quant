import SwiftUI

struct ThresholdsSettingsView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        Form {
            Section {
                SettingSlider(
                    SharedPostureSettings.forwardCreep,
                    value: String(format: "%.3f", appModel.forwardCreepThreshold),
                    amount: $appModel.forwardCreepThreshold)

                SettingSlider(
                    SharedPostureSettings.twist,
                    value: String(format: "%.0f\u{00B0}", appModel.twistThreshold),
                    amount: $appModel.twistThreshold)

                SettingSlider(
                    SharedPostureSettings.sideLean,
                    value: String(format: "%.2f", appModel.sideLeanThreshold),
                    amount: $appModel.sideLeanThreshold)

                SettingSlider(
                    title: "Head Drop",
                    value: HeadDrop.label(appModel.headDropThreshold),
                    amount: $appModel.headDropThreshold, range: HeadDrop.range, step: HeadDrop.step,
                    caption: "How far your head can drop towards your shoulders, in shoulder widths, before it counts.")

                SettingSlider(
                    title: "Shoulder Rounding",
                    value: String(format: "%.0f\u{00B0}", appModel.shoulderRoundingThreshold),
                    amount: $appModel.shoulderRoundingThreshold, range: 3...20, step: 1,
                    caption: "Shoulder rounding angle threshold")
            } header: {
                Text("Posture Thresholds")
                    .readableSecondary()
            } footer: {
                Text("Lower values make detection more sensitive.")
                    .readableSecondary()
            }

            Section {
                SettingSlider(
                    title: "Slouch Duration",
                    value: String(format: "%.0f sec", appModel.slouchDurationBeforeNudge),
                    amount: $appModel.slouchDurationBeforeNudge, range: 30...600, step: 10,
                    caption: "Slouched seconds before a nudge, added up: brief sit-ups pause the count, 30 s sitting well resets it")

                SettingSlider(
                    title: "Repeat While Slouched",
                    value: String(format: "%.0f sec", appModel.nudgeCooldown),
                    amount: $appModel.nudgeCooldown, range: 30...600, step: 10,
                    caption: "Still slouched after a nudge: nudged again after this much more slouching. 30 s sitting well ends it")

                SettingSlider(
                    title: "Max Nudges/Hour",
                    value: appModel.maxNudgesPerHour == 0 ? "No limit" : "\(appModel.maxNudgesPerHour)",
                    amount: Binding(
                        get: { Double(appModel.maxNudgesPerHour) },
                        set: { appModel.maxNudgesPerHour = Int($0) }
                    ),
                    range: 0...10, step: 1,
                    caption: "Maximum nudge alerts per hour. 0 is no limit: the cooldown spaces them.")
            } header: {
                Text("Timing")
                    .readableSecondary()
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

extension ThresholdsSettingsView {
    /// The head drop slider. Steps of 0.00125 since 2026-11-18: at 0.0025 it could only jump
    /// between 0.0175 and 0.020, and the line went to 0.01875, halfway.
    enum HeadDrop {
        static let range: ClosedRange<Float> = 0.005...0.05
        static let step: Float = 0.00125

        /// To 5 places, without trailing zeros past the third: "0.01875", "0.0175", "0.020".
        /// Three places showed 0.0175 as "0.018".
        static func label(_ value: Float) -> String {
            var text = String(format: "%.5f", value)
            while text.hasSuffix("0"), text.count > "0.000".count { text.removeLast() }
            return text
        }
    }
}
