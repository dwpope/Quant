import XCTest
import PostureLogic
@testable import Quant

/// Head drop counts the way it reads on the device, negative as the head drops, since 2026-10-05
/// (see `PostureThresholds.headDropThreshold`).
/// The setting's meaning changed with it, so a value stored under the old meaning must not carry
/// over: 0.15 would need a huge drop and silence the signal.
@MainActor
final class HeadDropSettingTests: XCTestCase {

    /// 0.0175 since 2026-11-17: at 0.020 Dave's neck strained and the app stayed green. (0.020
    /// from 2026-11-09, when sitting well flickered across 0.015.)
    func test_theDefault_isBetweenSittingWellAndAStrainedNeck() {
        XCTAssertEqual(AppModel.defaultHeadDropThreshold, 0.0175)
    }

    func test_aValueStoredUnderTheOldMeaning_isIgnored() {
        UserDefaults.standard.set(Float(0.15), forKey: "com.quant.posture.headDrop")
        defer { UserDefaults.standard.removeObject(forKey: "com.quant.posture.headDrop") }
        XCTAssertEqual(AppModel().headDropThreshold, 0.0175)
    }

    /// The old default, stored when the slider was touched, mustn't keep the flicker going.
    func test_aValueStoredBeforeTheNewLine_isIgnored() {
        UserDefaults.standard.set(Float(0.015), forKey: "com.quant.posture.headDrop.v2")
        defer { UserDefaults.standard.removeObject(forKey: "com.quant.posture.headDrop.v2") }
        XCTAssertEqual(AppModel().headDropThreshold, 0.0175)
    }

    /// 0.020, stored when the setting was touched or reset, mustn't keep the strain green.
    func test_aValueStoredBeforeTheTighterLine_isIgnored() {
        UserDefaults.standard.set(Float(0.020), forKey: "com.quant.posture.headDrop.v3")
        defer { UserDefaults.standard.removeObject(forKey: "com.quant.posture.headDrop.v3") }
        XCTAssertEqual(AppModel().headDropThreshold, 0.0175)
    }
}
