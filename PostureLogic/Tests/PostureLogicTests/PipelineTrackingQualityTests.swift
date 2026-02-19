import CoreGraphics
import XCTest
@testable import PostureLogic

final class PipelineTrackingQualityTests: XCTestCase {

    private func makeKeypoint(_ joint: Joint, x: CGFloat = 0.5, y: CGFloat = 0.5, confidence: Float = 0.9) -> Keypoint {
        Keypoint(joint: joint, position: CGPoint(x: x, y: y), confidence: confidence)
    }

    private var defaultCriticalKeypoints: [Keypoint] {
        [
            makeKeypoint(.leftShoulder, x: 0.2, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.8, y: 0.5),
            makeKeypoint(.nose, x: 0.5, y: 0.2),
        ]
    }

    private func makeObservation(confidence: Float, keypoints: [Keypoint]? = nil) -> PoseObservation {
        PoseObservation(
            timestamp: 0,
            keypoints: keypoints ?? defaultCriticalKeypoints,
            confidence: confidence
        )
    }

    func test_computeTrackingQuality_returnsLost_whenNoPixelBuffer() {
        let quality = Pipeline.computeTrackingQuality(
            poseObservation: makeObservation(confidence: 0.9),
            hasPixelBuffer: false,
            previousQuality: .good
        )

        XCTAssertEqual(quality, .lost)
    }

    func test_computeTrackingQuality_returnsLost_whenPoseObservationMissing() {
        let quality = Pipeline.computeTrackingQuality(
            poseObservation: nil,
            hasPixelBuffer: true,
            previousQuality: .good
        )

        XCTAssertEqual(quality, .lost)
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

    func test_computeTrackingQuality_requiresStrictlyGreaterThanUpgradeThreshold() {
        let observation = makeObservation(confidence: 0.65)

        let quality = Pipeline.computeTrackingQuality(
            poseObservation: observation,
            hasPixelBuffer: true,
            previousQuality: .lost
        )

        XCTAssertEqual(quality, .degraded, "At exactly 0.65, quality should remain .degraded because threshold is strict >.")
    }

    func test_computeTrackingQuality_staysGoodWhenAboveStayThreshold() {
        let observation = makeObservation(confidence: 0.76)

        let quality = Pipeline.computeTrackingQuality(
            poseObservation: observation,
            hasPixelBuffer: true,
            previousQuality: .good
        )

        XCTAssertEqual(quality, .good)
    }

    func test_computeTrackingQuality_requiresStrictlyGreaterThanStayThreshold() {
        let observation = makeObservation(confidence: 0.75)

        let quality = Pipeline.computeTrackingQuality(
            poseObservation: observation,
            hasPixelBuffer: true,
            previousQuality: .good
        )

        XCTAssertEqual(quality, .degraded, "At exactly 0.75, quality should drop to .degraded because threshold is strict >.")
    }

    func test_computeTrackingQuality_acceptsSingleShoulderPlusHeadAsTrackable() {
        let keypoints: [Keypoint] = [
            makeKeypoint(.rightShoulder, x: 0.7, y: 0.5),
            makeKeypoint(.nose, x: 0.5, y: 0.2),
        ]
        let observation = makeObservation(confidence: 0.70, keypoints: keypoints)

        let quality = Pipeline.computeTrackingQuality(
            poseObservation: observation,
            hasPixelBuffer: true,
            previousQuality: .lost
        )

        XCTAssertEqual(quality, .good)
    }

    func test_computeTrackingQuality_returnsDegraded_whenHeadMissingButKeypointCountHigh() {
        let keypoints: [Keypoint] = [
            makeKeypoint(.leftShoulder, x: 0.2, y: 0.5),
            makeKeypoint(.rightShoulder, x: 0.8, y: 0.5),
            makeKeypoint(.leftHip, x: 0.3, y: 0.7),
            makeKeypoint(.rightHip, x: 0.7, y: 0.7),
        ]
        let observation = makeObservation(confidence: 0.9, keypoints: keypoints)

        let result = Pipeline.computeTrackingQualityWithDiag(
            poseObservation: observation,
            hasPixelBuffer: true,
            previousQuality: .good
        )

        XCTAssertEqual(result.quality, .degraded)
        XCTAssertTrue(result.missingJoints.contains("Head"))
    }

    func test_computeTrackingQuality_returnsDegraded_whenNoShouldersButEnoughKeypointsFromGood() {
        let keypoints: [Keypoint] = [
            makeKeypoint(.nose, x: 0.5, y: 0.2),
            makeKeypoint(.leftEye, x: 0.45, y: 0.22),
            makeKeypoint(.rightEye, x: 0.55, y: 0.22),
        ]
        let observation = makeObservation(confidence: 0.9, keypoints: keypoints)

        let quality = Pipeline.computeTrackingQuality(
            poseObservation: observation,
            hasPixelBuffer: true,
            previousQuality: .good
        )

        XCTAssertEqual(quality, .degraded)
    }

    func test_computeTrackingQuality_returnsLost_whenNoShouldersAndTooFewKeypointsFromLost() {
        let keypoints: [Keypoint] = [
            makeKeypoint(.nose, x: 0.5, y: 0.2),
            makeKeypoint(.leftEye, x: 0.45, y: 0.22),
            makeKeypoint(.rightEye, x: 0.55, y: 0.22),
        ]
        let observation = makeObservation(confidence: 0.9, keypoints: keypoints)

        let quality = Pipeline.computeTrackingQuality(
            poseObservation: observation,
            hasPixelBuffer: true,
            previousQuality: .lost
        )

        XCTAssertEqual(quality, .lost)
    }

    func test_computeTrackingQuality_returnsDegraded_whenNoShouldersButEnoughKeypointsFromLost() {
        let keypoints: [Keypoint] = [
            makeKeypoint(.nose, x: 0.5, y: 0.2),
            makeKeypoint(.leftEye, x: 0.45, y: 0.22),
            makeKeypoint(.rightEye, x: 0.55, y: 0.22),
            makeKeypoint(.leftEar, x: 0.4, y: 0.22),
        ]
        let observation = makeObservation(confidence: 0.9, keypoints: keypoints)

        let quality = Pipeline.computeTrackingQuality(
            poseObservation: observation,
            hasPixelBuffer: true,
            previousQuality: .lost
        )

        XCTAssertEqual(quality, .degraded)
    }

    func test_computeTrackingQualityWithDiag_reportsNoPixelBufferReason() {
        let result = Pipeline.computeTrackingQualityWithDiag(
            poseObservation: makeObservation(confidence: 0.9),
            hasPixelBuffer: false,
            previousQuality: .good
        )

        XCTAssertEqual(result.quality, .lost)
        XCTAssertEqual(result.missingJoints, "no pixelBuffer")
    }

    func test_computeTrackingQualityWithDiag_reportsNoPoseReason() {
        let result = Pipeline.computeTrackingQualityWithDiag(
            poseObservation: nil,
            hasPixelBuffer: true,
            previousQuality: .good
        )

        XCTAssertEqual(result.quality, .lost)
        XCTAssertEqual(result.missingJoints, "no pose")
    }

    func test_computeTrackingQualityWithDiag_reportsNoneMissingWhenCriticalJointsPresent() {
        let result = Pipeline.computeTrackingQualityWithDiag(
            poseObservation: makeObservation(confidence: 0.9),
            hasPixelBuffer: true,
            previousQuality: .good
        )

        XCTAssertEqual(result.missingJoints, "none")
    }
}
