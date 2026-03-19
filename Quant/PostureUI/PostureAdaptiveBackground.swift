import SwiftUI

/// Conditionally applies material blur or a solid color fallback based on
/// the user's Reduce Transparency accessibility setting.
extension View {
    func postureBackground() -> some View {
        modifier(PostureAdaptiveBackgroundModifier())
    }
}

private struct PostureAdaptiveBackgroundModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if reduceTransparency {
            let fallback = colorScheme == .dark
                ? Color(white: 0.22)
                : Color(white: 0.92)
            content.background(fallback)
        } else {
            content.background(.ultraThinMaterial)
        }
    }
}
