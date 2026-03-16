import XCTest
import PostureLogic
@testable import Quant

final class PostureThresholdsExtensionTests: XCTestCase {

    func test_thresholdForKey_returnsCorrectFieldPerKey() {
        let thresholds = PostureThresholds()

        XCTAssertEqual(
            thresholds.threshold(for: .forwardCreep),
            thresholds.forwardCreepThreshold
        )
        XCTAssertEqual(
            thresholds.threshold(for: .headDrop),
            thresholds.headDropThreshold
        )
        XCTAssertEqual(
            thresholds.threshold(for: .shoulderRounding),
            thresholds.shoulderRoundingThreshold
        )
        XCTAssertEqual(
            thresholds.threshold(for: .lateralLean),
            thresholds.sideLeanThreshold
        )
        XCTAssertEqual(
            thresholds.threshold(for: .twist),
            thresholds.twistThreshold
        )
    }
}
