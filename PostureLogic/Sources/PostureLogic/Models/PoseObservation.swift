import CoreGraphics
import Foundation

public struct PoseObservation {
    public let timestamp: TimeInterval
    public let keypoints: [Keypoint]
    public let confidence: Float

    /// Head orientation from a *joint* 3D face-model fit (Vision rev-3's
    /// `VNFaceObservation.yaw/pitch/roll`), in DEGREES. Unlike the three independent
    /// 2D keypoint formulas in `PoseDepthFusion`, these three axes come from one
    /// consistent rotation, so a pure turn cannot leak into a phantom nod/tilt (the
    /// "W"). `computeHeadAngles` prefers them per-axis over the legacy estimate.
    ///
    /// Each is `nil` independently when Vision could not fit that axis (or no face
    /// was detected), so the legacy 2D formula transparently fills the gap — a strong
    /// turn that hides the face still tracks via the body-pose one-ear path.
    ///
    /// NOT part of the `Codable` `PoseSample`: derived fresh each frame, never
    /// serialized, so existing recordings/replay JSON are byte-for-byte unchanged.
    /// Sign is Vision-native (scaled to degrees); the *physical* render direction is
    /// owned by the live `headYaw/Pitch/RollGain` signs in the binding, exactly as
    /// the legacy signal's direction was dialled in.
    public let faceYaw: Float?
    public let facePitch: Float?
    public let faceRoll: Float?

    public init(
        timestamp: TimeInterval,
        keypoints: [Keypoint],
        confidence: Float,
        faceYaw: Float? = nil,
        facePitch: Float? = nil,
        faceRoll: Float? = nil
    ) {
        self.timestamp = timestamp
        self.keypoints = keypoints
        self.confidence = confidence
        self.faceYaw = faceYaw
        self.facePitch = facePitch
        self.faceRoll = faceRoll
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
