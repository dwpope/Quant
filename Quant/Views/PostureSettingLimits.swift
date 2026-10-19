import SwiftUI

/// A setting's slider: its range and its step.
struct SliderLimits<Value: BinaryFloatingPoint> where Value.Stride: BinaryFloatingPoint {
    let range: ClosedRange<Value>
    let step: Value.Stride
}

/// One range and step for each posture setting that's on both settings screens and the Watch
/// (2026-10-16 audit). Posture Thresholds and Calibration each had their own, and they differed,
/// so a value set on one could be out of the other's range. Each is the wider range of the two
/// with the finer step. The Watch's `WatchSettingLimits` is a golden copy of these numbers.
enum PostureSettingLimits {
    static let forwardCreep = SliderLimits<Float>(range: 0.01...0.30, step: 0.005)
    static let twist = SliderLimits<Float>(range: 5...45, step: 1)
    static let sideLean = SliderLimits<Float>(range: 0.02...0.25, step: 0.01)
}

extension SettingSlider {
    init(title: String, value: String, amount: Binding<Value>, limits: SliderLimits<Value>,
         caption: String, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(title: title, value: value, amount: amount, range: limits.range, step: limits.step,
                  caption: caption, onEditingChanged: onEditingChanged)
    }
}
