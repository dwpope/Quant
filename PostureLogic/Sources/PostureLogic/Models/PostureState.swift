import Foundation

public enum PostureState: Codable, Equatable {
    case absent
    case calibrating
    case good
    case drifting(since: TimeInterval)
    case bad(since: TimeInterval)
    
    public var isBad: Bool {
        if case .bad = self { return true }
        return false
    }
    
    public var durationInCurrentState: TimeInterval? {
        switch self {
        case .drifting(let since), .bad(let since):
            return Date().timeIntervalSince1970 - since
        default:
            return nil
        }
    }
}
