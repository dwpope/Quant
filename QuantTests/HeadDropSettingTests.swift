import XCTest
import PostureLogic
import SwiftUI
@testable import Quant

/// Head drop counts the way it reads on the device, negative as the head drops, since 2026-10-05
/// (see `PostureThresholds.headDropThreshold`).
/// The setting's meaning changed with it, so a value stored under the old meaning must not carry
/// over: 0.15 would need a huge drop and silence the signal.
@MainActor
final class HeadDropSettingTests: XCTestCase {

    /// 0.01875 since 2026-11-18, halfway between the last two: at 0.0175 Dave was nudged for small
    /// dips, and at 0.020 his neck strained while the app stayed green. (0.020 from 2026-11-09,
    /// when sitting well flickered across 0.015.)
    func test_theDefault_isBetweenASmallDipAndAStrainedNeck() {
        XCTAssertEqual(AppModel.defaultHeadDropThreshold, 0.01875)
    }

    func test_aValueStoredUnderTheOldMeaning_isIgnored() {
        UserDefaults.standard.set(Float(0.15), forKey: "com.quant.posture.headDrop")
        defer { UserDefaults.standard.removeObject(forKey: "com.quant.posture.headDrop") }
        XCTAssertEqual(AppModel().headDropThreshold, 0.01875)
    }

    /// The old default, stored when the slider was touched, mustn't keep the flicker going.
    func test_aValueStoredBeforeTheNewLine_isIgnored() {
        UserDefaults.standard.set(Float(0.015), forKey: "com.quant.posture.headDrop.v2")
        defer { UserDefaults.standard.removeObject(forKey: "com.quant.posture.headDrop.v2") }
        XCTAssertEqual(AppModel().headDropThreshold, 0.01875)
    }

    /// 0.020, stored when the setting was touched or reset, mustn't keep the strain green.
    func test_aValueStoredBeforeTheTighterLine_isIgnored() {
        UserDefaults.standard.set(Float(0.020), forKey: "com.quant.posture.headDrop.v3")
        defer { UserDefaults.standard.removeObject(forKey: "com.quant.posture.headDrop.v3") }
        XCTAssertEqual(AppModel().headDropThreshold, 0.01875)
    }

    /// 0.0175, stored when the setting was touched or reset, mustn't keep the small dips nudging.
    func test_aValueStoredBeforeTheHalfwayLine_isIgnored() {
        UserDefaults.standard.set(Float(0.0175), forKey: "com.quant.posture.headDrop.v4")
        defer { UserDefaults.standard.removeObject(forKey: "com.quant.posture.headDrop.v4") }
        XCTAssertEqual(AppModel().headDropThreshold, 0.01875)
    }

    // MARK: - The slider (2026-11-18)

    /// Its steps were 0.0025, so it could only jump between 0.0175 and 0.020. Every line tried
    /// since 2026-11-09 is now a step, so Dave can tune it himself.
    func test_theSlider_landsOnEveryLineTried() {
        let slider = ThresholdsSettingsView.HeadDrop.self
        for line: Float in [0.015, 0.0175, 0.01875, 0.020] {
            let steps = (line - slider.range.lowerBound) / slider.step
            XCTAssertEqual(steps, steps.rounded(), accuracy: 0.001, "\(line) is between two steps")
        }
    }

    /// A VoiceOver swipe up from the old line lands on the new one.
    func test_aStepUpFromTheOldLine_isTheNewLine() {
        let slider = ThresholdsSettingsView.HeadDrop.self
        let up = SettingSlider<Float>.adjusted(0.0175, .increment, step: slider.step, in: slider.range)
        XCTAssertEqual(up, 0.01875, accuracy: 0.000001)
    }

    /// It showed 3 places, so 0.0175 read as "0.017" or "0.018", and 0.01875 would too.
    func test_theValue_showsTheLineAsSet() {
        let label = ThresholdsSettingsView.HeadDrop.label
        XCTAssertEqual(label(0.0175), "0.0175")
        XCTAssertEqual(label(0.01875), "0.01875")
        XCTAssertEqual(label(0.020), "0.020")
        XCTAssertEqual(label(0.005), "0.005")
        // As the slider makes it: the range's start plus whole steps, in Float.
        XCTAssertEqual(label(0.005 + 11 * ThresholdsSettingsView.HeadDrop.step), "0.01875")
    }
}
