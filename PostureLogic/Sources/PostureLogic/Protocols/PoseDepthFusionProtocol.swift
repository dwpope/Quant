import Foundation

public protocol PoseDepthFusionProtocol: DebugDumpable {
    mutating func fuse(
        pose: PoseObservation,
        depthSamples: [DepthAtPoint]?,
        confidence: DepthConfidence,
        trackingQuality: TrackingQuality
    ) -> PoseSample?
}
