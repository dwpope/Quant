import XCTest
import PostureLogic
@testable import Quant

/// Head drop counts the way it reads on the device, negative as the head drops, since 2026-10-05
/// (see `PostureThresholds.headDropThreshold`).
/// The setting's meaning changed with it, so a value stored under the old meaning must not carry
/// over: 0.15 would need a huge drop and silence the signal.
@MainActor
final class HeadDropSettingTests: XCTestCase {

    /// 0.020 since 2026-11-09 (was 0.015): in the real-use session sitting well flickered across
    /// 0.015, which drove most of its slouched time and three nudges.
    func test_theDefault_clearsSittingWell() {
        XCTAssertEqual(AppModel.defaultHeadDropThreshold, 0.020)
    }

    func test_aValueStoredUnderTheOldMeaning_isIgnored() {
        UserDefaults.standard.set(Float(0.15), forKey: "com.quant.posture.headDrop")
        defer { UserDefaults.standard.removeObject(forKey: "com.quant.posture.headDrop") }
        XCTAssertEqual(AppModel().headDropThreshold, 0.020)
    }

    /// The old default, stored when the slider was touched, mustn't keep the flicker going.
    func test_aValueStoredBeforeTheNewLine_isIgnored() {
        UserDefaults.standard.set(Float(0.015), forKey: "com.quant.posture.headDrop.v2")
        defer { UserDefaults.standard.removeObject(forKey: "com.quant.posture.headDrop.v2") }
        XCTAssertEqual(AppModel().headDropThreshold, 0.020)
    }
}
