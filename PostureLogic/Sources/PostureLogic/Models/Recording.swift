import Foundation

public struct RecordedSession: Codable {
    public let id: UUID
    public let startTime: Date
    public let endTime: Date
    public let samples: [PoseSample]
    public let tags: [Tag]
    public let metadata: SessionMetadata
    
    public init(id: UUID, startTime: Date, endTime: Date, samples: [PoseSample], tags: [Tag], metadata: SessionMetadata) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.samples = samples
        self.tags = tags
        self.metadata = metadata
    }
}

public struct Tag: Codable {
    public let timestamp: TimeInterval
    public let label: TagLabel
    public let source: TagSource
    
    public init(timestamp: TimeInterval, label: TagLabel, source: TagSource) {
        self.timestamp = timestamp
        self.label = label
        self.source = source
    }
}

public enum TagLabel: String, Codable, CaseIterable {
    case goodPosture
    case slouching
    case reading
    case typing
    case stretching
    case absent
}

public enum TagSource: String, Codable {
    case manual
    case voice
    case automatic
}

public struct SessionMetadata: Codable {
    public let deviceModel: String
    public let depthAvailable: Bool
    public let thresholds: PostureThresholds

    /// The calibration baseline that was live when this session was recorded.
    ///
    /// Required to replay a session against the threshold engine: every `RawMetrics` field is
    /// a baseline-relative delta, so "what would the thresholds have said about this sample?"
    /// is unanswerable without it. It cannot be reconstructed afterwards — the live baseline
    /// lives in a single UserDefaults key, is cleared on recalibration, and is treated as
    /// stale after an hour — so it is captured here at record time or not at all.
    ///
    /// Optional, with an additive default of `nil` (the convention used by
    /// `Baseline.shoulderTwist` and `neckHeight`): sessions recorded before this field existed
    /// still decode, and a `nil` baseline is not encoded, so old and new files share one shape.
    /// A `nil` here means the session is not replayable against the engine.
    public let baseline: Baseline?

    public init(deviceModel: String, depthAvailable: Bool, thresholds: PostureThresholds, baseline: Baseline? = nil) {
        self.deviceModel = deviceModel
        self.depthAvailable = depthAvailable
        self.thresholds = thresholds
        self.baseline = baseline
    }
}
