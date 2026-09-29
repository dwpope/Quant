//
//  JevRemoteView.swift
//  QuantWatch Watch App
//
//  Classify and judge Jev captures from the wrist, so tapping never moves the posture being
//  captured.
//

import SwiftUI

struct JevRemoteView: View {
    @ObservedObject var session: WatchSessionDelegate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let status = session.jevStatus {
                    liveSection(status)
                    classifySection(status)
                    if let record = status.lastRecord {
                        Divider()
                        recordSection(record, options: status.trueClassOptions)
                    }
                    Text("Judged \(status.judgedCount) of \(status.total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(session.isPhoneReachable
                         ? "Waiting for the phone…"
                         : "Open Aware on your iPhone and keep it on screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Jev capture")
        .onAppear { session.requestJevStatus() }
    }

    // MARK: - Sections

    /// What the camera sees right now, so you know a capture will be usable before you tap.
    @ViewBuilder
    private func liveSection(_ status: JevRemoteStatus) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(trackingColor(status.tracking))
                .frame(width: 8, height: 8)
            Text("Tracking \(status.tracking)")
                .font(.caption)
        }
        HStack(spacing: 4) {
            Text("Thresholds: \(status.thresholdState)")
            if let since = status.thresholdSince {
                Text(since, style: .timer)
                    .monospacedDigit()
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func classifySection(_ status: JevRemoteStatus) -> some View {
        if !status.enabled {
            // The switch stays on the phone: it is what decides whether anything leaves it.
            Text("Switch on Jev classifier in the phone's panel.")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else if !status.calibrated {
            Text("The phone is calibrating. Sit upright in view.")
                .font(.caption2)
                .foregroundStyle(.orange)
        }

        Button {
            session.sendJevClassify()
        } label: {
            buttonLabel(status)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(session.jevBusy || !status.enabled || !status.calibrated || !session.isPhoneReachable)

        if session.jevBusy, status.captureDelay > 0 {
            // The capture happens after the wrist goes down, so the glance isn't recorded.
            Text("Lower your wrist, look at the screen and hold the pose for \(Int(status.captureDelay.rounded())) seconds.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if let notice = status.notice {
            Text(notice)
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func recordSection(_ record: JevRemoteStatus.Record, options: [String]) -> some View {
        Text("Last capture, \(record.capturedAt, style: .relative) ago")
            .font(.caption2)
            .foregroundStyle(.secondary)

        if let jevClass = record.jevClass {
            Text("Jev: \(JevRemoteStatus.displayName(jevClass)) \(Int(((record.jevConfidence ?? 0) * 100).rounded()))%")
                .font(.headline)
        } else {
            Text("Jev didn't answer")
                .font(.headline)
                .foregroundStyle(.orange)
        }
        Text("Thresholds said \(record.thresholdStateAtCapture)")
            .font(.caption)

        if let judged = record.judged {
            Label(verdictLabel(judged), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if record.jevClass != nil {
            Button("Jev ok") {
                session.sendJevJudge(recordID: record.id, verdict: .jevWasRight)
            }
            Button("Thr ok") {
                session.sendJevJudge(recordID: record.id, verdict: .thresholdsWereRight)
            }
            NavigationLink("Both wrong") {
                TrueClassPicker(session: session, recordID: record.id, options: options)
            }
        }
    }

    // MARK: - Helpers

    /// "Classify", then a countdown to the phone's capture, then "Classifying…" until it answers.
    @ViewBuilder
    private func buttonLabel(_ status: JevRemoteStatus) -> some View {
        if session.jevBusy, let tapped = session.jevTapDate {
            TimelineView(.periodic(from: tapped, by: 0.5)) { context in
                let left = JevRemoteStatus.secondsUntilCapture(
                    tappedAt: tapped, now: context.date, delay: status.captureDelay)
                Text(left > 0 ? "Capturing in \(left)" : "Classifying…")
            }
        } else {
            Text(session.jevBusy ? "Classifying…" : "Classify")
        }
    }

    private func trackingColor(_ tracking: String) -> Color {
        switch tracking {
        case "good": return .green
        case "degraded": return .orange
        default: return .red
        }
    }

    private func verdictLabel(_ verdict: JevRemoteVerdict) -> String {
        switch verdict {
        case .jevWasRight: return "Judged: Jev ok"
        case .thresholdsWereRight: return "Judged: thr ok"
        case .bothWrong: return "Judged: both wrong"
        }
    }
}

/// "Both wrong": what you were actually doing.
private struct TrueClassPicker: View {
    @ObservedObject var session: WatchSessionDelegate
    let recordID: UUID
    let options: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(options, id: \.self) { option in
            Button(JevRemoteStatus.displayName(option)) {
                session.sendJevJudge(recordID: recordID, verdict: .bothWrong, trueClass: option)
                dismiss()
            }
        }
        .navigationTitle("Actually…")
    }
}
