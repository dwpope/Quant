import CoreGraphics
import Foundation
import simd

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

    /// The same Layer-1 head orientation as `externalHeadAngles`, carried as a raw
    /// quaternion (screen-frame rotation) threaded through from
    /// `InputFrame.externalHeadOrientation`. Runs parallel to the decomposed Euler
    /// angles so a later stage can drive the figure head from the quaternion
    /// directly. **Viz-only** — never feeds scoring. `nil` on every non-ARKit-face
    /// path. Never serialized (derived fresh each frame).
    public let externalHeadOrientation: simd_quatf?

    public init(
        timestamp: TimeInterval,
        keypoints: [Keypoint],
        confidence: Float,
        externalHeadAngles: HeadAngles? = nil,
        externalHeadOrientation: simd_quatf? = nil
    ) {
        self.timestamp = timestamp
        self.keypoints = keypoints
        self.confidence = confidence
        self.externalHeadAngles = externalHeadAngles
        self.externalHeadOrientation = externalHeadOrientation
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
