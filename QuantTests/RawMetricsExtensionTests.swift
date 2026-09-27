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
}
