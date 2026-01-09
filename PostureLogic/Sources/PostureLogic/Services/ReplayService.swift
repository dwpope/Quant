import Foundation

/// Replays recorded sessions as if they were live data
/// Enables testing and development without real ARKit hardware
public final class ReplayService: ReplayServiceProtocol {
    public var debugState: [String: Any] {
        [
            "isPlaying": _isPlaying,
            "progress": _progress,
            "playbackSpeed": playbackSpeed,
            "samplesLoaded": session?.samples.count ?? 0,
            "currentSampleIndex": currentIndex
        ]
    }

    public var isPlaying: Bool {
        return _isPlaying
    }

    public var progress: Float {
        return _progress
    }

    private var session: RecordedSession?
    private var _isPlaying = false
    private var _progress: Float = 0.0
    private var playbackSpeed: Float = 1.0
    private var currentIndex: Int = 0

    public init() {}

    // MARK: - Session Management

    public func load(session: RecordedSession) {
        self.session = session
        _progress = 0.0
        currentIndex = 0
    }

    // MARK: - Playback Control

    public func setSpeed(_ speed: Float) {
        // Clamp speed to reasonable range
        playbackSpeed = max(0.1, min(speed, 100.0))
    }

    public func stop() {
        _isPlaying = false
    }

    // MARK: - Playback

    public func play() -> AsyncStream<PoseSample> {
        guard let session = session, !session.samples.isEmpty else {
            // No session loaded or empty, return empty stream
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        _isPlaying = true
        _progress = 0.0
        currentIndex = 0

        return AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            Task {
                await self.playbackLoop(session: session, continuation: continuation)
            }
        }
    }

    // MARK: - Private Helpers

    private func playbackLoop(session: RecordedSession, continuation: AsyncStream<PoseSample>.Continuation) async {
        let samples = session.samples
        guard !samples.isEmpty else {
            _isPlaying = false
            continuation.finish()
            return
        }

        var lastTimestamp: TimeInterval = samples[0].timestamp
        currentIndex = 0

        for (index, sample) in samples.enumerated() {
            // Check if stopped
            guard _isPlaying else {
                break
            }

            // Calculate delay based on timestamp difference
            let timeDelta = sample.timestamp - lastTimestamp
            if timeDelta > 0 && index > 0 {
                // Apply playback speed
                let adjustedDelay = timeDelta / Double(playbackSpeed)

                // Sleep for the adjusted duration
                let nanoseconds = UInt64(adjustedDelay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            // Check again after sleep (might have been stopped)
            guard _isPlaying else {
                break
            }

            // Yield sample
            continuation.yield(sample)

            // Update state
            lastTimestamp = sample.timestamp
            currentIndex = index + 1
            _progress = Float(index + 1) / Float(samples.count)
        }

        // Playback complete
        _isPlaying = false
        _progress = 1.0
        continuation.finish()
    }
}

// MARK: - Convenience Extensions

extension ReplayService {
    /// Create and load a replay service from a file
    public static func fromFile(_ url: URL) throws -> ReplayService {
        let service = ReplayService()
        let session = try RecordedSession.loadFromFile(url: url)
        service.load(session: session)
        return service
    }

    /// Estimate total playback duration at current speed
    public var estimatedDuration: TimeInterval? {
        guard let session = session,
              let first = session.samples.first,
              let last = session.samples.last else {
            return nil
        }

        let realDuration = last.timestamp - first.timestamp
        return realDuration / Double(playbackSpeed)
    }

    /// Get remaining playback time
    public var remainingTime: TimeInterval? {
        guard let total = estimatedDuration else { return nil }
        return total * Double(1.0 - _progress)
    }
}
