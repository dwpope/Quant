import CoreGraphics
import Foundation

public struct PoseObservation {
    public let timestamp: TimeInterval
    public let keypoints: [Keypoint]
    public let confidence: Float
    
    public init(timestamp: TimeInterval, keypoints: [Keypoint], confidence: Float) {
        self.timestamp = timestamp
        self.keypoints = keypoints
        self.confidence = confidence
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
