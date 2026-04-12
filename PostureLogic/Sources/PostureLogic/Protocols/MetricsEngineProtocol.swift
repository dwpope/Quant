import Foundation

protocol MetricsEngineProtocol: DebugDumpable {
    mutating func compute(from sample: PoseSample, baseline: Baseline?) -> RawMetrics
}
