import XCTest
@testable import PostureLogic

final class DepthServiceTests: XCTestCase {

    func test_depthConfidence_returnsUnavailable_whenNoDepthMap() {
        // Given
        var service = DepthService()
        let frame = InputFrame(
            timestamp: 0,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )

        // When
        let confidence = service.computeConfidence(from: frame)

        // Then
        XCTAssertEqual(confidence, .unavailable)
    }

    func test_sampleDepth_returnsZeroConfidence_whenNoDepthMap() {
        // Given
        var service = DepthService()
        let frame = InputFrame(
            timestamp: 0,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )
        let points = [
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.3, y: 0.7)
        ]

        // When
        let samples = service.sampleDepth(at: points, from: frame)

        // Then
        XCTAssertEqual(samples.count, 2)
        for sample in samples {
            XCTAssertEqual(sample.depth, 0)
            XCTAssertEqual(sample.confidence, 0)
        }
    }

    func test_sampleDepth_returnsZeroConfidence_forOutOfBoundsPoints() {
        // Given
        var service = DepthService()
        let frame = InputFrame(
            timestamp: 0,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )
        let points = [
            CGPoint(x: -0.1, y: 0.5),  // Negative
            CGPoint(x: 1.5, y: 0.5),   // > 1.0
            CGPoint(x: 0.5, y: -0.1),  // Negative
            CGPoint(x: 0.5, y: 1.5)    // > 1.0
        ]

        // When
        let samples = service.sampleDepth(at: points, from: frame)

        // Then
        XCTAssertEqual(samples.count, 4)
        for sample in samples {
            XCTAssertEqual(sample.confidence, 0)
        }
    }

    func test_debugState_includesLastConfidence() {
        // Given
        var service = DepthService()
        let frame = InputFrame(
            timestamp: 0,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil
        )

        // When
        _ = service.computeConfidence(from: frame)
        let debugState = service.debugState

        // Then
        XCTAssertNotNil(debugState["lastConfidence"])
        XCTAssertEqual(debugState["lastConfidence"] as? String, "unavailable")
    }
}
