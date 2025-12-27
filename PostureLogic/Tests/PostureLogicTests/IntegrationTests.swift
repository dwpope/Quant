import XCTest
@testable import PostureLogic

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
        XCTAssertEqual(output?.trackingQuality, .good)
    }
}
