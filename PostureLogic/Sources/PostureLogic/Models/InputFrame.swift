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

    /// The same Layer-1 head orientation as `externalHeadAngles`, but carried as a
    /// raw quaternion (screen-frame rotation) parallel to the decomposed Euler
    /// angles. Lets a later stage drive the figure head from ARKit's quaternion
    /// directly instead of re-amplifying decomposed Euler axes. **Viz-only** — never
    /// feeds scoring. `nil` for every non-ARKit-face path (so the Euler/2D path is
    /// unchanged). Not serialized (this struct is never `Codable`).
    public let externalHeadOrientation: simd_quatf?

    public init(timestamp: TimeInterval, pixelBuffer: CVPixelBuffer?, depthMap: CVPixelBuffer?, cameraIntrinsics: simd_float3x3?, precomputedSample: PoseSample? = nil, externalHeadAngles: HeadAngles? = nil, externalHeadOrientation: simd_quatf? = nil) {
        self.timestamp = timestamp
        self.pixelBuffer = pixelBuffer
        self.depthMap = depthMap
        self.cameraIntrinsics = cameraIntrinsics
        self.precomputedSample = precomputedSample
        self.externalHeadAngles = externalHeadAngles
        self.externalHeadOrientation = externalHeadOrientation
    }
}
