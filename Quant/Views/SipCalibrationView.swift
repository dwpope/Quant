import PostureLogic
import SwiftUI

/// Guides the user through recording 5 sips to personalise detection thresholds.
///
/// Each tap of "Record Sip" starts a 10-second window during which the
/// camera watches for a drinking gesture. After 5 sips, derived thresholds
/// replace the defaults in `SipDetector`.
struct SipCalibrationView: View {
    @ObservedObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    private var capture: SipCalibrationCapture { appModel.sipCalibrationCapture }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                progressSection

                instructionsSection

                Spacer()

                actionButton

                if capture.isReady {
                    applyButton
                }
            }
            .padding(24)
            .navigationTitle("Sip Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<5) { i in
                    Circle()
                        .fill(i < capture.recordedSipCount ? Color.blue : Color.secondary.opacity(0.3))
                        .frame(width: 12, height: 12)
                }
            }

            Text("\(capture.recordedSipCount) of 5 sips recorded")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(spacing: 8) {
            Text("Personalise your sip detection")
                .font(.headline)

            Text("Take a sip from your water bottle naturally, then tap \"Record Sip\" after each one. Quant will learn your typical drinking motion and set thresholds to match.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        if appModel.sipCalibrationActive {
            // Capture in progress — show countdown
            VStack(spacing: 8) {
                ProgressView(value: appModel.sipCalibrationProgress)
                    .tint(.blue)

                Text("Recording… take a sip now")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if !capture.isReady {
            Button {
                appModel.beginSipCalibrationCapture()
            } label: {
                Label("Record Sip", systemImage: "circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Apply Button

    private var applyButton: some View {
        Button {
            appModel.applySipCalibration()
            dismiss()
        } label: {
            Label("Apply Personalised Thresholds", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
