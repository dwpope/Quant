import XCTest
@testable import PostureLogic

@MainActor
final class IntegrationTests: XCTestCase {
    func test_mockFrameFlowsThroughPipeline() async throws {
        // Given
        let mock = MockPoseProvider()
        let pipeline = Pipeline(provider: mock)

        try await mock.start()

        // Wait for pipeline to subscribe (async safety)
        try await Task.sleep(nanoseconds: 100_000_000)

        // When
        mock.emit(frame: TestScenarios.goodPosture.frames[0])

        // Wait for pipeline to process
        // In a real async pipeline we might use expectation on publisher
        // For this simple sink, a short sleep is sufficient or checking immediately if synchronous dispatch
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then
        let output = pipeline.latestSample
        XCTAssertNotNil(output)
        // TestScenarios.goodPosture has nil pixel buffer, so tracking quality should be .lost
        XCTAssertEqual(output?.trackingQuality, .lost, "Without pixel buffer, tracking should be lost")
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

        // Wait for pipeline subscription
        try await Task.sleep(nanoseconds: 50_000_000)

        // Emit frame like ARSessionService does
        mock.emit(frame: testFrame)

        // Wait for processing
        try await Task.sleep(nanoseconds: 50_000_000)

        // Verify pipeline received and processed the frame
        let sample = pipeline.latestSample
        XCTAssertNotNil(sample, "Pipeline should process ARKit-like frames")
        XCTAssertEqual(sample?.timestamp, testFrame.timestamp, "Timestamp should match input frame")
        XCTAssertEqual(sample?.depthMode, .twoDOnly, "Should default to 2D mode without depth")

        print("✅ Ticket 0.2 ARKit integration pattern verified")
    }
}
