import SwiftUI
import UIKit
import XCTest
import PostureLogic
@testable import Quant

/// One set of words for your posture, colours that read as text, and a cue beside colour
/// (2026-10-16 audit).
///
/// The same posture had four sets of names: "Good / Drifting / Poor posture" on the phone's card,
/// "Sitting well / Slouching" on the Watch, "Sat well / Slouched long enough to nudge" under the
/// timeline. In light mode the card's green and yellow were 2.0:1 and 1.35:1 against the 4.5:1
/// text needs, and the timeline told good from bad by colour alone.
@MainActor
final class PostureWordsAndColoursTests: XCTestCase {

    func test_theCard_andTheTimeline_useTheSameWords() {
        XCTAssertEqual(PostureCard.label(for: .good), "Sitting well")
        XCTAssertEqual(PostureCard.label(for: .drifting(since: 0)), "Slouching")
        XCTAssertEqual(PostureCard.label(for: .bad(since: 0)), "Still slouching")
        XCTAssertEqual(PostureCard.label(for: .absent), "Away")
        XCTAssertEqual(PostureTimeline.Band.allCases.map(\.label),
                       ["Sitting well", "Slouching", "Still slouching", "Away"])
    }

    /// The band dips while you slouch, and lower the longer it goes on: readable without colour.
    func test_eachBand_standsAtItsOwnHeight() {
        let heights = PostureTimeline.Band.allCases.map(\.height)
        XCTAssertEqual(heights, heights.sorted(by: >), "good, slouching, still slouching, away")
        XCTAssertEqual(Set(heights).count, heights.count)
    }

    // MARK: - Contrast

    private func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        func luminance(_ c: UIColor) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &alpha)
            func linear(_ v: CGFloat) -> Double {
                let v = Double(v)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Against the grouped background the cards sit on, in each mode.
    func test_thePostureColours_readAsText_inLightAndDarkMode() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let lightBackground = UIColor.systemGroupedBackground.resolvedColor(with: light)
        let darkBackground = UIColor.secondarySystemGroupedBackground.resolvedColor(with: dark)
        for (name, colour) in [("good", PosturePalette.good), ("slouching", PosturePalette.slouching),
                               ("still slouching", PosturePalette.stillSlouching)] {
            XCTAssertGreaterThanOrEqual(contrast(colour.resolvedColor(with: light), lightBackground), 4.5,
                                        "\(name), light")
            XCTAssertGreaterThanOrEqual(contrast(colour.resolvedColor(with: dark), darkBackground), 4.5,
                                        "\(name), dark")
        }
    }
}

/// A setting's slider is one element for VoiceOver (2026-10-16 audit): named, with its value as
/// shown and what it does as the hint, and swiped up or down a step at a time. Its value beside
/// the name was read on its own, as a bare "0.060".
@MainActor
final class SettingSliderTests: XCTestCase {

    func test_aSwipe_movesItAStep_withinItsRange() {
        XCTAssertEqual(SettingSlider<Double>.adjusted(30, .increment, step: 10, in: 30...600), 40)
        XCTAssertEqual(SettingSlider<Double>.adjusted(30, .decrement, step: 10, in: 30...600), 30)
        XCTAssertEqual(SettingSlider<Float>.adjusted(0.095, .increment, step: 0.005, in: 0.01...0.10), 0.10,
                       accuracy: 1e-6)
        XCTAssertEqual(SettingSlider<Float>.adjusted(0.10, .increment, step: 0.005, in: 0.01...0.10), 0.10)
    }

    /// A value set beyond this screen's range (another screen allows more) isn't pulled back
    /// into it by a swipe the other way: up never lowers it, down never raises it.
    func test_aSwipe_neverMovesItTheWrongWay() {
        XCTAssertEqual(SettingSlider<Float>.adjusted(0.20, .increment, step: 0.005, in: 0.01...0.10), 0.20)
        XCTAssertEqual(SettingSlider<Float>.adjusted(0.005, .decrement, step: 0.005, in: 0.01...0.10), 0.005)
    }
}

/// One range and step for each posture setting that's on both settings screens and the Watch
/// (2026-10-16 audit). Posture Thresholds and Calibration had forward lean at 0.01–0.10 and
/// 0.03–0.30, twist at 5–30° and 5–45°, side lean at 0.02–0.20 and 0.03–0.25: a value set on one
/// could be out of the other's range. Now the wider range with the finer step, everywhere. The
/// Watch's `WatchSettingLimits` is a golden copy of these numbers.
@MainActor
final class PostureSettingLimitsTests: XCTestCase {

    func test_eachSetting_hasTheWiderRange_andTheFinerStep() {
        XCTAssertEqual(PostureSettingLimits.forwardCreep.range, 0.01...0.30)
        XCTAssertEqual(PostureSettingLimits.forwardCreep.step, 0.005)
        XCTAssertEqual(PostureSettingLimits.twist.range, 5...45)
        XCTAssertEqual(PostureSettingLimits.twist.step, 1)
        XCTAssertEqual(PostureSettingLimits.sideLean.range, 0.02...0.25)
        XCTAssertEqual(PostureSettingLimits.sideLean.step, 0.01)
    }

    /// Each default can be set on the slider: in range, and on a step.
    func test_eachDefault_isOnTheSlider() {
        let defaults = PostureThresholds()
        for (name, limits, value) in [
            ("forward lean", PostureSettingLimits.forwardCreep, defaults.forwardCreepThreshold),
            ("twist", PostureSettingLimits.twist, defaults.twistThreshold),
            ("side lean", PostureSettingLimits.sideLean, defaults.sideLeanThreshold),
        ] {
            XCTAssertTrue(limits.range.contains(value), name)
            let steps = (value - limits.range.lowerBound) / limits.step
            XCTAssertEqual(steps, steps.rounded(), accuracy: 1e-3, name)
        }
    }
}
