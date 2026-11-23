//
//  SeatChangePrompt.swift
//  Quant
//

import SwiftUI

/// The seat-change question (2026-11-23): shown at the top of either main screen while the
/// pipeline holds it open. Nudges wait until it's answered, or it times out.
struct SeatChangePrompt: View {
    let onRecalibrate: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Moved your seat?")
                .font(.headline)
            Text("Your posture readings look off from where you calibrated.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            // Stacked at accessibility text sizes, where two buttons side by side don't fit.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Button("Recalibrate", action: onRecalibrate)
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Takes a new calibration for where you sit now")
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                    .accessibilityHint("Keeps your current calibration")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .onAppear {
            // VoiceOver is told the question when it appears.
            AccessibilityNotification.Announcement("Moved your seat?").post()
        }
    }
}
