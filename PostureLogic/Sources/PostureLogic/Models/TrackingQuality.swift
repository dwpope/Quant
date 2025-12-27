public enum TrackingQuality: Comparable, Codable {
    case lost
    case degraded
    case good
    
    public var allowsPostureJudgement: Bool {
        self == .good
    }
}
