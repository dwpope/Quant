import Foundation

public enum PoseDetectionResult {
    case observation(PoseObservation)
    case throttled
    case noPose
    case failed
}

/// Protocol for pose detection services
///
/// Implementations should extract body keypoints from input frames
/// and provide throttling to avoid processing every frame.
public protocol PoseServiceProtocol: DebugDumpable {
    /// Process an input frame and extract pose observation
    ///
    /// - Parameter frame: The input frame containing pixel buffer
    /// - Returns: A `PoseDetectionResult` describing whether the frame was processed.
    func process(frame: InputFrame) async -> PoseDetectionResult
}
