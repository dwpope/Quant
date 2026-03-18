import SwiftUI
import PostureLogic

/// Variant 26: Origami Crane — A stylized crane composed of triangular facets.
/// Good posture = fully open crane with wings spread. Bad posture = progressively
/// folded crane with drooping wings, tucked neck, compressed body.
struct Variant26View: View {
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
                        craneContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    craneContent(size: geo.size, isLandscape: isLandscape)
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

    private func craneContent(size: CGSize, isLandscape: Bool) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio

        return ZStack {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height / 2
                let scale = min(canvasSize.width, canvasSize.height) / 300

                @Sendable func paperColor(stress: Float) -> Color {
                    let t = Double(min(max(stress, 0), 1))
                    return Color(
                        red: 0.95 - t * 0.25,
                        green: 0.93 - t * 0.35,
                        blue: 0.88 - t * 0.5
                    )
                }

                // Body compression from forward creep
                let bodyWidth = (40 - CGFloat(fc) * 15) * scale
                let bodyHeight = 30 * scale

                // Neck/head angle from head drop
                let neckDrop = CGFloat(hd) * 40 * scale

                // Wing fold from shoulder rounding
                let wingSpread = (80 - CGFloat(sr) * 50) * scale
                let wingDroop = CGFloat(sr) * 25 * scale

                // Lateral tilt
                let tiltAngle = Angle(degrees: Double(ll) * 20)

                // Twist: asymmetric wing fold
                let leftWingExtra = CGFloat(tw) * 20 * scale
                let rightWingExtra = -CGFloat(tw) * 20 * scale

                // Apply global tilt transform
                let tiltTransform = CGAffineTransform(translationX: cx, y: cy)
                    .rotated(by: tiltAngle.radians)
                    .translatedBy(x: -cx, y: -cy)

                // Body diamond (2 triangles)
                let bodyTop = CGPoint(x: cx, y: cy - bodyHeight)
                let bodyBottom = CGPoint(x: cx, y: cy + bodyHeight)
                let bodyLeft = CGPoint(x: cx - bodyWidth, y: cy)
                let bodyRight = CGPoint(x: cx + bodyWidth, y: cy)

                drawFacet(context: context, points: [bodyTop, bodyLeft, bodyBottom],
                         fillColor: paperColor(stress: fc), transform: tiltTransform)
                drawFacet(context: context, points: [bodyTop, bodyRight, bodyBottom],
                         fillColor: paperColor(stress: fc), transform: tiltTransform)

                // Neck + head (triangle above body)
                let neckTip = CGPoint(x: cx, y: cy - bodyHeight - 50 * scale + neckDrop)
                let neckLeft = CGPoint(x: cx - 8 * scale, y: cy - bodyHeight)
                let neckRight = CGPoint(x: cx + 8 * scale, y: cy - bodyHeight)

                drawFacet(context: context, points: [neckTip, neckLeft, neckRight],
                         fillColor: paperColor(stress: hd), transform: tiltTransform)

                // Left wing (2 triangles)
                let leftWingTip = CGPoint(x: cx - wingSpread - leftWingExtra, y: cy - 10 * scale + wingDroop)
                let leftWingMid = CGPoint(x: cx - bodyWidth * 0.7, y: cy - bodyHeight * 0.5)

                drawFacet(context: context, points: [bodyLeft, leftWingMid, leftWingTip],
                         fillColor: paperColor(stress: sr), transform: tiltTransform)
                drawFacet(context: context, points: [bodyLeft, leftWingTip, CGPoint(x: cx - bodyWidth * 0.5, y: cy + 5 * scale)],
                         fillColor: paperColor(stress: sr), transform: tiltTransform)

                // Right wing (2 triangles)
                let rightWingTip = CGPoint(x: cx + wingSpread + rightWingExtra, y: cy - 10 * scale + wingDroop)
                let rightWingMid = CGPoint(x: cx + bodyWidth * 0.7, y: cy - bodyHeight * 0.5)

                drawFacet(context: context, points: [bodyRight, rightWingMid, rightWingTip],
                         fillColor: paperColor(stress: sr), transform: tiltTransform)
                drawFacet(context: context, points: [bodyRight, rightWingTip, CGPoint(x: cx + bodyWidth * 0.5, y: cy + 5 * scale)],
                         fillColor: paperColor(stress: sr), transform: tiltTransform)

                // Tail (triangle below body)
                let tailTip = CGPoint(x: cx, y: cy + bodyHeight + 35 * scale)
                let tailLeft = CGPoint(x: cx - 10 * scale, y: cy + bodyHeight)
                let tailRight = CGPoint(x: cx + 10 * scale, y: cy + bodyHeight)

                drawFacet(context: context, points: [tailTip, tailLeft, tailRight],
                         fillColor: paperColor(stress: 0), transform: tiltTransform)

                // Center fold crease line
                let creaseOpacity = 0.1 + Double(1.0 - observer.data.aggregateScore) * 0.3
                var creasePath = Path()
                creasePath.move(to: neckTip.applying(tiltTransform))
                creasePath.addLine(to: tailTip.applying(tiltTransform))
                context.stroke(
                    creasePath,
                    with: .color(.primary.opacity(creaseOpacity)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Alert info
            VStack {
                Spacer()
                if observer.data.isAlertMode {
                    if let worst = observer.data.worstOffender {
                        Text(worst.key.displayName)
                            .font(.caption.bold())
                            .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                    }
                    if let seconds = observer.data.nudgeCountdownSeconds {
                        Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func drawFacet(context: GraphicsContext, points: [CGPoint], fillColor: Color, transform: CGAffineTransform) {
        guard points.count >= 3 else { return }

        var path = Path()
        path.move(to: points[0].applying(transform))
        for i in 1..<points.count {
            path.addLine(to: points[i].applying(transform))
        }
        path.closeSubpath()

        context.fill(path, with: .color(fillColor.opacity(0.6)))
        context.stroke(path, with: .color(.primary.opacity(0.5)), style: StrokeStyle(lineWidth: 1))
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant26View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .shoulderRounding,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant26View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant26View()
        .environmentObject(observer)
}
