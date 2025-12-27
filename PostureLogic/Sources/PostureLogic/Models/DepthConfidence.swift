import CoreGraphics
import Foundation

public struct DepthAtPoint {
    public let point: CGPoint
    public let depth: Float
    public let confidence: Float
    
    public init(point: CGPoint, depth: Float, confidence: Float) {
        self.point = point
        self.depth = depth
        self.confidence = confidence
    }
}

public enum DepthConfidence: Comparable {
    case unavailable
    case low
    case medium
    case high
    
    public var numericValue: Float {
        switch self {
        case .unavailable: return 0.0
        case .low: return 0.3
        case .medium: return 0.6
        case .high: return 0.9
        }
    }
}
