import XCTest
import Combine
import PostureLogic
@testable import Quant

final class SwitchablePoseProviderTests: XCTestCase {

    func test_forwardsFramesFromAttachedSource() async throws {
        let provider = SwitchablePoseProvider()
        let mock = MockPoseProvider()
        try await mock.start()
        provider.attach(source: mock)

        let expectation = expectation(description: "Frame forwarded")
        let cancellable = provider.framePublisher.sink { _ in
            expectation.fulfill()
        }

        let frame = InputFrame(
            timestamp: 0,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )
        mock.emit(frame: frame)

        await fulfillment(of: [expectation], timeout: 1)
        cancellable.cancel()
    }

    func test_detachStopsForwarding() async throws {
        let provider = SwitchablePoseProvider()
        let mock = MockPoseProvider()
        try await mock.start()
        provider.attach(source: mock)
        provider.detach()

        let expectation = expectation(description: "No frame after detach")
        expectation.isInverted = true
        let cancellable = provider.framePublisher.sink { _ in
            expectation.fulfill()
        }

        let frame = InputFrame(
            timestamp: 0,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )
        mock.emit(frame: frame)

        await fulfillment(of: [expectation], timeout: 0.3)
        cancellable.cancel()
    }

    func test_reattachSwitchesSource() async throws {
        let provider = SwitchablePoseProvider()
        let mockA = MockPoseProvider()
        let mockB = MockPoseProvider()
        try await mockA.start()
        try await mockB.start()

        // Attach A, then replace with B
        provider.attach(source: mockA)
        provider.attach(source: mockB)

        // Frame from B should arrive
        let arrivedFromB = expectation(description: "Frame from B arrives")
        var cancellable = provider.framePublisher.sink { _ in
            arrivedFromB.fulfill()
        }

        let frame = InputFrame(
            timestamp: 0,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )
        mockB.emit(frame: frame)
        await fulfillment(of: [arrivedFromB], timeout: 1)
        cancellable.cancel()

        // Frame from A should NOT arrive
        let notFromA = expectation(description: "No frame from A")
        notFromA.isInverted = true
        cancellable = provider.framePublisher.sink { _ in
            notFromA.fulfill()
        }

        mockA.emit(frame: frame)
        await fulfillment(of: [notFromA], timeout: 0.3)
        cancellable.cancel()
    }
}
