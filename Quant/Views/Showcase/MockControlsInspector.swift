import SwiftUI
import PostureLogic

struct MockControlsInspector: View {
    @ObservedObject var mockSource: MockPostureDataSource

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Auto-simulate", isOn: $mockSource.isAutoSimulating)
                        .onChange(of: mockSource.isAutoSimulating) { _, newValue in
                            if newValue {
                                mockSource.startSimulation()
                            } else {
                                mockSource.stopSimulation()
                            }
                        }
                }

                if !mockSource.isAutoSimulating {
                    Section("Metrics") {
                        metricSlider("Forward Creep", value: $mockSource.manualForwardCreep,
                                     threshold: mockSource.simulationThresholds.forwardCreepThreshold)
                        metricSlider("Head Drop", value: $mockSource.manualHeadDrop,
                                     threshold: mockSource.simulationThresholds.headDropThreshold)
                        metricSlider("Shoulder Rounding", value: $mockSource.manualShoulderRounding,
                                     threshold: mockSource.simulationThresholds.shoulderRoundingThreshold)
                        metricSlider("Lateral Lean", value: $mockSource.manualLateralLean,
                                     threshold: mockSource.simulationThresholds.sideLeanThreshold)
                        metricSlider("Twist", value: $mockSource.manualTwist,
                                     threshold: mockSource.simulationThresholds.twistThreshold)
                    }

                    Section("State Override") {
                        stateButtons
                    }
                }
            }
            .navigationTitle("Mock Controls")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func metricSlider(_ label: String, value: Binding<Float>, threshold: Float) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.3f", value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...(threshold * 2))
        }
    }

    private var stateButtons: some View {
        let now = Date().timeIntervalSince1970
        let states: [(String, PostureState)] = [
            ("Good", .good),
            ("Drifting", .drifting(since: now)),
            ("Bad", .bad(since: now)),
            ("Calibrating", .calibrating),
            ("Absent", .absent),
        ]
        return ForEach(states, id: \.0) { label, state in
            Button(label) {
                mockSource.manualPostureState = state
            }
        }
    }
}
