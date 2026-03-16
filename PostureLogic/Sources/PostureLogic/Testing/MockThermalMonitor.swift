import Combine
import Foundation

/// Mock thermal monitor for testing. Allows programmatic control of thermal level.
public final class MockThermalMonitor: ThermalMonitorProtocol {

    public private(set) var currentLevel: ThermalLevel
    public var currentPolicy: ThermalPolicy { ThermalPolicy.policy(for: currentLevel) }

    public var levelPublisher: AnyPublisher<ThermalLevel, Never> {
        levelSubject.eraseToAnyPublisher()
    }

    private let levelSubject: CurrentValueSubject<ThermalLevel, Never>

    public init(level: ThermalLevel = .nominal) {
        self.currentLevel = level
        self.levelSubject = CurrentValueSubject(level)
    }

    /// Set the thermal level, publishing the change immediately.
    public func setLevel(_ level: ThermalLevel) {
        currentLevel = level
        levelSubject.send(level)
    }
}
