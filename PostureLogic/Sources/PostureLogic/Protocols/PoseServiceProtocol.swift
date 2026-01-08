import Foundation

/// Protocol for pose detection services
///
/// Implementations should extract body keypoints from input frames
/// and provide throttling to avoid processing every frame.
public protocol PoseServiceProtocol: DebugDumpable {
    /// Process an input frame and extract pose observation
    ///
    /// - Parameter frame: The input frame containing pixel buffer
    /// - Returns: PoseObservation if successful, nil if throttled or failed
    func process(frame: InputFrame) async -> PoseObservation?
}
