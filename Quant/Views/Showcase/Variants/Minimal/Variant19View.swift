import SwiftUI
import PostureLogic

/// Variant 19: Concentric Ripples — Concentric circles emanate from the center
/// like ripples on a pond. Good posture = calm, even circles. Bad posture =
/// irregular, distorted, overlapping rings with per-metric distortions.
struct Variant19View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var ripples: [Ripple] = []

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private var spawnInterval: Double {
        switch observer.data.postureState {
        case .good: return 2.0
        case .drifting: return 1.2
        case .bad: return 0.6
        default: return 2.0
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        rippleCanvas(size: geo.size)
                    }
                } else {
                    rippleCanvas(size: geo.size)
                }

                // Center score and metric dots
                if !isAbsent {
                    centerDisplay
                }

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

    private func rippleCanvas(size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 0.03)) { timeline in
            let now = timeline.date.timeIntervalSince1970
            let maxRadius = max(size.width, size.height) * 0.6

            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

                // Metric-driven distortion parameters
                let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
                let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
                let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
                let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
                let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio

                // Generate ripple phases based on time
                let ringCount = 8
                for i in 0..<ringCount {
                    let phase = (now.truncatingRemainder(dividingBy: spawnInterval * Double(ringCount)))
                    let ringPhase = (phase + Double(i) * spawnInterval) / (spawnInterval * Double(ringCount))
                    let radius = CGFloat(ringPhase) * maxRadius

                    guard radius > 0 else { continue }

                    let opacity = max(0, 1.0 - (radius / maxRadius))
                    guard opacity > 0.01 else { continue }

                    // Distortions
                    let yStretch = 1.0 + CGFloat(fc) * 0.3  // Forward creep → vertical stretch
                    let centerYOffset = CGFloat(hd) * 30     // Head drop → origin drifts down
                    let wobbleAmp = CGFloat(sr) * 8          // Shoulder rounding → radius wobble
                    let xOffset = CGFloat(ll) * 20           // Lateral lean → off-center
                    let rotation = CGFloat(tw) * 0.3 * CGFloat(i)  // Twist → spiral rotation

                    let adjustedCenter = CGPoint(
                        x: center.x + xOffset,
                        y: center.y + centerYOffset
                    )

                    // Draw distorted ring
                    var path = Path()
                    let segments = 60
                    for s in 0...segments {
                        let angle = Double(s) / Double(segments) * 2 * .pi + Double(rotation)
                        let wobble = sin(angle * 4) * Double(wobbleAmp)
                        let r = Double(radius) + wobble

                        let x = adjustedCenter.x + CGFloat(r * cos(angle))
                        let y = adjustedCenter.y + CGFloat(r * sin(angle) * Double(yStretch))

                        if s == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    path.closeSubpath()

                    let strokeWidth: CGFloat = observer.data.postureState.isBad
                        ? CGFloat.random(in: 1...4)
                        : 1.5

                    let strokeColor: Color = observer.data.postureState.isBad
                        ? .red : (observer.data.isAlertMode ? .yellow : .primary)

                    context.stroke(
                        path,
                        with: .color(strokeColor.opacity(opacity * 0.4)),
                        style: StrokeStyle(lineWidth: strokeWidth)
                    )
                }
            }
        }
    }

    private var centerDisplay: some View {
        VStack(spacing: 8) {
            Text(String(format: "%.0f", observer.data.aggregateScore * 100))
                .font(.system(size: observer.data.isAlertMode ? 28 : 32,
                              weight: .light, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.snappy, value: Int(observer.data.aggregateScore * 100))

            HStack(spacing: 4) {
                ForEach(observer.data.metrics, id: \.key) { metric in
                    Circle()
                        .fill(PostureVisualStyle.metricColor(ratio: metric.ratio))
                        .frame(width: metric.isWorstOffender && observer.data.isAlertMode ? 8 : 5,
                               height: metric.isWorstOffender && observer.data.isAlertMode ? 8 : 5)
                }
            }

            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                Text(worst.key.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Ripple model

private struct Ripple: Identifiable {
    let id = UUID()
    let spawnTime: TimeInterval
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant19View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .twist,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant19View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant19View()
        .environmentObject(observer)
}
