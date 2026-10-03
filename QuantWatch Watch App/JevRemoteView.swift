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

    /// Where you are in the test plan. Kept across launches, so a session can be paused.
    @AppStorage("jevTestPlan.index") private var planIndex = 0

    /// The last record whose judgement moved the plan on, so a double tap can't skip a step.
    @AppStorage("jevTestPlan.advancedFor") private var advancedForRecord = ""

    @State private var confirmingRestart = false

    /// The capture waiting on a "Discard?" confirmation.
    @State private var confirmingDiscard: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // The top of the screen is always the next action: judge a fresh capture,
                // otherwise the posture to do and Classify. Everything else is below the fold.
                if let status = session.jevStatus {
                    if let record = status.lastRecord, awaitsJudgement(record) {
                        judgeSection(record, options: status.trueClassOptions)
                    } else {
                        planSection(status)
                    }
                    Divider()
                    liveSection(status)
                    if let record = status.lastRecord, !awaitsJudgement(record) {
                        lastCaptureSection(record)
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

    private func awaitsJudgement(_ record: JevRemoteStatus.Record) -> Bool {
        JevTestPlan.awaitsJudgement(capturedAt: record.capturedAt, jevClass: record.jevClass,
                                    judged: record.judged != nil, discarded: record.discarded,
                                    now: Date())
    }

    // MARK: - Sections

    /// The posture to do now and the Classify button first, then how to do it and what counts
    /// as right. Moves on by itself when you judge; Back and Skip are for a capture gone wrong.
    @ViewBuilder
    private func planSection(_ status: JevRemoteStatus) -> some View {
        if let progress = JevTestPlan.progress(at: planIndex) {
            let posture = progress.step.posture
            HStack(spacing: 6) {
                Circle()
                    .fill(trackingColor(status.tracking))
                    .frame(width: 8, height: 8)
                Text(progress.repeatCount > 1
                     ? "\(posture.name) \(progress.repeatNumber)/\(progress.repeatCount)"
                     : posture.name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            classifySection(status)
            Text(posture.instruction)
                .font(.caption2)
            Text("Right: Jev \(posture.jevShouldSay), thresholds \(posture.thresholdsShouldSay)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Button("Back") { planIndex = JevTestPlan.previous(before: planIndex) }
                    .disabled(planIndex == 0)
                Button("Skip") { planIndex = JevTestPlan.next(after: planIndex) }
            }
            .font(.caption2)
            .buttonStyle(.bordered)
            Button("Restart plan") { confirmingRestart = true }
                .font(.caption2)
                .buttonStyle(.bordered)
                .disabled(planIndex == 0)
                .confirmationDialog("Restart the test plan from step 1?",
                                    isPresented: $confirmingRestart) {
                    Button("Restart", role: .destructive) { planIndex = 0 }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Captures you've already made stay on the phone.")
                }
            Text("\(progress.number) of \(progress.total)\(progress.step.optional ? " · optional" : "")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("Test plan done")
                .font(.headline)
            Text("Export on the phone: prepare export, then share.")
                .font(.caption2)
            Button("Start again") { planIndex = 0 }
                .font(.caption2)
                .buttonStyle(.bordered)
            classifySection(status)
        }
    }

    /// Judge the capture you just made.
    ///
    /// Labelled "You did", "Jev said" and "Thresholds said", because "Judge: Lean" read as an
    /// answer rather than the posture you were doing (2026-10-03). Each answer gets a tick or a
    /// cross against this step's right answers, and the button they point to is highlighted.
    /// You still choose: a capture can go wrong in ways the plan can't see.
    @ViewBuilder
    private func judgeSection(_ record: JevRemoteStatus.Record, options: [String]) -> some View {
        let posture = JevTestPlan.progress(at: planIndex)?.step.posture
        let jevRight = posture?.jevRight(record.jevClass)
        let thresholdsRight = posture?.thresholdsRight(record.thresholdStateAtCapture)
        let suggested = jevRight.flatMap { j in
            thresholdsRight.map { JevTestPlan.suggestedVerdict(jevRight: j, thresholdsRight: $0) }
        }

        if let posture {
            Text("You did: \(posture.name)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        answerRow("Jev said: \(JevRemoteStatus.displayName(record.jevClass ?? "")) \(Int(((record.jevConfidence ?? 0) * 100).rounded()))%",
                  right: jevRight, font: .headline)
        answerRow("Thresholds said: \(record.thresholdStateAtCapture)",
                  right: thresholdsRight, font: .caption)
        if let posture {
            Text("Right: Jev \(posture.jevShouldSay), thresholds \(posture.thresholdsShouldSay)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        verdictButton("Jev ok", .jevWasRight, suggested: suggested) {
            session.sendJevJudge(recordID: record.id, verdict: .jevWasRight)
            advancePlan(after: record.id)
        }
        verdictButton("Thr ok", .thresholdsWereRight, suggested: suggested) {
            session.sendJevJudge(recordID: record.id, verdict: .thresholdsWereRight)
            advancePlan(after: record.id)
        }
        let picker = NavigationLink("Both wrong") {
            TrueClassPicker(session: session, recordID: record.id, options: options,
                            thisStep: posture?.trueClass,
                            onJudged: { advancePlan(after: record.id) })
        }
        if suggested == .bothWrong {
            picker.buttonStyle(.borderedProminent).tint(.green)
        } else {
            picker.buttonStyle(.bordered)
        }
        discardButton(record)
    }

    /// For a capture made by mistake. It isn't judged, the plan stays on the same posture, and
    /// the phone keeps the record, flagged, so the analysis can leave it out.
    @ViewBuilder
    private func discardButton(_ record: JevRemoteStatus.Record) -> some View {
        Button("Discard capture", role: .destructive) { confirmingDiscard = record.id }
            .font(.caption2)
            .buttonStyle(.bordered)
            .confirmationDialog("Discard this capture?",
                                isPresented: Binding(
                                    get: { confirmingDiscard == record.id },
                                    set: { if !$0 { confirmingDiscard = nil } })) {
                Button("Discard", role: .destructive) {
                    session.sendJevDiscard(recordID: record.id)
                    confirmingDiscard = nil
                }
                Button("Cancel", role: .cancel) { confirmingDiscard = nil }
            } message: {
                Text("It stays on the phone, marked, and is left out of the analysis.")
            }
    }

    /// An answer with a tick or a cross against this step, or plain once the plan is finished.
    @ViewBuilder
    private func answerRow(_ text: String, right: Bool?, font: Font) -> some View {
        HStack(spacing: 4) {
            if let right {
                Image(systemName: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(right ? .green : .red)
                    .accessibilityLabel(right ? "right" : "wrong")
            }
            Text(text)
                .font(font)
        }
    }

    /// The button the ticks point to is filled in; the others are outlined.
    @ViewBuilder
    private func verdictButton(_ title: String, _ verdict: JevRemoteVerdict,
                               suggested: JevRemoteVerdict?,
                               action: @escaping () -> Void) -> some View {
        if verdict == suggested {
            Button(title, action: action).buttonStyle(.borderedProminent).tint(.green)
        } else {
            Button(title, action: action).buttonStyle(.bordered)
        }
    }

    /// Moves the plan on once per judged record.
    private func advancePlan(after recordID: UUID) {
        guard advancedForRecord != recordID.uuidString else { return }
        advancedForRecord = recordID.uuidString
        planIndex = JevTestPlan.next(after: planIndex)
    }

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

    /// The last capture, below the fold, once it's judged or too old to ask about.
    @ViewBuilder
    private func lastCaptureSection(_ record: JevRemoteStatus.Record) -> some View {
        Text("Last capture, \(record.capturedAt, style: .relative) ago")
            .font(.caption2)
            .foregroundStyle(.secondary)
        if let jevClass = record.jevClass {
            Text("Jev: \(JevRemoteStatus.displayName(jevClass)) \(Int(((record.jevConfidence ?? 0) * 100).rounded()))%")
                .font(.caption)
        } else {
            Text("Jev didn't answer. Classify again.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if record.discarded {
            Label("Discarded", systemImage: "trash")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            if let judged = record.judged {
                Label(verdictLabel(judged), systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
            // Also here, for a capture judged and only then found to be a mistake.
            discardButton(record)
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

/// "Both wrong": what you were actually doing. The test plan's posture for this step is listed
/// first and marked, since that's almost always the answer.
private struct TrueClassPicker: View {
    @ObservedObject var session: WatchSessionDelegate
    let recordID: UUID
    let options: [String]
    var thisStep: String? = nil
    var onJudged: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    private var ordered: [String] {
        guard let thisStep, options.contains(thisStep) else { return options }
        return [thisStep] + options.filter { $0 != thisStep }
    }

    var body: some View {
        List(ordered, id: \.self) { option in
            Button(option == thisStep
                   ? "\(JevRemoteStatus.displayName(option)) · this step"
                   : JevRemoteStatus.displayName(option)) {
                session.sendJevJudge(recordID: recordID, verdict: .bothWrong, trueClass: option)
                onJudged()
                dismiss()
            }
        }
        .navigationTitle("Actually…")
    }
}
