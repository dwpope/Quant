import PostureLogic

enum MetricKey: String, CaseIterable, Identifiable {
    case forwardCreep
    case headDrop
    case shoulderRounding
    case lateralLean
    case twist

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .forwardCreep:     return "Forward Creep"
        case .headDrop:         return "Head Drop"
        case .shoulderRounding: return "Shoulder Rounding"
        case .lateralLean:      return "Lateral Lean"
        case .twist:            return "Twist"
        }
    }

    var symbolName: String {
        switch self {
        case .forwardCreep:     return "arrow.forward.circle"
        case .headDrop:         return "arrow.down.circle"
        case .shoulderRounding: return "person.bust"
        case .lateralLean:      return "arrow.left.and.right"
        case .twist:            return "arrow.triangle.2.circlepath"
        }
    }
}
