import CoreVideo
import CoreGraphics
import Foundation

/// Service for sampling and analyzing depth data from ARKit frames
///
/// This is a stateless service — all methods are pure functions with no mutable state.
/// Immutable design ensures thread-safety and predictable behavior.
public final class DepthService: DepthServiceProtocol {
    public var debugState: [String: Any] {
        [
            "description": "Stateless depth service - no mutable state"
        ]
    }

    private let edgeMargin: Float = 0.05  // 5% margin from edges (per Known Gotchas)

    public init() {}

    public func sampleDepth(at points: [CGPoint], from frame: InputFrame) -> [DepthAtPoint] {
        guard let depthMap = frame.depthMap else {
            // No depth map available, return zero-confidence samples
            return points.map { DepthAtPoint(point: $0, depth: 0, confidence: 0) }
        }

        // Lock the pixel buffer for reading
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return points.map { DepthAtPoint(point: $0, depth: 0, confidence: 0) }
        }

        // Bind to Float32 (ARKit depth maps are 32-bit float)
        let buffer = baseAddress.assumingMemoryBound(to: Float32.self)

        return points.map { point in
            // Convert normalized coordinates (0-1) to pixel coordinates
            let x = Int(point.x * CGFloat(width))
            let y = Int(point.y * CGFloat(height))

            // Check if point is within bounds
            guard x >= 0 && x < width && y >= 0 && y < height else {
                return DepthAtPoint(point: point, depth: 0, confidence: 0)
            }

            // Check if point is too close to edges (per Known Gotchas)
            if isNearEdge(x: x, y: y, width: width, height: height) {
                return DepthAtPoint(point: point, depth: 0, confidence: 0)
            }

            // Calculate buffer index
            let index = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
            let depthValue = buffer[index]

            // Validate depth value
            let isValid = depthValue.isFinite && depthValue > 0 && depthValue < 10.0  // Reasonable range for desk distance
            let confidence: Float = isValid ? 1.0 : 0.0
            let depth = isValid ? depthValue : 0.0

            return DepthAtPoint(point: point, depth: depth, confidence: confidence)
        }
    }

    public func computeConfidence(from frame: InputFrame) -> DepthConfidence {
        guard let depthMap = frame.depthMap else {
            return .unavailable
        }

        // Lock the pixel buffer for reading
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return .unavailable
        }

        let buffer = baseAddress.assumingMemoryBound(to: Float32.self)

        // Sample a grid of points to assess overall quality
        let sampleGridSize = 20  // 20x20 grid = 400 samples
        var validCount = 0
        var totalCount = 0

        let stepX = width / sampleGridSize
        let stepY = height / sampleGridSize

        for gridY in 0..<sampleGridSize {
            for gridX in 0..<sampleGridSize {
                let x = gridX * stepX + stepX / 2
                let y = gridY * stepY + stepY / 2

                // Skip edge samples
                if isNearEdge(x: x, y: y, width: width, height: height) {
                    continue
                }

                let index = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                let depthValue = buffer[index]

                totalCount += 1

                if depthValue.isFinite && depthValue > 0 && depthValue < 10.0 {
                    validCount += 1
                }
            }
        }

        guard totalCount > 0 else {
            return .low
        }

        let coverage = Float(validCount) / Float(totalCount)

        // Determine confidence based on coverage
        if coverage >= 0.8 {
            return .high
        } else if coverage >= 0.5 {
            return .medium
        } else if coverage >= 0.2 {
            return .low
        } else {
            return .unavailable
        }
    }

    private func isNearEdge(x: Int, y: Int, width: Int, height: Int) -> Bool {
        let marginX = Int(Float(width) * edgeMargin)
        let marginY = Int(Float(height) * edgeMargin)

        return x < marginX || x >= width - marginX ||
               y < marginY || y >= height - marginY
    }
}
