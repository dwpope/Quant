import simd
import Foundation

public struct Baseline: Codable {
    public let timestamp: Date
    public let shoulderMidpoint: SIMD3<Float>
    public let headPosition: SIMD3<Float>
    public let torsoAngle: Float
    public let shoulderTwist: Float
    public let shoulderWidth: Float
    public let depthAvailable: Bool

    public init(timestamp: Date, shoulderMidpoint: SIMD3<Float>, headPosition: SIMD3<Float>, torsoAngle: Float, shoulderTwist: Float = 0, shoulderWidth: Float, depthAvailable: Bool) {
        self.timestamp = timestamp
        self.shoulderMidpoint = shoulderMidpoint
        self.headPosition = headPosition
        self.torsoAngle = torsoAngle
        self.shoulderTwist = shoulderTwist
        self.shoulderWidth = shoulderWidth
        self.depthAvailable = depthAvailable
    }
    
    public func isStale(after interval: TimeInterval = 3600) -> Bool {
        Date().timeIntervalSince(timestamp) > interval
    }
}
