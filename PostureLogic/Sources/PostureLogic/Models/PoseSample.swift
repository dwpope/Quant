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

    /// Raw screen-frame head orientation as a quaternion stored `(x, y, z, w)`,
    /// parallel to the `headPitch/Yaw/Roll` Euler fields (which remain the fallback
    /// + compat signal). This is the recorded/replay boundary; `SIMD4<Float>` is
    /// `Codable`, and being optional with a `nil` default it is backward-compatible
    /// — old recordings (no `headOrientation` key) decode to `nil` via the synthesized
    /// `Codable`. **Viz-only** — scoring never reads it. `nil` on every non-ARKit-face
    /// path (the Euler fallback is used there).
    public let headOrientation: SIMD4<Float>?

    /// Ear-based head-carriage height: `(ear-midpoint.y − shoulder-midpoint.y) /
    /// shoulderWidth`, in Vision y-up image coordinates (larger y = physically
    /// higher). Scale-invariant like the other shoulder-normalized fields. This is
    /// a **2D body-pose** signal (ear + shoulder image keypoints, same domain as
    /// `torsoAngle`) — NOT a head-orientation angle — and it sources the refined
    /// `RawMetrics.headDrop`, which now tracks true neck/head carriage rather than
    /// the transient nose drop that `headPosition.y` picks up when merely looking
    /// down. Ear above shoulders ⇒ positive; head sinking toward the shoulders ⇒
    /// decreasing. Falls back to the already-resolved (nose-first) head Y when the
    /// ears aren't confidently detected (see `PoseDepthFusion.computeNeckHeight`).
    /// Default 0 keeps every existing `PoseSample(...)` call site (and old Codable
    /// recordings, which lack the key) valid — mirrors the additive-default pattern
    /// used for `headOrientation`.
    public let neckHeight: Float

    public init(timestamp: TimeInterval, depthMode: DepthMode, headPosition: SIMD3<Float>, shoulderMidpoint: SIMD3<Float>, leftShoulder: SIMD3<Float>, rightShoulder: SIMD3<Float>, torsoAngle: Float, headForwardOffset: Float, shoulderTwist: Float, shoulderWidthRaw: Float, trackingQuality: TrackingQuality, headPitch: Float = 0, headYaw: Float = 0, headRoll: Float = 0, headOrientation: SIMD4<Float>? = nil, neckHeight: Float = 0) {
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
        self.headOrientation = headOrientation
        self.neckHeight = neckHeight
    }

    // MARK: - Codable (back-compat for additive fields)
    //
    // The synthesized `Codable` decodes every key with `decode`, which THROWS on a
    // missing key even when the property has a default init value — so an old
    // recording that predates an additive field would fail to load. To keep those
    // recordings decoding (the documented additive-default contract), the
    // back-compat fields are decoded with `decodeIfPresent` and fall back to their
    // defaults. Same pattern the codebase already uses for `SipEvent.label`.
    // `neckHeight` is the field added for the ear-based `headDrop`; `headPitch/
    // Yaw/Roll` predate it but carry the same additive-default promise, made real
    // here. `headOrientation` is optional, so `decodeIfPresent` matches what the
    // synthesizer already did. Encoding stays complete (every key written).

    private enum CodingKeys: String, CodingKey {
        case timestamp, depthMode, headPosition, shoulderMidpoint, leftShoulder,
             rightShoulder, torsoAngle, headForwardOffset, shoulderTwist,
             shoulderWidthRaw, trackingQuality, headPitch, headYaw, headRoll,
             headOrientation, neckHeight
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        self.depthMode = try container.decode(DepthMode.self, forKey: .depthMode)
        self.headPosition = try container.decode(SIMD3<Float>.self, forKey: .headPosition)
        self.shoulderMidpoint = try container.decode(SIMD3<Float>.self, forKey: .shoulderMidpoint)
        self.leftShoulder = try container.decode(SIMD3<Float>.self, forKey: .leftShoulder)
        self.rightShoulder = try container.decode(SIMD3<Float>.self, forKey: .rightShoulder)
        self.torsoAngle = try container.decode(Float.self, forKey: .torsoAngle)
        self.headForwardOffset = try container.decode(Float.self, forKey: .headForwardOffset)
        self.shoulderTwist = try container.decode(Float.self, forKey: .shoulderTwist)
        self.shoulderWidthRaw = try container.decode(Float.self, forKey: .shoulderWidthRaw)
        self.trackingQuality = try container.decode(TrackingQuality.self, forKey: .trackingQuality)
        self.headPitch = try container.decodeIfPresent(Float.self, forKey: .headPitch) ?? 0
        self.headYaw = try container.decodeIfPresent(Float.self, forKey: .headYaw) ?? 0
        self.headRoll = try container.decodeIfPresent(Float.self, forKey: .headRoll) ?? 0
        self.headOrientation = try container.decodeIfPresent(SIMD4<Float>.self, forKey: .headOrientation)
        self.neckHeight = try container.decodeIfPresent(Float.self, forKey: .neckHeight) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(depthMode, forKey: .depthMode)
        try container.encode(headPosition, forKey: .headPosition)
        try container.encode(shoulderMidpoint, forKey: .shoulderMidpoint)
        try container.encode(leftShoulder, forKey: .leftShoulder)
        try container.encode(rightShoulder, forKey: .rightShoulder)
        try container.encode(torsoAngle, forKey: .torsoAngle)
        try container.encode(headForwardOffset, forKey: .headForwardOffset)
        try container.encode(shoulderTwist, forKey: .shoulderTwist)
        try container.encode(shoulderWidthRaw, forKey: .shoulderWidthRaw)
        try container.encode(trackingQuality, forKey: .trackingQuality)
        try container.encode(headPitch, forKey: .headPitch)
        try container.encode(headYaw, forKey: .headYaw)
        try container.encode(headRoll, forKey: .headRoll)
        try container.encodeIfPresent(headOrientation, forKey: .headOrientation)
        try container.encode(neckHeight, forKey: .neckHeight)
    }
}
