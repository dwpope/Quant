import Foundation
import simd

/// Protocol for fusing pose detection and depth data into unified PoseSample
public protocol PoseDepthFusionProtocol: DebugDumpable {
    mutating func fuse(
        pose: PoseObservation,
        depthSamples: [DepthAtPoint]?,
        confidence: DepthConfidence,
        cameraIntrinsics: simd_float3x3?
    ) -> PoseSample
}
