import Foundation
import PostureLogic

struct PostureDisplayData {
    let metrics: [MetricInfo]
    let postureState: PostureState
    let nudgeDecision: NudgeDecision
    let trackingQuality: TrackingQuality
    let worstOffender: MetricInfo?
    let timeInCurrentState: TimeInterval?
    let nudgeCountdownSeconds: TimeInterval?
    let thresholds: PostureThresholds

    func metric(for key: MetricKey) -> MetricInfo {
        metrics.first { $0.key == key }!
    }

    var aggregateScore: Float {
        let avgRatio = metrics.map(\.clampedRatio).reduce(0, +) / Float(metrics.count)
        return max(0, 1.0 - avgRatio)
    }

    var isAlertMode: Bool {
        switch postureState {
        case .drifting, .bad: return true
        default: return false
        }
    }
}
