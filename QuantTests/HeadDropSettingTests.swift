import XCTest
import PostureLogic
@testable import Quant

/// Head drop counts a RISING head since 2026-10-05 (see `PostureThresholds.headDropThreshold`).
/// The setting's meaning changed with it, so a value stored under the old meaning must not carry
/// over: 0.15 would read as a huge rise and silence the signal.
@MainActor
final class HeadDropSettingTests: XCTestCase {

    func test_theDefault_isTheRisingHeadTripPoint() {
        XCTAssertEqual(AppModel.defaultHeadDropThreshold, 0.015)
    }

    func test_aValueStoredUnderTheOldMeaning_isIgnored() {
        UserDefaults.standard.set(Float(0.15), forKey: "com.quant.posture.headDrop")
        defer { UserDefaults.standard.removeObject(forKey: "com.quant.posture.headDrop") }
        XCTAssertEqual(AppModel().headDropThreshold, 0.015)
    }
}
