import XCTest
@testable import PostureLogic

final class PoseServiceTests: XCTestCase {

    func test_process_returnsNil_whenPixelBufferIsNil() async {
        // Given
        let service = PoseService()
        let frame = InputFrame(
            timestamp: 0,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )

        // When
        let result = await service.process(pixelBuffer: frame.pixelBuffer, timestamp: frame.timestamp)

        // Then
        XCTAssertNil(result, "Should return nil when pixel buffer is nil")
    }

    func test_process_throttlesFrames() async {
        // Given
        let service = PoseService()
        let frame1 = InputFrame(
            timestamp: 0.0,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )
        let frame2 = InputFrame(
            timestamp: 0.05,  // Only 50ms later - should be throttled
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )
        let frame3 = InputFrame(
            timestamp: 0.15,  // 150ms from first - should NOT be throttled
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )

        // When
        _ = await service.process(pixelBuffer: frame1.pixelBuffer, timestamp: frame1.timestamp)
        let result2 = await service.process(pixelBuffer: frame2.pixelBuffer, timestamp: frame2.timestamp)
        _ = await service.process(pixelBuffer: frame3.pixelBuffer, timestamp: frame3.timestamp)

        // Then
        XCTAssertNil(result2, "Should throttle frame that arrives too quickly")

        // Check debug state shows throttling
        let debugState = service.debugState
        let framesThrottled = debugState["framesThrottled"] as? Int
        XCTAssertNotNil(framesThrottled)
        XCTAssertGreaterThan(framesThrottled!, 0, "Should have throttled at least one frame")
    }

    func test_process_respectsMinFrameInterval() async {
        // Given
        let service = PoseService()

        // When - process frames with nil pixel buffers at 50ms intervals
        for i in 0..<20 {
            let timestamp = Double(i) * 0.05  // 50ms intervals (20 FPS input)
            _ = await service.process(pixelBuffer: nil, timestamp: timestamp)
        }

        // Then - with 50ms intervals and 100ms min interval, some frames should be throttled
        // Throttling happens before pixel buffer check, so nil buffers still get throttled
        let debugState = service.debugState
        let framesThrottled = debugState["framesThrottled"] as? Int
        XCTAssertNotNil(framesThrottled)
        XCTAssertGreaterThan(framesThrottled!, 0, "Should throttle some frames even with nil pixel buffers")
    }

    func test_process_allowsFramesAfterMinInterval() async {
        // Given
        let service = PoseService()
        let frame1 = InputFrame(
            timestamp: 0.0,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )
        let frame2 = InputFrame(
            timestamp: 0.11,  // Exactly over the 0.1s threshold
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )

        // When
        _ = await service.process(pixelBuffer: frame1.pixelBuffer, timestamp: frame1.timestamp)
        let initialThrottled = service.debugState["framesThrottled"] as? Int ?? 0

        _ = await service.process(pixelBuffer: frame2.pixelBuffer, timestamp: frame2.timestamp)
        let afterThrottled = service.debugState["framesThrottled"] as? Int ?? 0

        // Then
        XCTAssertEqual(initialThrottled, afterThrottled, "Should not throttle frame after min interval")
    }

    func test_debugState_includesExpectedKeys() async {
        // Given
        let service = PoseService()
        let frame = InputFrame(
            timestamp: 1.5,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )

        // When
        _ = await service.process(pixelBuffer: frame.pixelBuffer, timestamp: frame.timestamp)
        let debugState = service.debugState

        // Then
        XCTAssertNotNil(debugState["lastProcessTime"])
        XCTAssertNotNil(debugState["keypointsFound"])
        XCTAssertNotNil(debugState["lastConfidence"])
        XCTAssertNotNil(debugState["framesThrottled"])
    }

    func test_debugState_updatesLastProcessTime() async {
        // Given
        let service = PoseService()

        // When processing with nil pixel buffer, lastProcessTime should NOT be updated
        _ = await service.process(pixelBuffer: nil, timestamp: 1.0)
        let timeAfterNil = service.debugState["lastProcessTime"] as? TimeInterval

        // Should remain at default (0.0) when nil pixel buffer is passed
        XCTAssertEqual(timeAfterNil, 0.0, "lastProcessTime should not update for nil pixel buffer")
    }

    func test_debugState_tracksKeypointsFound() async {
        // Given
        let service = PoseService()
        let frame = InputFrame(
            timestamp: 0,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )

        // When
        _ = await service.process(pixelBuffer: frame.pixelBuffer, timestamp: frame.timestamp)
        let keypointsFound = service.debugState["keypointsFound"] as? Int

        // Then
        // With nil pixel buffer, no keypoints will be found
        XCTAssertEqual(keypointsFound, 0)
    }

    func test_debugState_tracksConfidence() async {
        // Given
        let service = PoseService()
        let frame = InputFrame(
            timestamp: 0,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )

        // When
        _ = await service.process(pixelBuffer: frame.pixelBuffer, timestamp: frame.timestamp)
        let confidence = service.debugState["lastConfidence"] as? Float

        // Then
        // With nil pixel buffer, confidence will be 0
        XCTAssertEqual(confidence, 0)
    }
}
