import CoreGraphics
import Foundation

protocol DepthServiceProtocol: DebugDumpable {
    mutating func sampleDepth(at points: [CGPoint], from frame: InputFrame) -> [DepthAtPoint]
    mutating func computeConfidence(from frame: InputFrame) -> DepthConfidence
}
