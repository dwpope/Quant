import Foundation

/// Protocol for smoothing metrics to reduce jitter
/// Ticket 3.4: Applies temporal smoothing using exponential moving average
public protocol MetricsSmootherProtocol: DebugDumpable {
    mutating func smooth(_ current: RawMetrics) -> RawMetrics
}
