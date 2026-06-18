import Foundation

public struct RawMetrics: Codable {
    public let timestamp: TimeInterval
    
    public let forwardCreep: Float
    public let headDrop: Float
    public let shoulderRounding: Float
    /// Unsigned lateral sway from the calibrated centre — the magnitude posture
    /// scoring thresholds on (`PostureEngine`'s `sideLeanThreshold`). Direction is
    /// intentionally discarded here; use `lateralLeanSigned` when you need it.
    public let lateralLean: Float
    /// Signed lateral sway (`+` = shoulder-midpoint right of baseline in image-x,
    /// `−` = left). Same magnitude as `lateralLean`, but keeps the left/right sense
    /// the visualization needs to lean the figure the correct way. Not used by
    /// scoring. Defaults to 0 so older construction sites stay valid.
    public let lateralLeanSigned: Float
    /// Unsigned shoulder twist from the calibrated rest — the magnitude scoring
    /// thresholds on. Direction discarded; use `twistSigned` when you need it.
    public let twist: Float
    /// Signed shoulder twist (same magnitude as `twist`, keeps left/right sense for
    /// the visualization's torso rotation). Not used by scoring. Defaults to 0.
    public let twistSigned: Float

    public let movementLevel: Float
    public let headMovementPattern: MovementPattern

    public init(timestamp: TimeInterval, forwardCreep: Float, headDrop: Float, shoulderRounding: Float, lateralLean: Float, twist: Float, movementLevel: Float, headMovementPattern: MovementPattern, lateralLeanSigned: Float = 0, twistSigned: Float = 0) {
        self.timestamp = timestamp
        self.forwardCreep = forwardCreep
        self.headDrop = headDrop
        self.shoulderRounding = shoulderRounding
        self.lateralLean = lateralLean
        self.lateralLeanSigned = lateralLeanSigned
        self.twist = twist
        self.twistSigned = twistSigned
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
