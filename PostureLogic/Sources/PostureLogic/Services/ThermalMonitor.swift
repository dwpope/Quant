import Combine
import Foundation

/// Observes `ProcessInfo.thermalState` and publishes `ThermalLevel` changes.
public final class ThermalMonitor: ThermalMonitorProtocol, DebugDumpable {

    public private(set) var currentLevel: ThermalLevel
    public var currentPolicy: ThermalPolicy { ThermalPolicy.policy(for: currentLevel) }

    public var levelPublisher: AnyPublisher<ThermalLevel, Never> {
        levelSubject.eraseToAnyPublisher()
    }

    private let levelSubject: CurrentValueSubject<ThermalLevel, Never>
    private var cancellable: AnyCancellable?

    public init() {
        let initial = ThermalMonitor.mapThermalState(ProcessInfo.processInfo.thermalState)
        self.currentLevel = initial
        self.levelSubject = CurrentValueSubject(initial)

        cancellable = NotificationCenter.default
            .publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .compactMap { _ in
                ThermalMonitor.mapThermalState(ProcessInfo.processInfo.thermalState)
            }
            .removeDuplicates()
            .sink { [weak self] level in
                self?.currentLevel = level
                self?.levelSubject.send(level)
            }
    }

    private static func mapThermalState(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    // MARK: - DebugDumpable

    public var debugState: [String: Any] {
        [
            "thermalLevel": "\(currentLevel)",
            "maxFPS": currentPolicy.maxFPS,
            "depthEnabled": currentPolicy.depthEnabled,
            "detectionPaused": currentPolicy.detectionPaused,
        ]
    }
}
