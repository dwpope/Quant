import Combine
import XCTest
import PostureLogic
@testable import Quant

/// The forward-lean line moved from 3% to 6% on 2026-10-10 (see
/// `PostureThresholds.forwardCreepThreshold`). A 0.03 stored before then, on the phone or sent
/// from the Watch, mustn't hold the new line back.
@MainActor
final class ForwardCreepSettingTests: XCTestCase {

    func test_theDefault_isSixPercent() {
        XCTAssertEqual(AppModel.defaultForwardCreepThreshold, 0.06)
    }

    func test_aValueStoredBeforeTheMove_isIgnored() {
        UserDefaults.standard.set(Float(0.03), forKey: "com.quant.posture.forwardCreep")
        defer { UserDefaults.standard.removeObject(forKey: "com.quant.posture.forwardCreep") }
        XCTAssertEqual(AppModel().forwardCreepThreshold, 0.06)
    }

    /// A Watch on an older build still sends the old key: ignored.
    func test_theOldKeyFromTheWatch_isIgnored() {
        let model = AppModel()
        model.watchService.settingsReceived.send([
            "type": "settings", "com.quant.posture.forwardCreep": Float(0.03),
        ])
        XCTAssertEqual(model.forwardCreepThreshold, 0.06)
    }
}
