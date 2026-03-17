import XCTest
import SwiftUI
import PostureLogic
@testable import Quant

final class PostureVisualStyleTests: XCTestCase {

    // MARK: - stateColor

    func test_stateColor_good_isTealGreen() {
        let color = PostureVisualStyle.stateColor(for: .good)
        let hue = color.hueComponent
        // Design doc: hue 0.38 ± 0.05
        XCTAssertEqual(hue, 0.38, accuracy: 0.05, "Good state should be teal-green")
    }

    func test_stateColor_bad_isCoralRed() {
        let color = PostureVisualStyle.stateColor(for: .bad(since: 0))
        let hue = color.hueComponent
        // Design doc: hue 0.02
        XCTAssertEqual(hue, 0.02, accuracy: 0.05, "Bad state should be coral-red")
    }

    func test_stateColor_absent_isSecondary() {
        // .absent and .calibrating return .secondary — just verify they don't crash
        _ = PostureVisualStyle.stateColor(for: .absent)
        _ = PostureVisualStyle.stateColor(for: .calibrating)
    }

    // MARK: - metricColor

    func test_metricColor_zeroRatio_isGreen() {
        let color = PostureVisualStyle.metricColor(ratio: 0.0)
        let hue = color.hueComponent
        // hue ≈ 0.35
        XCTAssertEqual(hue, 0.35, accuracy: 0.05)
    }

    func test_metricColor_fullRatio_isRed() {
        let color = PostureVisualStyle.metricColor(ratio: 1.0)
        let hue = color.hueComponent
        // hue ≈ 0.0
        XCTAssertEqual(hue, 0.0, accuracy: 0.05)
    }

    func test_metricColor_overThreshold_clamped() {
        let atOne = PostureVisualStyle.metricColor(ratio: 1.0)
        let atTwo = PostureVisualStyle.metricColor(ratio: 2.0)
        // Should be identical (clamped)
        XCTAssertEqual(atOne.hueComponent, atTwo.hueComponent, accuracy: 0.001)
    }

    // MARK: - nudgeCountdownLabel

    func test_nudgeCountdownLabel_275seconds() {
        let label = PostureVisualStyle.nudgeCountdownLabel(seconds: 275)
        XCTAssertEqual(label, "4:35")
    }

    func test_nudgeCountdownLabel_zero() {
        let label = PostureVisualStyle.nudgeCountdownLabel(seconds: 0)
        XCTAssertEqual(label, "0:00")
    }

    func test_nudgeCountdownLabel_60seconds() {
        let label = PostureVisualStyle.nudgeCountdownLabel(seconds: 60)
        XCTAssertEqual(label, "1:00")
    }

    // MARK: - stateLabel

    func test_stateLabel_allStates() {
        XCTAssertEqual(PostureVisualStyle.stateLabel(for: .absent), "Waiting")
        XCTAssertEqual(PostureVisualStyle.stateLabel(for: .calibrating), "Calibrating")
        XCTAssertEqual(PostureVisualStyle.stateLabel(for: .good), "Good")
        XCTAssertEqual(PostureVisualStyle.stateLabel(for: .drifting(since: 0)), "Drifting")
        XCTAssertEqual(PostureVisualStyle.stateLabel(for: .bad(since: 0)), "Bad")
    }

    // MARK: - stateAccessibilityLabel

    func test_stateAccessibilityLabel_withWorstOffender() {
        let info = MetricInfo(
            key: .headDrop, value: 0.1, ratio: 1.5, threshold: 0.06, isWorstOffender: true
        )
        let label = PostureVisualStyle.stateAccessibilityLabel(
            for: .bad(since: 0), worstOffender: info
        )
        XCTAssertTrue(label.contains("Bad"))
        XCTAssertTrue(label.contains("Head Drop"))
    }

    func test_stateAccessibilityLabel_withoutWorstOffender() {
        let label = PostureVisualStyle.stateAccessibilityLabel(for: .good, worstOffender: nil)
        XCTAssertEqual(label, "Good")
    }
}

// MARK: - Color Hue Helper

private extension Color {
    /// Extract the hue component from a SwiftUI Color.
    var hueComponent: Double {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        #if canImport(UIKit)
        UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        #endif
        return Double(hue)
    }
}
