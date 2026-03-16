import XCTest
@testable import Quant

final class MetricInfoTests: XCTestCase {

    func test_isExceeded_trueWhenRatioEqualsOne() {
        let info = MetricInfo(key: .forwardCreep, value: 0.1, ratio: 1.0, threshold: 0.1, isWorstOffender: false)
        XCTAssertTrue(info.isExceeded)
    }

    func test_isExceeded_trueWhenRatioAboveOne() {
        let info = MetricInfo(key: .headDrop, value: 0.2, ratio: 1.5, threshold: 0.1, isWorstOffender: false)
        XCTAssertTrue(info.isExceeded)
    }

    func test_isExceeded_falseWhenRatioBelowOne() {
        let info = MetricInfo(key: .twist, value: 0.05, ratio: 0.5, threshold: 0.1, isWorstOffender: false)
        XCTAssertFalse(info.isExceeded)
    }

    func test_clampedRatio_capsAtOne() {
        let info = MetricInfo(key: .lateralLean, value: 0.3, ratio: 2.5, threshold: 0.1, isWorstOffender: true)
        XCTAssertEqual(info.clampedRatio, 1.0)
    }

    func test_clampedRatio_passesThroughValuesBelowOne() {
        let info = MetricInfo(key: .shoulderRounding, value: 0.04, ratio: 0.4, threshold: 0.1, isWorstOffender: false)
        XCTAssertEqual(info.clampedRatio, 0.4)
    }
}
