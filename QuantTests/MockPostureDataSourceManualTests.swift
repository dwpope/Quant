import XCTest
@testable import Quant
import PostureLogic

@MainActor
final class MockPostureDataSourceManualTests: XCTestCase {

    func test_manualSliderAtThreshold_producesRatioOne() {
        let source = MockPostureDataSource()
        source.isAutoSimulating = false

        let threshold = source.simulationThresholds.headDropThreshold
        source.manualHeadDrop = threshold

        let data = source.currentData
        let headDropInfo = data.metric(for: .headDrop)
        XCTAssertEqual(headDropInfo.ratio, 1.0, accuracy: 0.001,
                       "Ratio should be 1.0 when manual value equals threshold")
    }

    func test_badStateWithZeroMetrics_doesNotCrash() {
        let source = MockPostureDataSource()
        source.isAutoSimulating = false
        source.manualPostureState = .bad(since: Date().timeIntervalSince1970 - 10)

        // All sliders default to 0.0 — access currentData to verify no crash
        let data = source.currentData
        XCTAssertTrue(data.postureState.isBad,
                      "State should be bad even with zero metrics")
        XCTAssertNil(data.worstOffender,
                     "No worst offender when all metrics are zero")
    }
}
