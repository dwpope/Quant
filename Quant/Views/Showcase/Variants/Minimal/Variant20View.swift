import SwiftUI
import PostureLogic

/// Variant 20: Kanji / Symbol — A custom-drawn abstract glyph morphs continuously.
/// Five metrics deform the symbol: forward lean tilts the top, head drop shortens it,
/// shoulder rounding bows the crossbar, lateral lean tilts everything, twist skews endpoints.
struct Variant20View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var breathScale: CGFloat = 0.98

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
                        symbolContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    symbolContent(size: geo.size, isLandscape: isLandscape)
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
        .onAppear { startBreathing() }
        .onChange(of: observer.data.postureState) { _, _ in startBreathing() }
    }

    private func symbolContent(size: CGSize, isLandscape: Bool) -> some View {
        VStack(spacing: 16) {
            Spacer()

            glyphCanvas(size: CGSize(width: 200, height: 200))
                .frame(width: 200, height: 200)
                .scaleEffect(breathScale)

            if !isAbsent {
                // State label
                Text(PostureVisualStyle.stateLabel(for: observer.data.postureState))
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.3))

                // Worst offender in alert mode
                if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                    Text(worst.key.displayName)
                        .font(.caption)
                        .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                        .transition(.opacity)
                }

                // Countdown
                if let seconds = observer.data.nudgeCountdownSeconds {
                    Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // Landscape: annotations
            if isLandscape && !isAbsent {
                metricAnnotations
            }

            Spacer()
        }
    }

    private func glyphCanvas(size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
            let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
            let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
            let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
            let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio

            let tremorActive = observer.data.isAlertMode && !isAbsent
            let tremorAmp: CGFloat = observer.data.postureState.isBad ? 3 : 1

            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height / 2

                let strokeColor: Color = observer.data.postureState.isBad
                    ? .red : (observer.data.isAlertMode ? .yellow : .primary)

                let strokeWidth: CGFloat = 3
                let dashPattern: [CGFloat] = observer.data.postureState.isBad
                    ? [15, 5, 10, 8] : []

                // Deformation parameters
                let topXShift = CGFloat(fc) * 30     // Forward creep shifts top right
                let topYShift = CGFloat(hd) * 30     // Head drop shortens from top
                let bowDepth = CGFloat(sr) * 25      // Shoulder rounding bows crossbar
                let tiltAngle = CGFloat(ll) * 20     // Lateral lean tilts everything
                let twistY = CGFloat(tw) * 15        // Twist skews horizontal endpoints

                // Tremor noise
                let tremor: () -> CGFloat = {
                    tremorActive ? CGFloat.random(in: -tremorAmp...tremorAmp) : 0
                }

                // Vertical stroke: from top to bottom
                let topPoint = CGPoint(
                    x: cx + topXShift + tremor(),
                    y: cy - 80 + topYShift + tremor()
                )
                let bottomPoint = CGPoint(
                    x: cx + tremor(),
                    y: cy + 80 + tremor()
                )

                var verticalPath = Path()
                verticalPath.move(to: topPoint)
                verticalPath.addLine(to: bottomPoint)

                // Horizontal stroke: bowed crossbar
                let leftPoint = CGPoint(
                    x: cx - 70 + tremor(),
                    y: cy - twistY + tremor()
                )
                let rightPoint = CGPoint(
                    x: cx + 70 + tremor(),
                    y: cy + twistY + tremor()
                )
                let bowControl = CGPoint(
                    x: cx + tremor(),
                    y: cy + bowDepth + tremor()
                )

                var horizontalPath = Path()
                horizontalPath.move(to: leftPoint)
                horizontalPath.addQuadCurve(to: rightPoint, control: bowControl)

                // Wing serifs at endpoints
                let serifLength: CGFloat = 12
                var serifPath = Path()
                // Top serif
                serifPath.move(to: CGPoint(x: topPoint.x - serifLength, y: topPoint.y))
                serifPath.addLine(to: CGPoint(x: topPoint.x + serifLength, y: topPoint.y))
                // Bottom serif
                serifPath.move(to: CGPoint(x: bottomPoint.x - serifLength, y: bottomPoint.y))
                serifPath.addLine(to: CGPoint(x: bottomPoint.x + serifLength, y: bottomPoint.y))
                // Left serif
                serifPath.move(to: CGPoint(x: leftPoint.x, y: leftPoint.y - serifLength))
                serifPath.addLine(to: CGPoint(x: leftPoint.x, y: leftPoint.y + serifLength))
                // Right serif
                serifPath.move(to: CGPoint(x: rightPoint.x, y: rightPoint.y - serifLength))
                serifPath.addLine(to: CGPoint(x: rightPoint.x, y: rightPoint.y + serifLength))

                // Apply global tilt
                let tiltTransform = CGAffineTransform(translationX: cx, y: cy)
                    .rotated(by: Angle(degrees: Double(tiltAngle)).radians)
                    .translatedBy(x: -cx, y: -cy)

                let style = StrokeStyle(
                    lineWidth: strokeWidth,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: dashPattern
                )

                context.stroke(
                    verticalPath.applying(tiltTransform),
                    with: .color(strokeColor.opacity(0.8)),
                    style: style
                )
                context.stroke(
                    horizontalPath.applying(tiltTransform),
                    with: .color(strokeColor.opacity(0.8)),
                    style: style
                )
                context.stroke(
                    serifPath.applying(tiltTransform),
                    with: .color(strokeColor.opacity(0.5)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashPattern)
                )
            }
        }
    }

    private var metricAnnotations: some View {
        HStack(spacing: 20) {
            ForEach(observer.data.metrics, id: \.key) { metric in
                VStack(spacing: 2) {
                    Circle()
                        .fill(PostureVisualStyle.metricColor(ratio: metric.ratio))
                        .frame(width: 6, height: 6)
                    Text(metric.key.displayName)
                        .font(.caption2)
                        .foregroundStyle(.primary.opacity(0.2))
                }
            }
        }
    }

    private func startBreathing() {
        breathScale = 0.98
        let duration: Double = observer.data.postureState.isBad ? 1.0 : 6.0
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            breathScale = 1.02
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant20View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .shoulderRounding,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant20View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant20View()
        .environmentObject(observer)
}
