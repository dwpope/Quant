import SwiftUI

/// A posture setting that's on both settings screens: what it's called, what it does, and its
/// slider's range and step, written once.
struct SharedSetting<Value: BinaryFloatingPoint> where Value.Stride: BinaryFloatingPoint {
    let title: String
    let caption: String
    let range: ClosedRange<Value>
    let step: Value.Stride
}

/// The posture settings on both Posture Thresholds and Calibration, and on the Watch.
///
/// One range and step for each (2026-10-16 audit): the two screens each had their own, and they
/// differed, so a value set on one could be out of the other's range. Each is the wider range of
/// the two with the finer step. The Watch's `WatchSettingLimits` is a golden copy of the numbers.
///
/// One name and description for each (2026-10-19): Posture Thresholds called forward lean
/// "Forward Creep", and each screen described all three in its own words.
enum SharedPostureSettings {
    static let forwardCreep = SharedSetting<Float>(
        title: "Forward Lean", caption: "How far you can lean forward before it counts as slouching",
        range: 0.01...0.30, step: 0.005)
    static let twist = SharedSetting<Float>(
        title: "Twist", caption: "How far your shoulders can twist before it counts as slouching",
        range: 5...45, step: 1)
    static let sideLean = SharedSetting<Float>(
        title: "Side Lean", caption: "How far you can lean to one side before it counts as slouching",
        range: 0.02...0.25, step: 0.01)
}

extension SettingSlider {
    init(_ setting: SharedSetting<Value>, value: String, amount: Binding<Value>,
         onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(title: setting.title, value: value, amount: amount, range: setting.range,
                  step: setting.step, caption: setting.caption, onEditingChanged: onEditingChanged)
    }
}
