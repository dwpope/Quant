//
//  WatchSettingLimits.swift
//  QuantWatch Watch App
//
//  The posture sliders' ranges and steps.
//

/// The posture sliders' ranges and steps, a golden copy of the phone's `PostureSettingLimits`
/// (2026-10-16 audit): one range and step for each setting, on both of the phone's settings
/// screens and here. The Watch had the Calibration screen's, which differed from Posture
/// Thresholds'. `WatchSettingLimitsTests` holds the same numbers as the phone's tests.
enum WatchSettingLimits {
    static let forwardCreep: ClosedRange<Float> = 0.01...0.30
    static let forwardCreepStep: Float = 0.005
    static let twist: ClosedRange<Float> = 5...45
    static let twistStep: Float = 1
    static let sideLean: ClosedRange<Float> = 0.02...0.25
    static let sideLeanStep: Float = 0.01
}
