import CoreVideo
import simd
import Foundation

public struct InputFrame {
    public let timestamp: TimeInterval
    public let pixelBuffer: CVPixelBuffer?
    public let depthMap: CVPixelBuffer?
    public let cameraIntrinsics: simd_float3x3?
    
    public init(timestamp: TimeInterval, pixelBuffer: CVPixelBuffer?, depthMap: CVPixelBuffer?, cameraIntrinsics: simd_float3x3?) {
        self.timestamp = timestamp
        self.pixelBuffer = pixelBuffer
        self.depthMap = depthMap
        self.cameraIntrinsics = cameraIntrinsics
    }
}
