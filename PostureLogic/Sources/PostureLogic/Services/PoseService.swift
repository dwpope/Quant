import Vision
import CoreGraphics
import Foundation

/// Service for extracting body pose keypoints from input frames using Vision framework
///
/// Features:
/// - Throttles processing to ~10 FPS to avoid performance issues
/// - Handles nil pixel buffers gracefully
/// - Corrects Vision's flipped Y coordinates
/// - Maps Vision keypoints to our Joint enum
public final class PoseService: PoseServiceProtocol {
    // MARK: - DebugDumpable

    public var debugState: [String: Any] {
        [
            "lastProcessTime": lastProcessTime,
            "keypointsFound": lastKeypointCount,
            "lastConfidence": lastConfidence,
            "framesThrottled": framesThrottled
        ]
    }

    // MARK: - Private Properties

    private var lastProcessTime: TimeInterval = 0
    private var lastKeypointCount: Int = 0
    private var lastConfidence: Float = 0
    private var framesThrottled: Int = 0
    private let minFrameInterval: TimeInterval = 0.1  // ~10 FPS

    // MARK: - Initialization

    public init() {}

    // MARK: - PoseServiceProtocol

    public func process(frame: InputFrame) async -> PoseObservation? {
        // Throttle to avoid processing every frame
        guard frame.timestamp - lastProcessTime >= minFrameInterval else {
            framesThrottled += 1
            return nil  // Throttled
        }

        guard let pixelBuffer = frame.pixelBuffer else {
            print("⚠️ PoseService: No pixel buffer in frame")
            return nil  // No pixel buffer to process
        }

        lastProcessTime = frame.timestamp

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])

            guard let observation = request.results?.first else {
                lastKeypointCount = 0
                print("⚠️ PoseService: Vision returned no results")
                return nil  // No pose detected
            }

            let keypoints = try extractKeypoints(from: observation)
            lastKeypointCount = keypoints.count
            lastConfidence = observation.confidence

            print("✓ PoseService: Detected \(keypoints.count) keypoints, confidence: \(observation.confidence)")

            return PoseObservation(
                timestamp: frame.timestamp,
                keypoints: keypoints,
                confidence: observation.confidence
            )
        } catch {
            // Vision request failed
            lastKeypointCount = 0
            print("❌ PoseService: Vision error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private Methods

    private func extractKeypoints(from observation: VNHumanBodyPoseObservation) throws -> [Keypoint] {
        var keypoints: [Keypoint] = []

        // Map our Joint enum to Vision's joint names
        let jointMapping: [(Joint, VNHumanBodyPoseObservation.JointName)] = [
            (.nose, .nose),
            (.leftEye, .leftEye),
            (.rightEye, .rightEye),
            (.leftEar, .leftEar),
            (.rightEar, .rightEar),
            (.leftShoulder, .leftShoulder),
            (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow),
            (.rightElbow, .rightElbow),
            (.leftWrist, .leftWrist),
            (.rightWrist, .rightWrist),
            (.leftHip, .leftHip),
            (.rightHip, .rightHip),
            (.leftKnee, .leftKnee),
            (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle),
            (.rightAnkle, .rightAnkle)
        ]

        for (joint, visionJoint) in jointMapping {
            if let recognizedPoint = try? observation.recognizedPoint(visionJoint),
               recognizedPoint.confidence > 0.1 {  // Filter out very low confidence points

                // IMPORTANT: Vision returns flipped Y coordinates
                // We need to flip Y: 1.0 - point.y
                let correctedPosition = CGPoint(
                    x: recognizedPoint.location.x,
                    y: 1.0 - recognizedPoint.location.y
                )

                let keypoint = Keypoint(
                    joint: joint,
                    position: correctedPosition,
                    confidence: recognizedPoint.confidence
                )

                keypoints.append(keypoint)
            }
        }

        return keypoints
    }
}
