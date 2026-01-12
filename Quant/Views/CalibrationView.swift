import SwiftUI
import PostureLogic

struct CalibrationView: View {
    @ObservedObject var appModel: AppModel
    @State private var showingError = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: iconName)
                .font(.system(size: 80))
                .foregroundStyle(iconColor)
                .symbolEffect(.bounce, value: appModel.calibrationStatus)

            // Title
            Text("Calibration")
                .font(.title)
                .fontWeight(.semibold)

            // Instructions
            VStack(spacing: 12) {
                Text(instructionText)
                    .font(.title3)
                    .multilineTextAlignment(.center)

                Text(subtitleText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            // Progress bar
            if case .sampling = appModel.calibrationStatus {
                ProgressView(value: appModel.calibrationProgress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 40)
                    .padding(.top, 16)
            }

            // Status message
            statusView
                .padding(.horizontal, 32)
                .padding(.top, 8)

            Spacer()

            // Action buttons
            buttonView
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
        }
        .padding()
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch appModel.calibrationStatus {
        case .waiting:
            return "figure.stand"
        case .sampling:
            return "figure.stand"
        case .validating:
            return "checkmark.circle"
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch appModel.calibrationStatus {
        case .waiting:
            return .blue
        case .sampling:
            return .blue
        case .validating:
            return .orange
        case .success:
            return .green
        case .failed:
            return .red
        }
    }

    private var instructionText: String {
        switch appModel.calibrationStatus {
        case .waiting:
            return "Sit up straight"
        case .sampling:
            return "Hold still..."
        case .validating:
            return "Validating..."
        case .success:
            return "Calibration complete!"
        case .failed:
            return "Calibration failed"
        }
    }

    private var subtitleText: String {
        switch appModel.calibrationStatus {
        case .waiting:
            return "Position yourself in frame with good posture. We'll capture your baseline for 5 seconds."
        case .sampling:
            return "Remain still and maintain good posture"
        case .validating:
            return "Processing your calibration data..."
        case .success:
            return "Your baseline has been saved successfully"
        case .failed:
            return "Please try again"
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch appModel.calibrationStatus {
        case .waiting:
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("Make sure you're fully visible and sitting upright")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)

        case .sampling:
            EmptyView()

        case .validating:
            ProgressView()

        case .success:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Baseline saved successfully")
                    .font(.caption)
            }
            .padding(12)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)

        case .failed(let reason):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Error")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var buttonView: some View {
        switch appModel.calibrationStatus {
        case .waiting:
            Button {
                appModel.startCalibration()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Calibration")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .disabled(appModel.trackingQuality != .good)

        case .sampling, .validating:
            Button {
                appModel.cancelCalibration()
            } label: {
                HStack {
                    Image(systemName: "xmark")
                    Text("Cancel")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.2))
                .foregroundStyle(.primary)
                .cornerRadius(12)
            }

        case .success:
            Button {
                appModel.finishCalibration()
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "checkmark")
                    Text("Continue")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }

        case .failed:
            VStack(spacing: 12) {
                Button {
                    appModel.retryCalibration()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }
            }
        }
    }
}

#Preview {
    CalibrationView(appModel: AppModel())
}
