import SwiftUI
import PostureLogic

struct CalibrationView: View {
    @ObservedObject var appModel: AppModel

    /// The phone on its side (2026-11-11): smaller and closer, to fit above the icons.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var compact: Bool { verticalSizeClass == .compact }

    var body: some View {
        VStack(spacing: compact ? 12 : 24) {
            if case .countdown(let seconds) = appModel.calibrationStatus {
                Text("\(seconds)")
                    .font(.system(size: compact ? 88 : 120, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
                    .contentTransition(.numericText())
                    .animation(.default, value: seconds)

                Text("Get into position!")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "figure.stand")
                    .font(.system(size: compact ? 44 : 80))
                    .foregroundStyle(iconColor)

                Text("Sit up straight")
                    .font(.title)

                Text("Hold still for 5 seconds")
                    .foregroundStyle(.secondary)

                ProgressView(value: appModel.calibrationProgress)
                    .padding(.horizontal, 40)

                statusText

                if case .failed = appModel.calibrationStatus {
                    Button("Try Again") {
                        appModel.startCalibration()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private var statusText: some View {
        switch appModel.calibrationStatus {
        case .waiting:
            Text("Position yourself in frame...")
                .foregroundStyle(.secondary)
        case .countdown:
            EmptyView()
        case .sampling:
            Text("Hold still...")
                .foregroundStyle(.blue)
        case .validating:
            Text("Validating...")
                .foregroundStyle(.blue)
        case .success:
            Text("Calibration complete!")
                .foregroundStyle(.green)
        case .failed(let reason):
            Text(reason)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var iconColor: Color {
        switch appModel.calibrationStatus {
        case .waiting: .secondary
        case .countdown, .sampling, .validating: .blue
        case .success: .green
        case .failed: .red
        }
    }
}
