import XCTest
@testable import Quant
import PostureLogic

@MainActor
final class MockPostureDataSourcePreviewTests: XCTestCase {

    func test_previewGood_returnsGoodState() {
        let source = MockPostureDataSource.preview(state: .good)
        let data = source.currentData
        XCTAssertEqual(data.postureState, .good,
                       "Preview with .good state should produce .good postureState")
        XCTAssertFalse(data.isAlertMode,
                       "Good state should not be in alert mode")
    }

    func test_previewDrifting_returnsCorrectWorstOffender() {
        let since = Date().timeIntervalSince1970 - 45
        let source = MockPostureDataSource.preview(
            state: .drifting(since: since),
            worstMetric: .headDrop,
            worstRatio: 1.3
        )
        let data = source.currentData

        XCTAssertTrue(data.isAlertMode,
                      "Drifting state should be in alert mode")
        XCTAssertNotNil(data.worstOffender,
                        "Should have a worst offender when worstRatio > 1.0")
        XCTAssertEqual(data.worstOffender?.key, .headDrop,
                       "Worst offender should be headDrop")
        XCTAssertEqual(data.worstOffender?.ratio ?? 0, 1.3, accuracy: 0.001,
                       "Worst offender ratio should be 1.3")
    }
}
