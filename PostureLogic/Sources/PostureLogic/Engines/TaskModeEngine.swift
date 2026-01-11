import Foundation

public struct TaskModeEngine: TaskModeEngineProtocol {
    public var debugState: [String: Any] {
        [
            "lastInferredMode": lastInferredMode?.rawValue ?? "none",
            "metricsWindowSize": metricsWindowSize
        ]
    }

    private var lastInferredMode: TaskMode?
    private let metricsWindowSize: Int = 10

    public init() {}

    public mutating func infer(from recentMetrics: [RawMetrics]) -> TaskMode {
        guard recentMetrics.count >= metricsWindowSize else {
            return .unknown
        }

        let avgMovement = recentMetrics.map(\.movementLevel).reduce(0, +) / Float(recentMetrics.count)
        let patterns = recentMetrics.map(\.headMovementPattern)

        let mode: TaskMode

        // Stretching: high movement
        if avgMovement > 0.7 {
            mode = .stretching
        }
        // Reading: low movement, small oscillations
        else if avgMovement < 0.2 && patterns.allSatisfy({ $0 == .still || $0 == .smallOscillations }) {
            mode = .reading
        }
        // Typing: moderate movement, large movements present
        else if avgMovement < 0.4 && patterns.contains(.largeMovements) {
            mode = .typing
        }
        // Meeting: higher movement but not stretching level
        else if avgMovement >= 0.4 && avgMovement <= 0.7 {
            mode = .meeting
        }
        else {
            mode = .unknown
        }

        lastInferredMode = mode
        return mode
    }
}
