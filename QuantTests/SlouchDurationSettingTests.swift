import XCTest
import PostureLogic
@testable import Quant

/// A nudge after a minute of slouching, added up, since 2026-10-08 (see
/// `PostureThresholds.slouchDurationBeforeNudge`). A value stored before then, 300 s of unbroken
/// slouching or the 2-minute default from "Reset to defaults", mustn't hold the minute back.
@MainActor
final class SlouchDurationSettingTests: XCTestCase {

    func test_theDefault_isAMinute() {
        XCTAssertEqual(AppModel.defaultSlouchDurationBeforeNudge, 60)
    }

    func test_aValueStoredBeforeTheMinute_isIgnored() {
        UserDefaults.standard.set(120.0, forKey: "com.quant.posture.slouchDuration")
        defer { UserDefaults.standard.removeObject(forKey: "com.quant.posture.slouchDuration") }
        XCTAssertEqual(AppModel().slouchDurationBeforeNudge, 60)
    }
}
