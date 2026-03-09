import Combine
import Foundation

/// Protocol for monitoring device thermal state and providing throttling policies.
public protocol ThermalMonitorProtocol {
    var currentLevel: ThermalLevel { get }
    var currentPolicy: ThermalPolicy { get }
    var levelPublisher: AnyPublisher<ThermalLevel, Never> { get }
}
