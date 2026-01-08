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
        let result = await service.process(frame: frame)

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
        _ = await service.process(frame: frame1)
        let result2 = await service.process(frame: frame2)
        _ = await service.process(frame: frame3)

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
        var processedCount = 0
        var throttledCount = 0

        // When - simulate 20 frames at varying intervals
        for i in 0..<20 {
            let timestamp = Double(i) * 0.05  // 50ms intervals (20 FPS input)
            let frame = InputFrame(
                timestamp: timestamp,
                pixelBuffer: nil,
                depthMap: nil,
                cameraIntrinsics: nil
            )

            let result = await service.process(frame: frame)
            if result != nil {
                processedCount += 1
            } else {
                throttledCount += 1
            }
        }

        // Then - with 50ms intervals and 100ms min interval, roughly half should be throttled
        // Since pixelBuffer is nil, all will return nil, but we can check debug state
        let debugState = service.debugState
        let framesThrottled = debugState["framesThrottled"] as? Int
        XCTAssertNotNil(framesThrottled)
        XCTAssertGreaterThan(framesThrottled!, 5, "Should have throttled multiple frames")
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
        _ = await service.process(frame: frame1)
        let initialThrottled = service.debugState["framesThrottled"] as? Int ?? 0

        _ = await service.process(frame: frame2)
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
        _ = await service.process(frame: frame)
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
        let frame1 = InputFrame(
            timestamp: 1.0,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )
        let frame2 = InputFrame(
            timestamp: 1.2,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )

        // When
        _ = await service.process(frame: frame1)
        let time1 = service.debugState["lastProcessTime"] as? TimeInterval

        _ = await service.process(frame: frame2)
        let time2 = service.debugState["lastProcessTime"] as? TimeInterval

        // Then
        XCTAssertEqual(time1, 1.0)
        XCTAssertEqual(time2, 1.2)
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
        _ = await service.process(frame: frame)
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
        _ = await service.process(frame: frame)
        let confidence = service.debugState["lastConfidence"] as? Float

        // Then
        // With nil pixel buffer, confidence will be 0
        XCTAssertEqual(confidence, 0)
    }
}
