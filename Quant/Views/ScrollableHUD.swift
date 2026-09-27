import SwiftUI

/// Caps a floating HUD at `maxHeight`, scrolling its content only when it would
/// be taller. `ViewThatFits` evaluates each candidate against the proposed height
/// (clamped to `maxHeight` by the frame), so a panel that fits renders as raw
/// `content` — sized to itself, no empty translucent box — while a panel that
/// overflows falls back to a `ScrollView`. No measurement round-trip, so it never
/// gets stuck at zero height the way a `min(measuredContent, maxHeight)` frame can.
///
/// `maxHeight` arrives as 0 for the first frame (before the surface is measured);
/// we treat that as "uncapped" so the panel is always visible, then the real cap
/// applies once `availableHeight` lands. Uncapped means no frame at all, not an
/// infinite one: `.frame(maxHeight: .infinity)` would stretch the panel to fill
/// every point offered, so a short panel would sit in a tall empty box.
///
/// Left at 0, the cap is whatever height the parent offers. That is how the main
/// screen uses it: its `VStack` offers the panel the space above the bottom
/// controls, so the panel can never push those controls off the screen.
///
/// Shared by the posture visualization's tuning panels and the main screen's
/// diagnostics panel. On the main screen it is what keeps the bottom controls on
/// screen: a panel whose content is taller than the space above them scrolls,
/// where a plain `VStack` would overflow both upwards and downwards.
struct ScrollableHUD<Content: View>: View {
    var maxHeight: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxHeight: maxHeight > 0 ? maxHeight : nil)
    }
}
