import SwiftUI
import PostureLogic

struct CalibrationView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "figure.stand")
                .font(.system(size: 80))
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
        .padding()
    }

    @ViewBuilder
    private var statusText: some View {
        switch appModel.calibrationStatus {
        case .waiting:
            Text("Position yourself in frame...")
                .foregroundStyle(.secondary)
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
        case .sampling, .validating: .blue
        case .success: .green
        case .failed: .red
        }
    }
}
