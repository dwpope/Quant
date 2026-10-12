import XCTest
import PostureLogic
@testable import Quant

/// The phone's threshold sliders reach the Watch (2026-10-11).
///
/// Forward lean, twist, side lean and the grace period are on both the phone's and the Watch's
/// settings screens. Changed on the phone, they updated the pipeline but were never sent, and
/// the Watch sends all its settings when any of its sliders moves: the next touch there put the
/// phone back to the Watch's old values.
@MainActor
final class WatchThresholdSyncTests: XCTestCase {

    private let keys = [
        "com.quant.posture.forwardCreep.v2", "com.quant.posture.twist",
        "com.quant.posture.sideLean", "com.quant.posture.driftingToBad",
    ]

    override func setUp() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
    override func tearDown() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    func test_eachSharedThreshold_isSentToTheWatch() {
        let model = AppModel()
        let changes: [(String, () -> Void)] = [
            ("forward lean", { model.forwardCreepThreshold = 0.09 }),
            ("twist", { model.twistThreshold = 20 }),
            ("side lean", { model.sideLeanThreshold = 0.1 }),
            ("grace", { model.driftingToBadThreshold = 90 }),
        ]
        for (name, change) in changes {
            let before = model.settingsSyncTask
            change()
            XCTAssertNotNil(model.settingsSyncTask, name)
            XCTAssertNotEqual(model.settingsSyncTask, before, "\(name) is sent to the Watch")
        }
    }
}
