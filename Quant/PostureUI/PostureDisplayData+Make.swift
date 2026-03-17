import Foundation
import PostureLogic

extension PostureDisplayData {
    static func make(
        from metrics: RawMetrics?,
        postureState: PostureState,
        nudgeDecision: NudgeDecision,
        trackingQuality: TrackingQuality,
        thresholds: PostureThresholds
    ) -> PostureDisplayData {
        let raw = metrics ?? .zero

        let metricInfos: [MetricInfo] = MetricKey.allCases.map { key in
            let value = raw.value(for: key)
            let threshold = thresholds.threshold(for: key)
            let ratio = threshold > 0 ? abs(value) / threshold : 0
            return MetricInfo(
                key: key,
                value: value,
                ratio: ratio,
                threshold: threshold,
                isWorstOffender: false
            )
        }

        let worstKey = metricInfos.max(by: { $0.ratio < $1.ratio })?.key
        let infosWithWorst = metricInfos.map { info in
            MetricInfo(
                key: info.key,
                value: info.value,
                ratio: info.ratio,
                threshold: info.threshold,
                isWorstOffender: info.key == worstKey && info.ratio > 0
            )
        }

        let nudgeCountdown: TimeInterval?
        if case .pending(_, let remaining) = nudgeDecision {
            nudgeCountdown = remaining
        } else {
            nudgeCountdown = nil
        }

        return PostureDisplayData(
            metrics: infosWithWorst,
            postureState: postureState,
            nudgeDecision: nudgeDecision,
            trackingQuality: trackingQuality,
            worstOffender: infosWithWorst.first(where: \.isWorstOffender),
            timeInCurrentState: postureState.durationInCurrentState,
            nudgeCountdownSeconds: nudgeCountdown,
            thresholds: thresholds
        )
    }
}
