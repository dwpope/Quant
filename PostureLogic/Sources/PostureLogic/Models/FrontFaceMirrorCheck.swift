import CoreGraphics

/// Whether Vision's picture of the person runs the same way as ARKit's face (Front Face,
/// 2026-11-27). Vision reads the frame turned upright and unmirrored; this compares where it
/// puts the nose across the frame with where ARKit's face projects, 0…1 each. If they agree the
/// orientation is right; if they sit on opposite sides of the middle, the picture is mirrored.
public enum FrontFaceMirrorCheck {
    public enum Result: Equatable, Sendable {
        case matches, mirrored, unclear
    }

    /// Within this much across the frame the two readings count as the same place.
    static let tolerance: CGFloat = 0.1

    public static func classify(visionNoseX: CGFloat, projectedFaceX: CGFloat) -> Result {
        let matches = abs(visionNoseX - projectedFaceX) <= tolerance
        let mirrored = abs((1 - visionNoseX) - projectedFaceX) <= tolerance
        // Near the middle both readings agree, so the check can't tell.
        if matches && mirrored { return .unclear }
        if matches { return .matches }
        if mirrored { return .mirrored }
        return .unclear
    }
}
