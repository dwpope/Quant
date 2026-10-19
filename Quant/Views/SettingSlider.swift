import SwiftUI

/// A setting with a slider: its name and value, the slider, then what it does.
///
/// For VoiceOver the row is one element (2026-10-16 audit): the setting's name, its value as
/// shown, what it does as the hint, and a swipe up or down moves it a step. The value beside the
/// name was read on its own, as a bare "0.060", and most sliders had no name.
struct SettingSlider<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    let title: String
    /// The value as shown, and as VoiceOver reads it.
    let value: String
    @Binding var amount: Value
    let range: ClosedRange<Value>
    let step: Value.Stride
    let caption: String
    /// Also called with `false` after a VoiceOver swipe, which has no drag to end.
    var onEditingChanged: (Bool) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // At the accessibility text sizes the value goes under the name (2026-10-19): beside
            // it, the name wrapped a word to a line.
            if typeSize.isAccessibilitySize {
                Text(title)
                valueText
            } else {
                HStack {
                    Text(title)
                    Spacer()
                    valueText
                }
            }
            Slider(value: $amount, in: range, step: step) {
                Text(title)
            } onEditingChanged: { editing in
                onEditingChanged(editing)
            }
            Text(caption)
                .font(.caption)
                .readableSecondary()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint(caption)
        .accessibilityAdjustableAction { direction in
            amount = Self.adjusted(amount, direction, step: step, in: range)
            onEditingChanged(false)
        }
    }

    private var valueText: some View {
        Text(value)
            .readableSecondary()
            .monospacedDigit()
    }

    /// A step up or down, kept within the range. A value already past the range's end (another
    /// screen allows more) stays put rather than being pulled back the wrong way.
    static func adjusted(_ amount: Value, _ direction: AccessibilityAdjustmentDirection,
                         step: Value.Stride, in range: ClosedRange<Value>) -> Value {
        switch direction {
        case .increment: return amount >= range.upperBound ? amount : min(range.upperBound, amount + Value(step))
        case .decrement: return amount <= range.lowerBound ? amount : max(range.lowerBound, amount - Value(step))
        @unknown default: return amount
        }
    }
}
