import SwiftUI
import UIKit

extension View {
    /// Applies `.ultraThinMaterial` when transparency is allowed, or a solid
    /// secondary background when Reduce Transparency is enabled.
    func postureBackground() -> some View {
        modifier(PostureBackgroundModifier())
    }
}

private struct PostureBackgroundModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(UIColor.secondarySystemBackground))
        } else {
            content
                .background(.ultraThinMaterial)
        }
    }
}
