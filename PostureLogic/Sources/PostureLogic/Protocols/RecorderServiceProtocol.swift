/// Protocol for recording posture sessions.
///
/// Lifecycle: ``startRecording(metadata:)`` -> ``record(sample:)`` (repeatedly) -> ``stopRecording()``
public protocol RecorderServiceProtocol: DebugDumpable {
    /// Whether a recording session is currently active.
    var isRecording: Bool { get }

    /// Begin a new recording session.
    /// - Parameter metadata: Device and configuration info for the session.
    /// - Returns: `true` if recording started, `false` if already recording.
    @discardableResult
    mutating func startRecording(metadata: SessionMetadata) -> Bool

    /// Append a pose sample to the current recording.
    /// No-op if not currently recording.
    mutating func record(sample: PoseSample)

    /// End the current recording and return the completed session.
    /// - Returns: The recorded session, or `nil` if not recording.
    mutating func stopRecording() -> RecordedSession?

    /// Number of samples recorded in the current session.
    var sampleCount: Int { get }
}
