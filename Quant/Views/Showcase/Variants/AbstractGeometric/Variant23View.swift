import SwiftUI
import PostureLogic

/// Variant 23: Concentric Target — A bullseye target with 5 colored rings.
/// Five metric dots are plotted on the target, drifting outward as metrics degrade.
/// Each dot has a distinct shape and trails a 30-sample motion path.
struct Variant23View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var trailBuffers: [[CGPoint]] = Array(repeating: [], count: 5)

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private let dotAngles: [CGFloat] = [
        -.pi / 2,
        -.pi / 2 + 1 * (2 * .pi / 5),
        -.pi / 2 + 2 * (2 * .pi / 5),
        -.pi / 2 + 3 * (2 * .pi / 5),
        -.pi / 2 + 4 * (2 * .pi / 5)
    ]

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        targetContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    targetContent(size: geo.size, isLandscape: isLandscape)
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

    private func targetContent(size: CGSize, isLandscape: Bool) -> some View {
        let chartSize = min(size.width, size.height) * 0.8
        let maxRadius = chartSize / 2

        return TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
            let ratios: [Float] = MetricKey.allCases.map { key in
                isAbsent ? 0 : observer.data.metric(for: key).clampedRatio
            }

            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height / 2

                // Concentric rings
                let ringColors: [(Color, CGFloat)] = [
                    (.red, 0.90),
                    (.orange, 0.70),
                    (.yellow, 0.50),
                    (.green.opacity(0.7), 0.30),
                    (.green, 0.15)
                ]

                for (color, radiusFraction) in ringColors {
                    let r = maxRadius * radiusFraction
                    let ringPath = Path(ellipseIn: CGRect(
                        x: cx - r, y: cy - r, width: r * 2, height: r * 2
                    ))
                    context.fill(ringPath, with: .color(color.opacity(0.15)))
                    context.stroke(ringPath, with: .color(color.opacity(0.2)), style: StrokeStyle(lineWidth: 0.5))
                }

                // Crosshair
                var crosshairPath = Path()
                crosshairPath.move(to: CGPoint(x: cx - maxRadius, y: cy))
                crosshairPath.addLine(to: CGPoint(x: cx + maxRadius, y: cy))
                crosshairPath.move(to: CGPoint(x: cx, y: cy - maxRadius))
                crosshairPath.addLine(to: CGPoint(x: cx, y: cy + maxRadius))
                context.stroke(
                    crosshairPath,
                    with: .color(.secondary.opacity(0.15)),
                    style: StrokeStyle(lineWidth: 0.5)
                )

                // Motion trails + dots
                for i in 0..<5 {
                    let angle = dotAngles[i]
                    let r = maxRadius * 0.9 * CGFloat(ratios[i])
                    let dotPos = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))

                    // Trail
                    if trailBuffers[i].count > 1 {
                        var trailPath = Path()
                        trailPath.move(to: trailBuffers[i][0])
                        for j in 1..<trailBuffers[i].count {
                            trailPath.addLine(to: trailBuffers[i][j])
                        }
                        let opacity = 0.3 * (1.0 - CGFloat(i) * 0.05)
                        context.stroke(
                            trailPath,
                            with: .color(.primary.opacity(opacity)),
                            style: StrokeStyle(lineWidth: 1, lineCap: .round)
                        )
                    }

                    // Dot (distinct shapes via path)
                    let dotSize: CGFloat = (observer.data.isAlertMode
                        && observer.data.metric(for: MetricKey.allCases[i]).isWorstOffender)
                        ? 10 : 6

                    let dotPath = Path(ellipseIn: CGRect(
                        x: dotPos.x - dotSize, y: dotPos.y - dotSize,
                        width: dotSize * 2, height: dotSize * 2
                    ))
                    context.fill(dotPath, with: .color(.primary))

                    // Alert ring around worst offender dot
                    if observer.data.isAlertMode
                        && observer.data.metric(for: MetricKey.allCases[i]).isWorstOffender {
                        let ringPath = Path(ellipseIn: CGRect(
                            x: dotPos.x - dotSize - 4, y: dotPos.y - dotSize - 4,
                            width: (dotSize + 4) * 2, height: (dotSize + 4) * 2
                        ))
                        context.stroke(ringPath, with: .color(.red), style: StrokeStyle(lineWidth: 1.5))
                    }
                }
            }
            .frame(width: chartSize, height: chartSize)
            .onChange(of: timeline.date) { _, _ in
                updateTrails(maxRadius: maxRadius)
            }

            // Worst offender label + countdown
            if observer.data.isAlertMode {
                VStack(spacing: 4) {
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
                .offset(y: chartSize / 2 + 30)
            }
        }
    }

    private func updateTrails(maxRadius: CGFloat) {
        let cx = maxRadius
        let cy = maxRadius
        for i in 0..<5 {
            let ratio = isAbsent ? Float(0) : observer.data.metric(for: MetricKey.allCases[i]).clampedRatio
            let angle = dotAngles[i]
            let r = maxRadius * 0.9 * CGFloat(ratio)
            let pos = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))

            trailBuffers[i].append(pos)
            if trailBuffers[i].count > 30 {
                trailBuffers[i].removeFirst()
            }
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant23View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .lateralLean,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant23View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant23View()
        .environmentObject(observer)
}
