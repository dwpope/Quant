import Foundation

/// The request payload for the Jev posture proxy (`POST /classify`).
///
/// Pure and platform-free so it can be built and tested without a camera, a network or the app
/// target. The key names are the wire contract with `jev-proxy/src/classify.ts`; the rubric there
/// reasons about these names, so they were chosen to describe what the numbers ACTUALLY are.
/// That took correcting, and the corrections are the useful part of this type:
///
/// - `torso_lean_delta_degrees` was first called `shoulder_rounding_degrees`, but
///   `RawMetrics.shoulderRounding` is `sample.torsoAngle - baseline.torsoAngle` — a torso-lean
///   delta with no shoulder-protraction content at all.
/// - `shoulder_tilt_signed_degrees` was first called `twist_signed_degrees`, but
///   `RawMetrics.twistSigned` is `asin(Δy / width)` — one shoulder higher than the other, not
///   axial rotation. A rubric reasoning about "twist" was reasoning about physics the data
///   does not carry.
/// - `lateral_lean_in_shoulder_widths` was first called `..._normalised`, when nothing
///   normalised it. See `make` — this is the one piece of arithmetic here.
/// - `torso_angle_degrees` is camera-absolute rather than a delta, and when the hips are out of
///   frame — the normal case at a desk — it is a clamped proxy from head-to-shoulder height
///   rather than a measured angle. The rubric is told to weigh it lightly.
// `Codable`, not merely `Encodable`: the comparison record persists the exact payload that
// was sent, and step 3c has to read it back to know what Jev was actually asked.
public struct JevFeatures: Codable, Equatable {
    public let headYawDegrees: Float
    public let headPitchDegrees: Float
    public let headRollDegrees: Float
    public let forwardCreepFraction: Float
    public let headDropInShoulderWidths: Float
    public let torsoLeanDeltaDegrees: Float
    public let lateralLeanInShoulderWidths: Float
    public let shoulderTiltSignedDegrees: Float
    public let torsoAngleDegrees: Float
    public let trackingQuality: TrackingQuality
    public let depthMode: DepthMode

    enum CodingKeys: String, CodingKey {
        case headYawDegrees = "head_yaw_degrees"
        case headPitchDegrees = "head_pitch_degrees"
        case headRollDegrees = "head_roll_degrees"
        case forwardCreepFraction = "forward_creep_fraction_of_baseline_shoulder_width"
        case headDropInShoulderWidths = "head_drop_in_shoulder_widths"
        case torsoLeanDeltaDegrees = "torso_lean_delta_degrees"
        case lateralLeanInShoulderWidths = "lateral_lean_in_shoulder_widths"
        case shoulderTiltSignedDegrees = "shoulder_tilt_signed_degrees"
        case torsoAngleDegrees = "torso_angle_degrees"
        case trackingQuality = "tracking_quality"
        case depthMode = "depth_mode"
    }

    /// Builds a payload, or returns `nil` when one cannot honestly be built.
    ///
    /// Two refusals, both deliberate.
    ///
    /// **Degenerate baseline width.** `RawMetrics.lateralLeanSigned` is a raw
    /// `shoulderMidpoint.x` delta, and `shoulderMidpoint` lives in different spaces depending on
    /// the fusion path — normalised image coordinates in `.twoDOnly`, camera-space metres in
    /// `.depthFusion`. The same number therefore means a fraction of frame width in one mode and
    /// metres in the other. Dividing by `baseline.shoulderWidth`, which is expressed in whichever
    /// space produced it, makes the value dimensionless and comparable across modes — but only if
    /// that width is a real measurement, so a zero, tiny or negative width refuses instead.
    ///
    /// **Non-finite values.** The proxy rejects any non-finite number with a 400, and nothing
    /// upstream in this app guarantees finiteness. Refusing here turns a guaranteed failed
    /// request into a clean "no classification available", which is what the caller falls back
    /// from anyway.
    public static func make(sample: PoseSample, metrics: RawMetrics, baseline: Baseline) -> JevFeatures? {
        guard baseline.shoulderWidth.isFinite, baseline.shoulderWidth > 1e-6 else { return nil }

        let features = JevFeatures(
            headYawDegrees: sample.headYaw,
            headPitchDegrees: sample.headPitch,
            headRollDegrees: sample.headRoll,
            forwardCreepFraction: metrics.forwardCreep,
            headDropInShoulderWidths: metrics.headDrop,
            torsoLeanDeltaDegrees: metrics.shoulderRounding,
            lateralLeanInShoulderWidths: metrics.lateralLeanSigned / baseline.shoulderWidth,
            shoulderTiltSignedDegrees: metrics.twistSigned,
            torsoAngleDegrees: sample.torsoAngle,
            trackingQuality: sample.trackingQuality,
            depthMode: sample.depthMode
        )

        let numbers = [
            features.headYawDegrees, features.headPitchDegrees, features.headRollDegrees,
            features.forwardCreepFraction, features.headDropInShoulderWidths,
            features.torsoLeanDeltaDegrees, features.lateralLeanInShoulderWidths,
            features.shoulderTiltSignedDegrees, features.torsoAngleDegrees,
        ]
        guard numbers.allSatisfy({ $0.isFinite }) else { return nil }

        return features
    }
}

/// The proxy's 200 response. `posture` is deliberately a `String` rather than an enum: the class
/// list lives in the Worker's rubric so it can be revised without an app release, and a new class
/// must not fail to decode on an older build.
// `Codable` for the same reason as `JevFeatures`: the comparison record keeps the verdict it
// is comparing against, so 3c never has to re-ask.
public struct JevVerdict: Codable, Equatable {
    public let posture: String
    public let confidence: Double
    public let probabilities: [String: Double]
    public let model: String

    public init(posture: String, confidence: Double, probabilities: [String: Double], model: String) {
        self.posture = posture
        self.confidence = confidence
        self.probabilities = probabilities
        self.model = model
    }
}
