import Foundation

/// Protocol for recording PoseSample streams to disk for analysis and testing
public protocol RecorderServiceProtocol: DebugDumpable {
    /// Start a new recording session
    mutating func startRecording()

    /// Stop the current recording and return the session
    mutating func stopRecording() -> RecordedSession

    /// Add a tag to the current recording
    mutating func addTag(_ tag: Tag)

    /// Record a pose sample
    mutating func record(sample: PoseSample)

    /// Check if currently recording
    var isRecording: Bool { get }
}
