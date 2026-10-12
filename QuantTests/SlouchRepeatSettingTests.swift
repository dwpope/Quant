import XCTest
import PostureLogic
@testable import Quant

/// A slouch left uncorrected after its nudge is nudged again every minute since 2026-10-12 (see
/// `PostureThresholds.nudgeCooldown`). A value stored before then, the 10-minute default from
/// "Reset to defaults", mustn't hold the minute back.
@MainActor
final class SlouchRepeatSettingTests: XCTestCase {

    func test_theDefault_isAMinute() {
        XCTAssertEqual(AppModel.defaultNudgeCooldown, 60)
    }

    func test_aValueStoredBeforeTheMinute_isIgnored() {
        UserDefaults.standard.set(600.0, forKey: "com.quant.posture.nudgeCooldown")
        defer { UserDefaults.standard.removeObject(forKey: "com.quant.posture.nudgeCooldown") }
        XCTAssertEqual(AppModel().nudgeCooldown, 60)
    }
}
