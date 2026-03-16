import XCTest
import PostureLogic
@testable import Quant

final class RawMetricsExtensionTests: XCTestCase {

    func test_zero_returnsAllZeroValues() {
        let zero = RawMetrics.zero
        XCTAssertEqual(zero.forwardCreep, 0)
        XCTAssertEqual(zero.headDrop, 0)
        XCTAssertEqual(zero.shoulderRounding, 0)
        XCTAssertEqual(zero.lateralLean, 0)
        XCTAssertEqual(zero.twist, 0)
        XCTAssertEqual(zero.movementLevel, 0)
        XCTAssertEqual(zero.timestamp, 0)
    }

    func test_valueForKey_returnsCorrectFieldPerKey() {
        let metrics = RawMetrics(
            timestamp: 1,
            forwardCreep: 0.1,
            headDrop: 0.2,
            shoulderRounding: 0.3,
            lateralLean: 0.4,
            twist: 0.5,
            movementLevel: 0.6,
            headMovementPattern: .still
        )

        XCTAssertEqual(metrics.value(for: .forwardCreep), 0.1, accuracy: 0.001)
        XCTAssertEqual(metrics.value(for: .headDrop), 0.2, accuracy: 0.001)
        XCTAssertEqual(metrics.value(for: .shoulderRounding), 0.3, accuracy: 0.001)
        XCTAssertEqual(metrics.value(for: .lateralLean), 0.4, accuracy: 0.001)
        XCTAssertEqual(metrics.value(for: .twist), 0.5, accuracy: 0.001)
    }
}
