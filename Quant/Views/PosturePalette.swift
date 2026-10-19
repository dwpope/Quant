import SwiftUI
import UIKit

/// The posture colours, readable as text in light and dark mode (2026-10-16 audit).
///
/// The system green, yellow and red are bright enough on dark backgrounds and too faint on light
/// ones: as text on the grouped background the card's green was 2.0:1 and yellow 1.35:1, against
/// the 4.5:1 text needs. In light mode these are darker shades of the same hues; in dark mode
/// they're the system colours, which also follow Increase Contrast.
enum PosturePalette {
    static let good = adaptive(light: UIColor(red: 0.10, green: 0.43, blue: 0.18, alpha: 1), dark: .systemGreen)
    static let slouching = adaptive(light: UIColor(red: 0.50, green: 0.32, blue: 0.00, alpha: 1), dark: .systemYellow)
    static let stillSlouching = adaptive(light: UIColor(red: 0.71, green: 0.14, blue: 0.09, alpha: 1), dark: .systemRed)

    private static func adaptive(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark.resolvedColor(with: traits) : light
        }
    }
}

/// Grey text that reads on a light background (2026-10-16 audit, fixed 2026-10-19).
///
/// The system's secondary grey is 3.4:1 on a light settings row and 3.3:1 on the grouped
/// background under it, against the 4.5:1 small text needs: Apple's audit failed the sliders'
/// values and captions and the section footers. In light mode it's a darker grey; in dark mode
/// the system's own, which reads and follows Increase Contrast. The app's blue is darker in
/// light mode for the same reason, in the asset catalog's AccentColor.
enum ReadablePalette {
    static let secondary = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.secondaryLabel.resolvedColor(with: traits)
            : UIColor(red: 0.39, green: 0.39, blue: 0.40, alpha: 1)
    }
}

extension View {
    /// Secondary text in `ReadablePalette.secondary`, for settings' values, captions, headers
    /// and footers.
    func readableSecondary() -> some View {
        foregroundStyle(Color(ReadablePalette.secondary))
    }
}
