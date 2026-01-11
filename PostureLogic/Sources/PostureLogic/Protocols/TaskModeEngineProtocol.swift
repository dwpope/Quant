import Foundation

public protocol TaskModeEngineProtocol: DebugDumpable {
    mutating func infer(from recentMetrics: [RawMetrics]) -> TaskMode
}
