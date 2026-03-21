import SwiftUI

/// Applies VoiceOver accessibility labels and reduce-motion support to any posture variant view.
/// Applied at the showcase wrapper level so all 60 variants get consistent accessibility behavior.
struct PostureVariantAccessibilityModifier: ViewModifier {
    @EnvironmentObject var observer: PostureDisplayObserver
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                PostureVisualStyle.stateAccessibilityLabel(
                    for: observer.data.postureState,
                    worstOffender: observer.data.worstOffender
                )
            )
            .accessibilityValue(
                "Overall score \(Int(observer.data.aggregateScore * 100)) percent"
            )
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = transaction.animation.map { _ in
                        .easeInOut(duration: 0.3)
                    }
                }
            }
    }
}

extension View {
    func postureVariantAccessibility() -> some View {
        modifier(PostureVariantAccessibilityModifier())
    }
}
