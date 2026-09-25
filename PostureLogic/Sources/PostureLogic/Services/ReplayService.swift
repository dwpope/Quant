import Foundation

/// Replays a ``RecordedSession`` as an `AsyncStream<PoseSample>` with timing.
///
/// Thread-safety: designed for single-threaded use (call from main actor or a single task).
/// Playback respects inter-sample timestamp deltas scaled by ``playbackSpeed``.
public final class ReplayService: ReplayServiceProtocol {

    // MARK: - State

    private var session: RecordedSession?
    private var playbackTask: Task<Void, Never>?

    // MARK: - Public

    public private(set) var isLoaded: Bool = false
    public private(set) var isPlaying: Bool = false
    public var playbackSpeed: Double = 1.0

    // MARK: - DebugDumpable

    public var debugState: [String: Any] {
        var state: [String: Any] = [
            "isLoaded": isLoaded,
            "isPlaying": isPlaying,
            "playbackSpeed": playbackSpeed
        ]
        if let session {
            state["sessionID"] = session.id.uuidString
            state["sampleCount"] = session.samples.count
        }
        return state
    }

    // MARK: - Init

    public init() {}

    // MARK: - Timing

    /// Delay before the next sample, derived from the gap between sample timestamps.
    ///
    /// Extracted so playback speed can be asserted exactly instead of measured. A wall-clock
    /// test of this relationship is a race between the code and the machine: the previous one
    /// compared elapsed times for a 1x and a 10x run and failed on CI at 0.0877s vs 0.0720s,
    /// which was scheduling noise rather than a regression.
    ///
    /// Returns 0 for a non-positive delta, so samples sharing a timestamp or arriving out of
    /// order neither stall playback nor trap on a negative `UInt64` conversion. Speed is clamped
    /// to a small positive value for the same reason — a zero speed would divide by zero.
    public static func sleepNanoseconds(timestampDelta: TimeInterval, speed: Double) -> UInt64 {
        guard timestampDelta > 0 else { return 0 }
        let safeSpeed = max(speed, 0.001)
        return UInt64(timestampDelta / safeSpeed * 1_000_000_000)
    }

    // MARK: - Lifecycle

    public func load(session: RecordedSession) {
        stop()
        self.session = session
        isLoaded = true
    }

    public func play() -> AsyncStream<PoseSample>? {
        guard let session, isLoaded, !isPlaying else { return nil }

        let samples = session.samples
        guard !samples.isEmpty else {
            return AsyncStream { $0.finish() }
        }

        isPlaying = true
        let speed = max(playbackSpeed, 0.001) // Guard against zero/negative

        return AsyncStream { [weak self] continuation in
            let task = Task { [weak self] in
                defer {
                    self?.isPlaying = false
                    continuation.finish()
                }

                for i in samples.indices {
                    if Task.isCancelled { return }

                    // Delay based on timestamp delta from previous sample. Uses the same
                    // `sleepNanoseconds` the tests assert on, so the tested arithmetic is the
                    // arithmetic that actually runs.
                    if i > 0 {
                        let nanoseconds = Self.sleepNanoseconds(
                            timestampDelta: samples[i].timestamp - samples[i - 1].timestamp,
                            speed: speed
                        )
                        if nanoseconds > 0 {
                            do {
                                try await Task.sleep(nanoseconds: nanoseconds)
                            } catch {
                                return // Cancelled
                            }
                        }
                    }

                    if Task.isCancelled { return }
                    continuation.yield(samples[i])
                }
            }

            self?.playbackTask = task

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }
}
