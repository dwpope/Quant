/// Protocol for replaying recorded posture sessions.
///
/// Lifecycle: ``load(session:)`` -> ``play()`` returns `AsyncStream<PoseSample>` -> ``stop()``
public protocol ReplayServiceProtocol: DebugDumpable {
    /// Whether a session is loaded and ready for playback.
    var isLoaded: Bool { get }

    /// Whether playback is currently in progress.
    var isPlaying: Bool { get }

    /// Playback speed multiplier. Default is 1.0 (real-time).
    var playbackSpeed: Double { get set }

    /// Load a recorded session for playback.
    /// - Parameter session: The session to replay.
    mutating func load(session: RecordedSession)

    /// Begin playback of the loaded session.
    /// - Returns: An `AsyncStream` yielding samples with inter-sample timing, or `nil` if no session is loaded.
    mutating func play() -> AsyncStream<PoseSample>?

    /// Stop playback if in progress.
    mutating func stop()
}
