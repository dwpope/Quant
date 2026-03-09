import XCTest
@testable import PostureLogic

final class ThermalMonitorTests: XCTestCase {

    func test_nominalPolicy_fullOperation() {
        let policy = ThermalPolicy.policy(for: .nominal)
        XCTAssertEqual(policy.maxFPS, 10)
        XCTAssertTrue(policy.depthEnabled)
        XCTAssertFalse(policy.detectionPaused)
    }

    func test_fairPolicy_reducesFPS() {
        let policy = ThermalPolicy.policy(for: .fair)
        XCTAssertEqual(policy.maxFPS, 5)
        XCTAssertTrue(policy.depthEnabled)
        XCTAssertFalse(policy.detectionPaused)
    }

    func test_seriousPolicy_disablesDepth() {
        let policy = ThermalPolicy.policy(for: .serious)
        XCTAssertEqual(policy.maxFPS, 3)
        XCTAssertFalse(policy.depthEnabled)
        XCTAssertFalse(policy.detectionPaused)
    }

    func test_criticalPolicy_pausesDetection() {
        let policy = ThermalPolicy.policy(for: .critical)
        XCTAssertEqual(policy.maxFPS, 0)
        XCTAssertFalse(policy.depthEnabled)
        XCTAssertTrue(policy.detectionPaused)
    }

    func test_thermalLevelComparable() {
        XCTAssertTrue(ThermalLevel.nominal < .fair)
        XCTAssertTrue(ThermalLevel.fair < .serious)
        XCTAssertTrue(ThermalLevel.serious < .critical)
        XCTAssertFalse(ThermalLevel.critical < .nominal)
    }

    func test_mockThermalMonitor_publishesChanges() {
        let mock = MockThermalMonitor()
        XCTAssertEqual(mock.currentLevel, .nominal)
        XCTAssertEqual(mock.currentPolicy, .nominal)

        var received: [ThermalLevel] = []
        let cancellable = mock.levelPublisher
            .sink { received.append($0) }

        mock.setLevel(.fair)
        XCTAssertEqual(mock.currentLevel, .fair)
        XCTAssertEqual(mock.currentPolicy, .fair)

        mock.setLevel(.critical)
        XCTAssertEqual(mock.currentLevel, .critical)

        // Should have received: initial (.nominal) + .fair + .critical
        XCTAssertEqual(received, [.nominal, .fair, .critical])
        cancellable.cancel()
    }
}
