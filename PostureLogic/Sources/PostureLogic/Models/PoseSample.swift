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

    public init(timestamp: TimeInterval, depthMode: DepthMode, headPosition: SIMD3<Float>, shoulderMidpoint: SIMD3<Float>, leftShoulder: SIMD3<Float>, rightShoulder: SIMD3<Float>, torsoAngle: Float, headForwardOffset: Float, shoulderTwist: Float, shoulderWidthRaw: Float, trackingQuality: TrackingQuality) {
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
    }
}
