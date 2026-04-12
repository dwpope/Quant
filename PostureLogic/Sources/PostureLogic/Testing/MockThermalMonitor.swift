import Combine
import Foundation

/// Mock thermal monitor for testing. Allows programmatic control of thermal level.
final class MockThermalMonitor: ThermalMonitorProtocol {

    private(set) var currentLevel: ThermalLevel
    var currentPolicy: ThermalPolicy { ThermalPolicy.policy(for: currentLevel) }

    var levelPublisher: AnyPublisher<ThermalLevel, Never> {
        levelSubject.eraseToAnyPublisher()
    }

    private let levelSubject: CurrentValueSubject<ThermalLevel, Never>

    init(level: ThermalLevel = .nominal) {
        self.currentLevel = level
        self.levelSubject = CurrentValueSubject(level)
    }

    /// Set the thermal level, publishing the change immediately.
    func setLevel(_ level: ThermalLevel) {
        currentLevel = level
        levelSubject.send(level)
    }
}
