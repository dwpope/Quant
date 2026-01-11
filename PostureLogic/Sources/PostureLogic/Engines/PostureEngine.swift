import Foundation

public final class PostureEngine: PostureEngineProtocol {
    public var debugState: [String: Any] {
        ["state": String(describing: currentState)]
    }

    private var currentState: PostureState = .absent
    private let thresholds: PostureThresholds

    public init(thresholds: PostureThresholds) {
        self.thresholds = thresholds
    }

    public func update(
        metrics: RawMetrics,
        taskMode: TaskMode,
        trackingQuality: TrackingQuality
    ) -> PostureState {
        // Don't judge if tracking is bad
        guard trackingQuality.allowsPostureJudgement else {
            // Don't change state, just pause timers
            return currentState
        }

        let isPostureBad = checkPostureBad(metrics: metrics, taskMode: taskMode)

        switch currentState {
        case .absent, .calibrating:
            currentState = .good

        case .good:
            if isPostureBad {
                currentState = .drifting(since: metrics.timestamp)
            }

        case .drifting(let since):
            if !isPostureBad {
                currentState = .good
            } else if metrics.timestamp - since >= thresholds.driftingToBadThreshold {
                currentState = .bad(since: since)
            }

        case .bad:
            if !isPostureBad {
                // Start grace period for recovery
                currentState = .drifting(since: metrics.timestamp)
            }
        }

        return currentState
    }

    private func checkPostureBad(metrics: RawMetrics, taskMode: TaskMode) -> Bool {
        // Stretching mode: never judge posture as bad
        if taskMode == .stretching {
            return false
        }

        // Get threshold multipliers for current task mode
        let multipliers = getThresholdMultipliers(for: taskMode)

        // Apply task-adjusted thresholds
        let forwardThreshold = thresholds.forwardCreepThreshold * multipliers.forwardCreep
        let twistThreshold = thresholds.twistThreshold * multipliers.twist
        let sideLeanThreshold = thresholds.sideLeanThreshold * multipliers.sideLean

        return metrics.forwardCreep > forwardThreshold
            || metrics.twist > twistThreshold
            || metrics.lateralLean > sideLeanThreshold
    }

    private func getThresholdMultipliers(for taskMode: TaskMode) -> (forwardCreep: Float, twist: Float, sideLean: Float) {
        switch taskMode {
        case .unknown:
            return (1.0, 1.0, 1.0)
        case .reading:
            return (1.3, 1.0, 1.0)
        case .typing:
            return (1.0, 1.2, 1.0)
        case .meeting:
            return (1.2, 1.5, 1.2)
        case .stretching:
            // This shouldn't be reached due to early return, but return high multipliers
            return (Float.infinity, Float.infinity, Float.infinity)
        }
    }

    public func reset() {
        currentState = .absent
    }
}
