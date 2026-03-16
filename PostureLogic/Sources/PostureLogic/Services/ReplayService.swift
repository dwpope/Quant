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

                    // Delay based on timestamp delta from previous sample
                    if i > 0 {
                        let delta = samples[i].timestamp - samples[i - 1].timestamp
                        if delta > 0 {
                            let sleepNanoseconds = UInt64(delta / speed * 1_000_000_000)
                            do {
                                try await Task.sleep(nanoseconds: sleepNanoseconds)
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
