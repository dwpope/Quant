import XCTest
import SwiftUI
@testable import Quant

final class PostureAnimationsTests: XCTestCase {

    func test_reducedMotion_alertOnset_isNotNil() {
        let anim = PostureAnimations.reducedMotion.alertOnset
        XCTAssertNotNil(anim)
    }

    func test_reducedMotion_metricUpdate_isNotNil() {
        let anim = PostureAnimations.reducedMotion.metricUpdate
        XCTAssertNotNil(anim)
    }

    func test_reducedMotion_nudgePulse_isNil() {
        // Repeating animations should be disabled under reduce-motion
        let anim = PostureAnimations.reducedMotion.nudgePulse
        XCTAssertNil(anim)
    }

    func test_reducedMotion_modeTransition_isNotNil() {
        let anim = PostureAnimations.reducedMotion.modeTransition
        XCTAssertNotNil(anim)
    }
}
