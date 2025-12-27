import Foundation

public struct RawMetrics: Codable {
    public let timestamp: TimeInterval
    
    public let forwardCreep: Float
    public let headDrop: Float
    public let shoulderRounding: Float
    public let lateralLean: Float
    public let twist: Float
    
    public let movementLevel: Float
    public let headMovementPattern: MovementPattern
    
    public init(timestamp: TimeInterval, forwardCreep: Float, headDrop: Float, shoulderRounding: Float, lateralLean: Float, twist: Float, movementLevel: Float, headMovementPattern: MovementPattern) {
        self.timestamp = timestamp
        self.forwardCreep = forwardCreep
        self.headDrop = headDrop
        self.shoulderRounding = shoulderRounding
        self.lateralLean = lateralLean
        self.twist = twist
        self.movementLevel = movementLevel
        self.headMovementPattern = headMovementPattern
    }
}

public enum MovementPattern: String, Codable {
    case still
    case smallOscillations
    case largeMovements
    case erratic
}
