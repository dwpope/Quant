import Foundation
import simd

public protocol PoseDepthFusionProtocol: DebugDumpable {
    mutating func fuse(
        pose: PoseObservation,
        depthSamples: [DepthAtPoint]?,
        confidence: DepthConfidence,
        intrinsics: simd_float3x3?,
        trackingQuality: TrackingQuality
    ) -> PoseSample?
}
