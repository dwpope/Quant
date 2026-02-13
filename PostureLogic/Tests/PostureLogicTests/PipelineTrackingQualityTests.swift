import CoreGraphics
import XCTest
@testable import PostureLogic

final class PipelineTrackingQualityTests: XCTestCase {

    private func makeObservation(confidence: Float) -> PoseObservation {
        let keypoints: [Keypoint] = [
            Keypoint(joint: .leftShoulder, position: CGPoint(x: 0.2, y: 0.5), confidence: 0.9),
            Keypoint(joint: .rightShoulder, position: CGPoint(x: 0.8, y: 0.5), confidence: 0.9),
            Keypoint(joint: .nose, position: CGPoint(x: 0.5, y: 0.2), confidence: 0.9),
        ]
        return PoseObservation(timestamp: 0, keypoints: keypoints, confidence: confidence)
    }

    func test_computeTrackingQuality_upgradesToGoodWithLowerThreshold() {
        let observation = makeObservation(confidence: 0.70)

        let quality = Pipeline.computeTrackingQuality(
            poseObservation: observation,
            hasPixelBuffer: true,
            previousQuality: .lost
        )

        XCTAssertEqual(quality, .good, "Should upgrade to .good when critical joints are present and confidence exceeds the upgrade threshold.")
    }

    func test_computeTrackingQuality_requiresHigherConfidenceToStayGood() {
        let observation = makeObservation(confidence: 0.70)

        let quality = Pipeline.computeTrackingQuality(
            poseObservation: observation,
            hasPixelBuffer: true,
            previousQuality: .good
        )

        XCTAssertEqual(quality, .degraded, "Should drop to .degraded when confidence is below the stay-good threshold.")
    }
}

