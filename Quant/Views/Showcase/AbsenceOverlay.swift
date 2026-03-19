import SwiftUI

struct AbsenceOverlay<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            content()
                .opacity(0.3)

            VStack(spacing: 16) {
                Circle()
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 48, height: 48)
                    .scaleEffect(isPulsing ? 1.15 : 1.0)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                        value: isPulsing
                    )

                Text("Waiting for pose...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Waiting for pose detection")
        }
        .onAppear {
            if !reduceMotion { isPulsing = true }
        }
    }
}
