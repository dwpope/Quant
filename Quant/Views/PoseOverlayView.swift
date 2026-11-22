import SwiftUI
import UIKit
import PostureLogic

/// The tracked points and the lines the posture measurements use, drawn over the front camera's
/// picture (2026-11-22). See `PoseOverlay` for what each line measures.
///
/// The reading lines are in the posture's colours: green inside their line, amber past it, red
/// once the slouch has gone on, with a countdown to the next change. The points are in colours
/// the posture never uses (blue shoulders, violet head, white for the rest), so a colour on
/// screen always means one thing. Dashed white is where things were at calibration.
struct PoseOverlayView: View {
    let keypoints: [Keypoint]
    let orientation: FrameOrientation
    let baseline: Baseline?
    var reading: PoseReading? = nil

    // The tracked points: no green, amber or red.
    static let shoulderPoint = Color(red: 0.35, green: 0.60, blue: 1.0)
    static let headPoint = Color(red: 0.78, green: 0.50, blue: 1.0)
    private let shoulderPoint = Self.shoulderPoint
    private let headPoint = Self.headPoint
    private let otherPoint = Color.white.opacity(0.6)
    private let calibrated = Color.white.opacity(0.85)
    /// A reading's line with no posture being judged.
    private let unjudged = Color.white

    var body: some View {
        GeometryReader { geometry in
            let overlay = PoseOverlay(keypoints: keypoints, orientation: orientation,
                                      baseline: baseline, reading: reading, in: geometry.size)
            Canvas { context, _ in
                draw(overlay, in: &context)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The posture's colours as the card and timeline use them, their dark-mode shades: the
    /// picture behind is a camera's, not the light background the light shades are for.
    static func colour(_ status: PoseOverlay.Status) -> Color {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let colour: UIColor = switch status {
        case .good: PosturePalette.good
        case .slouching: PosturePalette.slouching
        case .stillSlouching: PosturePalette.stillSlouching
        }
        return Color(uiColor: colour.resolvedColor(with: dark))
    }

    private func colour(_ line: PoseOverlay.Line) -> Color {
        line.status.map(Self.colour) ?? unjudged
    }

    private func draw(_ overlay: PoseOverlay, in context: inout GraphicsContext) {
        let dashed = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5])
        let solid = StrokeStyle(lineWidth: 4, lineCap: .round)
        let rightEnd = { (line: PoseOverlay.Line) in line.to.x > line.from.x ? line.to : line.from }

        for line in overlay.lines {
            var path = Path()
            path.move(to: line.from)
            path.addLine(to: line.to)
            switch line.kind {
            case .shoulders:
                context.stroke(path, with: .color(colour(line)), style: solid)
                label("shoulder width", at: rightEnd(line), colour: colour(line), in: &context,
                      offset: CGSize(width: 0, height: -18))
            case .ears:
                context.stroke(path, with: .color(colour(line)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                let left = line.to.x < line.from.x ? line.to : line.from
                label("turn", at: left, colour: colour(line), in: &context, offset: CGSize(width: -26, height: 0))
            case .headHeight:
                context.stroke(path, with: .color(colour(line)), style: solid)
                let middle = CGPoint(x: line.from.x, y: (line.from.y + line.to.y) / 2)
                label("head height", at: middle, colour: colour(line), in: &context,
                      offset: CGSize(width: -52, height: 0))
            case .centreShift:
                context.stroke(path, with: .color(colour(line)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                // Labelled once it's long enough to see.
                // Labelled once it's long enough to see, beyond the cross, away from the line.
                let length = hypot(line.to.x - line.from.x, line.to.y - line.from.y)
                if length > 12 {
                    let away = CGSize(width: (line.from.x - line.to.x) / length * 46,
                                      height: (line.from.y - line.to.y) / length * 22)
                    label("lean / sink", at: line.from, colour: colour(line), in: &context, offset: away)
                }
            case .calibratedShoulders:
                // Just below today's line, so both ends can be seen.
                context.stroke(path.offsetBy(dx: 0, dy: 10), with: .color(calibrated), style: dashed)
            case .calibratedHeadHeight:
                context.stroke(path, with: .color(calibrated), style: dashed)
                label("calibrated", at: rightEnd(line), colour: .white, in: &context,
                      offset: CGSize(width: 40, height: 0))
            }
        }

        if let centre = overlay.calibratedCentre {
            var cross = Path()
            cross.move(to: CGPoint(x: centre.x - 9, y: centre.y))
            cross.addLine(to: CGPoint(x: centre.x + 9, y: centre.y))
            cross.move(to: CGPoint(x: centre.x, y: centre.y - 9))
            cross.addLine(to: CGPoint(x: centre.x, y: centre.y + 9))
            context.stroke(cross, with: .color(calibrated), style: StrokeStyle(lineWidth: 2))
        }

        for dot in overlay.dots {
            let colour: Color = switch dot.part {
            case .head: headPoint
            case .shoulders: shoulderPoint
            case .other: otherPoint
            }
            let radius: CGFloat = dot.part == .other ? 4 : 6
            let circle = Path(ellipseIn: CGRect(x: dot.point.x - radius, y: dot.point.y - radius,
                                                width: radius * 2, height: radius * 2))
            if dot.measured {
                context.fill(circle, with: .color(colour))
                context.stroke(circle, with: .color(.black.opacity(0.6)), lineWidth: 1)
            } else {
                // Found, but too unsure for the measurements to use.
                context.stroke(circle, with: .color(colour.opacity(0.7)), lineWidth: 1.5)
            }
        }

        // Today's middle of the shoulders, in the shoulders' point colour.
        if let centre = overlay.shoulderCentre {
            let ring = Path(ellipseIn: CGRect(x: centre.x - 5, y: centre.y - 5, width: 10, height: 10))
            context.stroke(ring, with: .color(shoulderPoint), lineWidth: 2)

            // The countdown, under the shoulders, in the posture's colour.
            if let reading, let text = reading.countdown {
                label(text, at: centre, colour: reading.status.map(Self.colour) ?? unjudged,
                      in: &context, offset: CGSize(width: 0, height: 36), font: .callout.weight(.bold))
            }
        }
    }

    private func label(_ text: String, at point: CGPoint, colour: Color,
                       in context: inout GraphicsContext, offset: CGSize,
                       font: Font = .caption2.weight(.semibold)) {
        let resolved = context.resolve(Text(text).font(font.monospacedDigit()).foregroundStyle(colour))
        let size = resolved.measure(in: CGSize(width: 300, height: 40))
        let centre = CGPoint(x: point.x + offset.width, y: point.y + offset.height)
        let box = CGRect(x: centre.x - size.width / 2 - 5, y: centre.y - size.height / 2 - 2,
                         width: size.width + 10, height: size.height + 4)
        context.fill(Path(roundedRect: box, cornerRadius: 5), with: .color(.black.opacity(0.6)))
        context.draw(resolved, at: centre)
    }
}
