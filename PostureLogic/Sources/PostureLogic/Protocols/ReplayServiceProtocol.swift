import Foundation

/// Protocol for replaying recorded sessions for testing and simulation
public protocol ReplayServiceProtocol: DebugDumpable {
    /// Load a recorded session for playback
    mutating func load(session: RecordedSession)

    /// Start playback and return stream of samples
    /// Samples are emitted with timing based on their timestamps and playback speed
    func play() -> AsyncStream<PoseSample>

    /// Stop playback
    mutating func stop()

    /// Set playback speed multiplier (1.0 = realtime, 2.0 = 2x speed, etc.)
    mutating func setSpeed(_ speed: Float)

    /// Check if currently playing
    var isPlaying: Bool { get }

    /// Current playback progress (0.0 to 1.0)
    var progress: Float { get }
}
