import Foundation

public protocol PostureEngineProtocol: DebugDumpable {
    func update(
        metrics: RawMetrics,
        taskMode: TaskMode,
        trackingQuality: TrackingQuality
    ) -> PostureState

    func reset()
}
