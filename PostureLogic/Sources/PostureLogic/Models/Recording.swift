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

public enum TagLabel: String, Codable {
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
    
    public init(deviceModel: String, depthAvailable: Bool, thresholds: PostureThresholds) {
        self.deviceModel = deviceModel
        self.depthAvailable = depthAvailable
        self.thresholds = thresholds
    }
}
