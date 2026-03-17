import SwiftUI

struct SettingsSheetView: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

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
                }

                Section {
                    Toggle("Camera Preview", isOn: $appModel.showCameraPreview)
                }

                Section {
                    NavigationLink("Calibration") {
                        CalibrationSettingsView()
                    }
                    NavigationLink("Posture Thresholds") {
                        ThresholdsSettingsView()
                    }
                } header: {
                    Text("Settings")
                }

                Section {
                    Picker("Haptic Style", selection: $appModel.selectedHaptic) {
                        Text("notification").tag("notification")
                        Text("directionUp").tag("directionUp")
                        Text("directionDown").tag("directionDown")
                        Text("success").tag("success")
                        Text("failure").tag("failure")
                        Text("retry").tag("retry")
                        Text("start").tag("start")
                        Text("stop").tag("stop")
                        Text("click").tag("click")
                    }

                    Button("Test Nudge") {
                        appModel.sendTestNudge()
                    }
                } header: {
                    Text("Haptics")
                }

                Section {
                    Button("Recalibrate") {
                        appModel.recalibrate()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
