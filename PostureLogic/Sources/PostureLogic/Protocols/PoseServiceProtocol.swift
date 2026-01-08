import Foundation
import CoreVideo

/// Protocol for pose detection services
///
/// Implementations should extract body keypoints from pixel buffers
/// and provide throttling to avoid processing every frame.
public protocol PoseServiceProtocol: DebugDumpable {
    /// Process a pixel buffer and extract pose observation
    ///
    /// - Parameters:
    ///   - pixelBuffer: The pixel buffer to process (optional)
    ///   - timestamp: The timestamp of the frame
    /// - Returns: PoseObservation if successful, nil if throttled or failed
    func process(pixelBuffer: CVPixelBuffer?, timestamp: TimeInterval) async -> PoseObservation?
}
