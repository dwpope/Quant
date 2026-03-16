import Foundation

/// Classifies the user's current activity from a rolling window of metrics.
///
/// ## How It Works
///
/// The engine looks at recent movement patterns to infer what the user is doing:
///
/// | Activity    | Movement Level | Head Pattern        |
/// |-------------|---------------|---------------------|
/// | Reading     | < 0.2         | smallOscillations   |
/// | Typing      | 0.2 ..< 0.5  | largeMovements      |
/// | Meeting     | 0.15 ..< 0.4 | still               |
/// | Stretching  | > 0.7         | (any)               |
/// | Unknown     | < 10 samples or no pattern match     |
///
/// The classification uses a simple majority-vote approach: it counts how many
/// of the recent metrics match each activity's signature, then picks the one
/// with the most votes. If no pattern gets any votes, the result is `.unknown`.
///
/// ## Minimum Samples
///
/// The engine requires at least 10 metrics entries before it will classify.
/// With a typical 10 FPS capture rate, this means ~1 second of data.
/// Until then, it returns `.unknown` to avoid snap judgements.
public final class TaskModeEngine: DebugDumpable {

    // MARK: - Constants

    /// Minimum number of samples needed before classification is attempted.
    private let minimumSamples = 10

    // MARK: - Debug State

    private var lastResult: TaskMode = .unknown

    public var debugState: [String: Any] {
        [
            "lastResult": lastResult.rawValue,
            "minimumSamples": minimumSamples,
        ]
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Classification

    /// Infers the current task mode from a rolling window of recent metrics.
    ///
    /// - Parameter recentMetrics: The last ~100 `RawMetrics` entries (≈10 seconds at 10 FPS).
    /// - Returns: The inferred `TaskMode`, or `.unknown` if insufficient data or no pattern matches.
    public func infer(from recentMetrics: [RawMetrics]) -> TaskMode {
        guard recentMetrics.count >= minimumSamples else {
            lastResult = .unknown
            return .unknown
        }

        var readingVotes = 0
        var typingVotes = 0
        var meetingVotes = 0
        var stretchingVotes = 0

        for m in recentMetrics {
            if m.movementLevel > 0.7 {
                stretchingVotes += 1
            } else if m.movementLevel < 0.2 && m.headMovementPattern == .smallOscillations {
                readingVotes += 1
            } else if (0.2 ..< 0.5).contains(m.movementLevel) && m.headMovementPattern == .largeMovements {
                typingVotes += 1
            } else if (0.15 ..< 0.4).contains(m.movementLevel) && m.headMovementPattern == .still {
                meetingVotes += 1
            }
        }

        let candidates: [(TaskMode, Int)] = [
            (.stretching, stretchingVotes),
            (.reading, readingVotes),
            (.typing, typingVotes),
            (.meeting, meetingVotes),
        ]

        // Pick the mode with the most votes; ties broken by declaration order above.
        if let winner = candidates.max(by: { $0.1 < $1.1 }), winner.1 > 0 {
            lastResult = winner.0
            return winner.0
        }

        lastResult = .unknown
        return .unknown
    }
}
