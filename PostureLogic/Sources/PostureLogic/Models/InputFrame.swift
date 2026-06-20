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

    /// An authoritative head orientation supplied by the frame source (Layer 1: an
    /// app-side ARKit `ARFaceAnchor` provider). Unlike `precomputedSample` this does
    /// NOT bypass pose detection — Vision still runs to recover shoulders (so the
    /// device-confirmed side-lean survives); only the head angles are overridden,
    /// downstream in `PoseDepthFusion.computeHeadAngles`. `nil` for the Vision-only
    /// and replay providers. Not serialized (this struct is never `Codable`).
    public let externalHeadAngles: HeadAngles?

    public init(timestamp: TimeInterval, pixelBuffer: CVPixelBuffer?, depthMap: CVPixelBuffer?, cameraIntrinsics: simd_float3x3?, precomputedSample: PoseSample? = nil, externalHeadAngles: HeadAngles? = nil) {
        self.timestamp = timestamp
        self.pixelBuffer = pixelBuffer
        self.depthMap = depthMap
        self.cameraIntrinsics = cameraIntrinsics
        self.precomputedSample = precomputedSample
        self.externalHeadAngles = externalHeadAngles
    }
}
