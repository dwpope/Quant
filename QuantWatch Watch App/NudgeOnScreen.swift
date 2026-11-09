//
//  NudgeOnScreen.swift
//  QuantWatch Watch App
//
//  A nudge on the app's own screen.
//

import SwiftUI

/// A nudge that came with the app in front (2026-11-09, session 7). Dave saw no notification
/// while looking at the app, only felt its taps, so the app shows the nudge itself.
struct NudgeOnScreen: Identifiable, Equatable {
    let id = UUID()
    let body: String
    let arrivedAt: Date
}

/// The nudge's line, large, over the app's screen, as its notification would show it.
struct NudgeOnScreenView: View {
    let nudge: NudgeOnScreen
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Label(NudgeMessage.notificationTitle, systemImage: "figure.stand")
                    .font(.headline)
                    .foregroundStyle(.yellow)
                Text(nudge.body)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(nudge.arrivedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Done") { dismiss() }
            }
            .padding(.horizontal, 4)
        }
    }
}
