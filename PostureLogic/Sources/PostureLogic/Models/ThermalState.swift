import Foundation

/// Thermal severity levels mapped from ProcessInfo.ThermalState.
public enum ThermalLevel: Int, Comparable, CaseIterable, Codable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Policy describing how the Pipeline should behave at a given thermal level.
public struct ThermalPolicy: Equatable {
    /// Target FPS cap. 0 means detection is paused.
    public let maxFPS: Float
    /// Whether depth/LiDAR sampling should be used.
    public let depthEnabled: Bool
    /// Whether pose detection should be paused entirely.
    public let detectionPaused: Bool

    public static let nominal = ThermalPolicy(maxFPS: 10, depthEnabled: true, detectionPaused: false)
    public static let fair = ThermalPolicy(maxFPS: 5, depthEnabled: true, detectionPaused: false)
    public static let serious = ThermalPolicy(maxFPS: 3, depthEnabled: false, detectionPaused: false)
    public static let critical = ThermalPolicy(maxFPS: 0, depthEnabled: false, detectionPaused: true)

    public static func policy(for level: ThermalLevel) -> ThermalPolicy {
        switch level {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        }
    }
}
