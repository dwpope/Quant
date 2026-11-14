import CoreGraphics

/// Which way round the camera's frames come: upright, from the phone held upright, or wide, from
/// the phone on its side (2026-11-11).
public enum FrameOrientation: String, Codable, Equatable, Sendable {
    case portrait
    case landscape

    /// From a frame's size: wider than tall is landscape.
    public init(width: Int, height: Int) {
        self = width > height ? .landscape : .portrait
    }

    /// A keypoint from a wide frame, in the upright frame's units.
    ///
    /// Vision's points run 0…1 across each side of the frame. Every posture line was set on the
    /// upright phone's 720 × 1280 frames, where an x step is 1/720 of the picture and a y step
    /// 1/1280; on its side the same camera gives 1280 × 720, and the steps swap. Head drop and
    /// sink (heights over a width) would read 3.2 times larger, side lean 0.56 times. So each
    /// point keeps its pixels from the centre and is measured in the upright frame's steps. The
    /// centre stays at 0.5; the wide frame's sides reach past 0 and 1, as they're outside the
    /// upright frame. An upright frame's points are unchanged.
    public static func portraitUnits(_ point: CGPoint, width: Int, height: Int) -> CGPoint {
        guard width > height, height > 0 else { return point }
        let stretch = CGFloat(width) / CGFloat(height)
        return CGPoint(x: 0.5 + (point.x - 0.5) * stretch,
                       y: 0.5 + (point.y - 0.5) / stretch)
    }
}
