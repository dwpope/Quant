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

    /// The calibrated neutral head-carriage height, averaged over the calibration
    /// window. Same ear-based, shoulder-normalized quantity as
    /// `PoseSample.neckHeight`; `RawMetrics.headDrop` is `baseline.neckHeight −
    /// sample.neckHeight`, so a sample carrying its head lower than this neutral
    /// reads as positive head-drop. Default 0 keeps existing call sites and old
    /// serialized baselines valid (additive-default pattern, as with `shoulderTwist`).
    public let neckHeight: Float

    public init(timestamp: Date, shoulderMidpoint: SIMD3<Float>, headPosition: SIMD3<Float>, torsoAngle: Float, shoulderTwist: Float = 0, shoulderWidth: Float, depthAvailable: Bool, neckHeight: Float = 0) {
        self.timestamp = timestamp
        self.shoulderMidpoint = shoulderMidpoint
        self.headPosition = headPosition
        self.torsoAngle = torsoAngle
        self.shoulderTwist = shoulderTwist
        self.shoulderWidth = shoulderWidth
        self.depthAvailable = depthAvailable
        self.neckHeight = neckHeight
    }

    public func isStale(after interval: TimeInterval = 3600) -> Bool {
        Date().timeIntervalSince(timestamp) > interval
    }

    // MARK: - Codable (back-compat for additive fields)
    //
    // Custom coder so a persisted baseline that predates an additive field still
    // decodes: the synthesized `decode` throws on a missing key even with a default
    // init value. `shoulderTwist` and `neckHeight` are the additive-default fields,
    // decoded with `decodeIfPresent` and falling back to their defaults. Mirrors the
    // `SipEvent.label` pattern. Encoding stays complete.

    private enum CodingKeys: String, CodingKey {
        case timestamp, shoulderMidpoint, headPosition, torsoAngle, shoulderTwist,
             shoulderWidth, depthAvailable, neckHeight
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.shoulderMidpoint = try container.decode(SIMD3<Float>.self, forKey: .shoulderMidpoint)
        self.headPosition = try container.decode(SIMD3<Float>.self, forKey: .headPosition)
        self.torsoAngle = try container.decode(Float.self, forKey: .torsoAngle)
        self.shoulderTwist = try container.decodeIfPresent(Float.self, forKey: .shoulderTwist) ?? 0
        self.shoulderWidth = try container.decode(Float.self, forKey: .shoulderWidth)
        self.depthAvailable = try container.decode(Bool.self, forKey: .depthAvailable)
        self.neckHeight = try container.decodeIfPresent(Float.self, forKey: .neckHeight) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(shoulderMidpoint, forKey: .shoulderMidpoint)
        try container.encode(headPosition, forKey: .headPosition)
        try container.encode(torsoAngle, forKey: .torsoAngle)
        try container.encode(shoulderTwist, forKey: .shoulderTwist)
        try container.encode(shoulderWidth, forKey: .shoulderWidth)
        try container.encode(depthAvailable, forKey: .depthAvailable)
        try container.encode(neckHeight, forKey: .neckHeight)
    }
}
