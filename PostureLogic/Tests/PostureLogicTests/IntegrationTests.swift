import XCTest
@testable import PostureLogic

final class IntegrationTests: XCTestCase {
    func test_mockFrameFlowsThroughPipeline() async throws {
        // Given
        let mock = MockPoseProvider()
        let pipeline = Pipeline(provider: mock)

        try await mock.start()

        // When — emit a frame with no pixel buffer (PoseService can't extract keypoints)
        mock.emit(frame: TestScenarios.goodPosture.frames[0])

        await pipeline.settled()

        // Then — no valid pose observation means fusion returns nil, so no sample published
        let output = pipeline.latestSample
        XCTAssertNil(output, "No sample should be published without valid pose keypoints")
    }

    func test_ticket02_arkitIntegrationPattern() async throws {
        // Test that simulates ARSessionService behavior from ticket 0.2
        let mock = MockPoseProvider()
        let pipeline = Pipeline(provider: mock)

        // Simulate starting AR session
        try await mock.start()

        // Create a frame similar to what ARSessionService would provide
        let testFrame = InputFrame(
            timestamp: 123456.789,
            pixelBuffer: nil, // ARKit would provide CVPixelBuffer here
            depthMap: nil,    // LiDAR devices would provide depth map
            cameraIntrinsics: nil // ARKit camera intrinsics
        )

        // Emit frame like ARSessionService does
        mock.emit(frame: testFrame)

        await pipeline.settled()

        // Without a pixel buffer, PoseService returns nil, so PoseDepthFusion
        // has no observation to work with — latestSample remains nil
        let sample = pipeline.latestSample
        XCTAssertNil(sample, "No sample without pixel buffer for pose detection")

        // Verify pipeline still updates mode to 2D when no depth is available
        XCTAssertEqual(pipeline.currentMode, .twoDOnly, "Should default to 2D mode without depth")

        print("Ticket 0.2 ARKit integration pattern verified")
    }
}
