import CoreVideo
import simd
import Foundation

public struct InputFrame {
    public let timestamp: TimeInterval
    public let pixelBuffer: CVPixelBuffer?
    public let depthMap: CVPixelBuffer?
    public let cameraIntrinsics: simd_float3x3?

    /// A pre-fused pose sample that bypasses pose detection and depth fusion.
    /// Used by ``ReplayPoseProvider`` so replay shares the same Pipeline code path
    /// (metrics, posture engine, nudge engine) as live camera input.
    public let precomputedSample: PoseSample?

    public init(timestamp: TimeInterval, pixelBuffer: CVPixelBuffer?, depthMap: CVPixelBuffer?, cameraIntrinsics: simd_float3x3?, precomputedSample: PoseSample? = nil) {
        self.timestamp = timestamp
        self.pixelBuffer = pixelBuffer
        self.depthMap = depthMap
        self.cameraIntrinsics = cameraIntrinsics
        self.precomputedSample = precomputedSample
    }
}
