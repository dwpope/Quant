public enum TrackingQuality: String, Comparable, Codable {
    case lost
    case degraded
    case good

    public var allowsPostureJudgement: Bool {
        self == .good
    }

    public static func < (lhs: TrackingQuality, rhs: TrackingQuality) -> Bool {
        let order: [TrackingQuality] = [.lost, .degraded, .good]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}
