import Vision
import CoreGraphics
import Foundation
import os.log

/// Service for extracting body pose keypoints from input frames using Vision framework
///
/// Features:
/// - Throttles processing to ~10 FPS to avoid performance issues
/// - Handles nil pixel buffers gracefully
/// - Corrects Vision's flipped Y coordinates
/// - Maps Vision keypoints to our Joint enum
/// - Instruments error paths with detailed logging for debugging
final class PoseService: PoseServiceProtocol {
    // MARK: - DebugDumpable

    var debugState: [String: Any] {
        [
            "lastProcessTime": lastProcessTime,
            "keypointsFound": lastKeypointCount,
            "lastConfidence": lastConfidence,
            "framesThrottled": framesThrottled,
            "noPoseDetected": noPoseDetectedCount,
            "visionErrors": visionErrorCount
        ]
    }

    // MARK: - Private Properties

    private var lastProcessTime: TimeInterval = -.infinity
    private var lastKeypointCount: Int = 0
    private var lastConfidence: Float = 0
    private var framesThrottled: Int = 0
    private var noPoseDetectedCount: Int = 0
    private var visionErrorCount: Int = 0
    private let minFrameInterval: TimeInterval = 0.1  // ~10 FPS
    private let logger = Logger(subsystem: "com.quant.posture", category: "PoseService")

    // MARK: - Initialization

    init() {}

    // MARK: - PoseServiceProtocol

    func process(frame: InputFrame) async -> PoseDetectionResult {
        // Throttle to avoid processing every frame
        guard frame.timestamp - lastProcessTime >= minFrameInterval else {
            framesThrottled += 1
            return .throttled
        }

        lastProcessTime = frame.timestamp

        guard let pixelBuffer = frame.pixelBuffer else {
            logger.debug("PoseService: No pixel buffer available in frame")
            return .failed
        }

        let request = VNDetectHumanBodyPoseRequest()
        // Joint face-model fit for decoupled head yaw/pitch/roll. Runs on the SAME
        // handler/buffer as the body pose (one perform, one ML pass scheduling) and
        // is purely additive — its results only populate the optional face fields and
        // never affect body keypoints, so a face failure degrades to the legacy path.
        let faceRequest = VNDetectFaceRectanglesRequest()
        faceRequest.revision = VNDetectFaceRectanglesRequestRevision3  // rev-3 supplies pitch (yaw/roll since rev-1/2)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request, faceRequest])
            guard let observation = request.results?.first else {
                noPoseDetectedCount += 1
                lastKeypointCount = 0
                logger.debug("PoseService: Vision detected no pose in frame (count: \(self.noPoseDetectedCount))")
                return .noPose
            }

            let keypoints = try extractKeypoints(from: observation)
            lastKeypointCount = keypoints.count
            lastConfidence = observation.confidence

            let faceAngles = extractFaceAngles(from: faceRequest.results)

            return .observation(PoseObservation(
                timestamp: frame.timestamp,
                keypoints: keypoints,
                confidence: observation.confidence,
                faceYaw: faceAngles.yaw,
                facePitch: faceAngles.pitch,
                faceRoll: faceAngles.roll
            ))
        } catch {
            visionErrorCount += 1
            lastKeypointCount = 0
            logger.error("PoseService: Vision request failed: \(error.localizedDescription) (count: \(self.visionErrorCount))")
            return .failed
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

    /// Minimum `VNFaceObservation.confidence` to trust a face's pose angles. Below
    /// this we drop to the legacy body-pose head estimate rather than feed a shaky
    /// fit into the figure.
    private static let minFaceConfidence: Float = 0.3

    /// Picks the most prominent confident face and converts its Vision-native
    /// yaw/pitch/roll (radians, `NSNumber?`) into the pipeline's degree convention.
    /// Returns all-nil when no usable face was fit, so `computeHeadAngles` falls back
    /// per-axis. Largest bounding box = the subject closest to camera (the user),
    /// not a face in the background.
    private func extractFaceAngles(
        from results: [VNFaceObservation]?
    ) -> (yaw: Float?, pitch: Float?, roll: Float?) {
        guard let face = results?
            .filter({ $0.confidence >= Self.minFaceConfidence })
            .max(by: { lhs, rhs in
                lhs.boundingBox.width * lhs.boundingBox.height
                    < rhs.boundingBox.width * rhs.boundingBox.height
            })
        else {
            return (nil, nil, nil)
        }

        return FaceAngleConversion.degrees(
            yawRadians: face.yaw?.floatValue,
            pitchRadians: face.pitch?.floatValue,
            rollRadians: face.roll?.floatValue
        )
    }
}
