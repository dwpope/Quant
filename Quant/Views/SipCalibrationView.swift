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

                if capture.recordedSipCount > 0 && !appModel.sipCalibrationActive && !appModel.sipCalibrationCountingDown {
                    undoButton
                }

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
                if capture.isReady {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(
                            item: thresholdsJSON,
                            preview: SharePreview("Sip Thresholds")
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 8) {
            if capture.recordedSipCount > 0 {
                HStack(spacing: 6) {
                    ForEach(0..<capture.recordedSipCount, id: \.self) { _ in
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                    }
                }
            }

            Text("\(capture.recordedSipCount) sip\(capture.recordedSipCount == 1 ? "" : "s") recorded")
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
        if appModel.sipCalibrationCountingDown {
            VStack(spacing: 12) {
                Text("\(appModel.sipCalibrationCountdown)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.default, value: appModel.sipCalibrationCountdown)

                Text("Get ready…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if appModel.sipCalibrationActive {
            VStack(spacing: 8) {
                ProgressView(value: appModel.sipCalibrationProgress)
                    .tint(.blue)

                Text("Recording… take a sip now")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
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

    // MARK: - Undo Button

    private var undoButton: some View {
        Button {
            capture.removeLastSip()
        } label: {
            Label("Undo Last Sip", systemImage: "arrow.uturn.backward")
                .font(.subheadline)
        }
        .tint(.red)
    }

    // MARK: - Share

    private var thresholdsJSON: String {
        guard let thresholds = capture.derivedThresholds else { return "{}" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(thresholds),
              let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
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
