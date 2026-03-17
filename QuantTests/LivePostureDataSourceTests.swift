import XCTest
import Combine
import PostureLogic
@testable import Quant

@MainActor
final class LivePostureDataSourceTests: XCTestCase {

    func test_initialData_matchesAppModelSnapshot() {
        let appModel = AppModel()
        let source = LivePostureDataSource(appModel: appModel)

        XCTAssertEqual(
            source.currentData.postureState,
            appModel.postureState
        )
        XCTAssertEqual(
            source.currentData.trackingQuality,
            appModel.trackingQuality
        )
    }

    func test_postureStateChange_propagates() async {
        let appModel = AppModel()
        let source = LivePostureDataSource(appModel: appModel)

        let expectation = XCTestExpectation(description: "currentData updates after postureState change")
        var cancellable: AnyCancellable?
        cancellable = source.$currentData
            .dropFirst()
            .sink { data in
                if case .good = data.postureState {
                    expectation.fulfill()
                }
                _ = cancellable
            }

        appModel.postureState = .good

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func test_currentData_neverNilAfterInit() {
        let appModel = AppModel()
        let source = LivePostureDataSource(appModel: appModel)

        // currentData should always have valid metrics
        XCTAssertEqual(source.currentData.metrics.count, 5)
    }

    func test_metricsChange_propagates() async {
        let appModel = AppModel()
        let source = LivePostureDataSource(appModel: appModel)

        let expectation = XCTestExpectation(description: "currentData updates after metrics change")
        var cancellable: AnyCancellable?
        cancellable = source.$currentData
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
                _ = cancellable
            }

        appModel.latestMetrics = .zero

        await fulfillment(of: [expectation], timeout: 2.0)
    }
}
