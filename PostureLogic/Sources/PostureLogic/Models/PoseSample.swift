import simd
import Foundation

public struct PoseSample: Codable {
    public let timestamp: TimeInterval
    public let depthMode: DepthMode
    
    public let headPosition: SIMD3<Float>
    public let shoulderMidpoint: SIMD3<Float>
    public let leftShoulder: SIMD3<Float>
    public let rightShoulder: SIMD3<Float>
    
    public let torsoAngle: Float
    public let headForwardOffset: Float
    public let shoulderTwist: Float

    /// Raw shoulder width in image coordinates (0-1 range).
    /// Preserves the scale signal lost by normalization — needed for forward creep detection.
    public let shoulderWidthRaw: Float

    public let trackingQuality: TrackingQuality

    /// True head orientation in degrees, derived from facial keypoints
    /// (`nose`/`eye`/`ear`) independently of the shoulder skeleton — see
    /// `PoseDepthFusion.computeHeadAngles`. Sign conventions (y-up frame, larger
    /// `y` = physically higher): forward-head/chin-down → `headPitch` > 0;
    /// turn toward the subject's right (larger image-x) → `headYaw` > 0; left ear
    /// physically lower → `headRoll` > 0. Default 0 keeps every existing
    /// `PoseSample(...)` call site (and old Codable JSON) valid — mirrors the
    /// additive-default pattern used for `shoulderTwist` on `Baseline`.
    public let headPitch: Float
    public let headYaw: Float
    public let headRoll: Float

    public init(timestamp: TimeInterval, depthMode: DepthMode, headPosition: SIMD3<Float>, shoulderMidpoint: SIMD3<Float>, leftShoulder: SIMD3<Float>, rightShoulder: SIMD3<Float>, torsoAngle: Float, headForwardOffset: Float, shoulderTwist: Float, shoulderWidthRaw: Float, trackingQuality: TrackingQuality, headPitch: Float = 0, headYaw: Float = 0, headRoll: Float = 0) {
        self.timestamp = timestamp
        self.depthMode = depthMode
        self.headPosition = headPosition
        self.shoulderMidpoint = shoulderMidpoint
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
        self.torsoAngle = torsoAngle
        self.headForwardOffset = headForwardOffset
        self.shoulderTwist = shoulderTwist
        self.shoulderWidthRaw = shoulderWidthRaw
        self.trackingQuality = trackingQuality
        self.headPitch = headPitch
        self.headYaw = headYaw
        self.headRoll = headRoll
    }
}
