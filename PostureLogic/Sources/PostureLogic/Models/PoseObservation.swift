import CoreGraphics
import Foundation

public struct PoseObservation {
    public let timestamp: TimeInterval
    public let keypoints: [Keypoint]
    public let confidence: Float

    /// An authoritative, fully-decoupled head pose from an ARKit `ARFaceAnchor`
    /// (Layer 1), threaded through from `InputFrame.externalHeadAngles`. An
    /// all-or-nothing whole rotation (decoupled by construction, so a pure turn
    /// cannot leak into a phantom nod/tilt). When present it wins in
    /// `computeHeadAngles` over the legacy 2D estimate. `nil` on every non-ARKit-face
    /// path. Never serialized (derived fresh each frame, so recordings are unchanged).
    public let externalHeadAngles: HeadAngles?

    public init(
        timestamp: TimeInterval,
        keypoints: [Keypoint],
        confidence: Float,
        externalHeadAngles: HeadAngles? = nil
    ) {
        self.timestamp = timestamp
        self.keypoints = keypoints
        self.confidence = confidence
        self.externalHeadAngles = externalHeadAngles
    }
}

public struct Keypoint {
    public let joint: Joint
    public let position: CGPoint
    public let confidence: Float
    
    public init(joint: Joint, position: CGPoint, confidence: Float) {
        self.joint = joint
        self.position = position
        self.confidence = confidence
    }
}

public enum Joint: String, CaseIterable, Codable {
    case nose, leftEye, rightEye, leftEar, rightEar
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
}
