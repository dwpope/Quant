import SwiftUI
import PostureLogic

/// Variant 21: Stacked Totem — Three geometric primitives (circle, line, ellipse)
/// arranged vertically along a spine axis. Each metric deforms a specific aspect:
/// forward creep scales the totem, head drop lowers the circle, shoulder rounding
/// arcs the line, lateral lean shifts upper elements, twist rotates the shoulder line.
struct Variant21View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        totemContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    totemContent(size: geo.size, isLandscape: isLandscape)
                }

                // Settings gear
                VStack {
                    HStack {
                        Spacer()
                        SettingsGearButton { showingSettings = true }
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
        }
        .animation(PostureAnimations.alertOnset, value: observer.data.isAlertMode)
    }

    private func totemContent(size: CGSize, isLandscape: Bool) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio

        return ZStack {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height / 2

                let overallScore = observer.data.aggregateScore
                let tintColor: Color = overallScore > 0.7 ? .primary
                    : (overallScore > 0.4 ? .orange : .red)

                // Spine axis (dashed center line)
                var spinePath = Path()
                if isLandscape {
                    spinePath.move(to: CGPoint(x: cx - canvasSize.width * 0.3, y: cy))
                    spinePath.addLine(to: CGPoint(x: cx + canvasSize.width * 0.3, y: cy))
                } else {
                    spinePath.move(to: CGPoint(x: cx, y: cy - canvasSize.height * 0.25))
                    spinePath.addLine(to: CGPoint(x: cx, y: cy + canvasSize.height * 0.25))
                }
                context.stroke(
                    spinePath,
                    with: .color(.secondary.opacity(0.15)),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )

                // Scale factor from forward creep
                let scaleFactor: CGFloat = 1.0 + CGFloat(fc) * 0.3

                // Head drop offset
                let headDropOffset = CGFloat(hd) * 40

                // Shoulder rounding arc depth
                let shoulderArcDepth = CGFloat(sr) * 30

                // Lateral lean offset
                let leanOffset = CGFloat(ll) * 40

                // Twist rotation
                let twistAngle = CGFloat(tw) * 20

                if isLandscape {
                    // Horizontal layout: torso left, shoulders center, head right
                    let torsoCenter = CGPoint(x: cx - 100, y: cy)
                    let shoulderCenter = CGPoint(x: cx, y: cy)
                    let headCenter = CGPoint(x: cx + 100 - headDropOffset, y: cy + leanOffset)

                    drawEllipse(context: context, center: torsoCenter, rx: 25 * scaleFactor, ry: 50, color: tintColor)
                    drawShoulderLine(context: context, center: shoulderCenter, halfWidth: 50, arcDepth: shoulderArcDepth, twist: twistAngle, color: tintColor, isLandscape: true)
                    drawHead(context: context, center: headCenter, radius: 20, color: tintColor)
                } else {
                    // Vertical layout: head top, shoulders middle, torso bottom
                    let headCenter = CGPoint(x: cx + leanOffset, y: cy - 80 + headDropOffset)
                    let shoulderCenter = CGPoint(x: cx + leanOffset * 0.5, y: cy - 10)
                    let torsoCenter = CGPoint(x: cx, y: cy + 60)

                    drawHead(context: context, center: headCenter, radius: 20, color: tintColor)
                    drawShoulderLine(context: context, center: shoulderCenter, halfWidth: 55, arcDepth: shoulderArcDepth, twist: twistAngle, color: tintColor, isLandscape: false)
                    drawEllipse(context: context, center: torsoCenter, rx: 30 * scaleFactor, ry: 55, color: tintColor)
                }

                // Alert mode glow
                if observer.data.isAlertMode {
                    context.addFilter(.shadow(color: .red.opacity(0.3), radius: 10))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Countdown
            if observer.data.isAlertMode, let seconds = observer.data.nudgeCountdownSeconds {
                VStack {
                    Spacer()
                    Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 20)
                }
            }

            // Worst offender label
            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                VStack {
                    Spacer()
                    Text(worst.key.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                        .padding(.bottom, 40)
                }
                .transition(.opacity)
            }
        }
    }

    private func drawHead(context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        let headPath = Path(ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))
        context.stroke(headPath, with: .color(color), style: StrokeStyle(lineWidth: 2.5))
        // Crosshair inside head
        var crossPath = Path()
        crossPath.move(to: CGPoint(x: center.x - radius * 0.5, y: center.y))
        crossPath.addLine(to: CGPoint(x: center.x + radius * 0.5, y: center.y))
        crossPath.move(to: CGPoint(x: center.x, y: center.y - radius * 0.5))
        crossPath.addLine(to: CGPoint(x: center.x, y: center.y + radius * 0.5))
        context.stroke(crossPath, with: .color(color.opacity(0.3)), style: StrokeStyle(lineWidth: 1))
    }

    private func drawShoulderLine(context: GraphicsContext, center: CGPoint, halfWidth: CGFloat, arcDepth: CGFloat, twist: CGFloat, color: Color, isLandscape: Bool) {
        let twistRad = Angle(degrees: Double(twist)).radians

        var shoulderPath = Path()
        let leftEnd = CGPoint(x: center.x - halfWidth, y: center.y)
        let rightEnd = CGPoint(x: center.x + halfWidth, y: center.y)
        let control = CGPoint(x: center.x, y: center.y + arcDepth)

        shoulderPath.move(to: leftEnd)
        shoulderPath.addQuadCurve(to: rightEnd, control: control)

        // Apply twist rotation
        let rotateTransform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: twistRad)
            .translatedBy(x: -center.x, y: -center.y)

        context.stroke(
            shoulderPath.applying(rotateTransform),
            with: .color(color),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
        )

        // Endpoint dots
        for pt in [leftEnd, rightEnd] {
            let transformed = pt.applying(rotateTransform)
            let dotPath = Path(ellipseIn: CGRect(x: transformed.x - 4, y: transformed.y - 4, width: 8, height: 8))
            context.fill(dotPath, with: .color(color))
        }
    }

    private func drawEllipse(context: GraphicsContext, center: CGPoint, rx: CGFloat, ry: CGFloat, color: Color) {
        let ellipsePath = Path(ellipseIn: CGRect(
            x: center.x - rx, y: center.y - ry,
            width: rx * 2, height: ry * 2
        ))
        context.stroke(ellipsePath, with: .color(color), style: StrokeStyle(lineWidth: 2.5))
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant21View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.9
    )
    let observer = PostureDisplayObserver(source: source)
    Variant21View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant21View()
        .environmentObject(observer)
}
