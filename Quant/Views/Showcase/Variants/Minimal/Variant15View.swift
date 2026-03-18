import SwiftUI
import PostureLogic

/// Variant 15: Thin Line — A single horizontal line deforms based on five metrics:
/// sag (forward creep), droop (head drop), waves (shoulder rounding),
/// tilt (lateral lean), and zigzag (twist).
struct Variant15View: View {
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
            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        lineContent(size: geo.size)
                    }
                } else {
                    lineContent(size: geo.size)
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

    private func lineContent(size: CGSize) -> some View {
        let metrics = observer.data
        let fc = isAbsent ? Float(0) : metrics.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : metrics.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : metrics.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : metrics.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : metrics.metric(for: .twist).clampedRatio

        let strokeWidth: CGFloat = observer.data.isAlertMode
            ? (observer.data.postureState.isBad ? 6 : 4)
            : 2

        let strokeColor: Color = observer.data.postureState.isBad
            ? .red
            : (observer.data.postureState.isDrifting ? .yellow : .primary)

        return ZStack {
            // Main deformable line via Canvas
            Canvas { context, canvasSize in
                let baseY = canvasSize.height / 2
                let steps = 100
                let dx = canvasSize.width / CGFloat(steps)

                var path = Path()
                for i in 0...steps {
                    let x = CGFloat(i) * dx
                    let t = CGFloat(i) / CGFloat(steps)

                    // Forward creep sag (center sag)
                    let sagFactor = sin(t * .pi) * CGFloat(fc) * 40

                    // Head drop (left third droop)
                    let droopFactor = (t < 0.33)
                        ? sin(t / 0.33 * .pi) * CGFloat(hd) * 30
                        : 0

                    // Shoulder rounding (sinusoidal wave)
                    let waveFactor = sin(t * .pi * 4) * CGFloat(sr) * 20

                    // Twist (zigzag noise)
                    let zigzagFactor: CGFloat = {
                        let segment = Int(t * 16)
                        return (segment % 2 == 0 ? 1 : -1) * CGFloat(tw) * 10
                    }()

                    let y = baseY + sagFactor + droopFactor + waveFactor + zigzagFactor

                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                // Apply lateral lean tilt
                let tiltAngle = Angle(degrees: Double(ll) * 15)
                let transform = CGAffineTransform(translationX: canvasSize.width / 2, y: canvasSize.height / 2)
                    .rotated(by: tiltAngle.radians)
                    .translatedBy(x: -canvasSize.width / 2, y: -canvasSize.height / 2)
                let tiltedPath = path.applying(transform)

                // Glow for worst offender region in alert mode
                if observer.data.isAlertMode {
                    context.addFilter(.shadow(color: strokeColor.opacity(0.5), radius: 8))
                }

                // Fragmentation in bad state
                let dashPattern: [CGFloat] = observer.data.postureState.isBad
                    ? [12, 8, 20, 10, 15, 12]
                    : []

                context.stroke(
                    tiltedPath,
                    with: .color(strokeColor),
                    style: StrokeStyle(
                        lineWidth: strokeWidth,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: dashPattern
                    )
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Metric labels below the line
            if !isAbsent {
                metricLabels(size: size)
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
        }
    }

    private func metricLabels(size: CGSize) -> some View {
        let labels: [(MetricKey, CGFloat)] = [
            (.headDrop, 0.15),
            (.forwardCreep, 0.35),
            (.shoulderRounding, 0.5),
            (.lateralLean, 0.7),
            (.twist, 0.85)
        ]

        return ZStack {
            ForEach(labels, id: \.0) { key, xFraction in
                let metric = observer.data.metric(for: key)
                let isWorst = metric.isWorstOffender && observer.data.isAlertMode

                Text(key.displayName)
                    .font(isWorst ? .caption : .caption2)
                    .foregroundStyle(.primary.opacity(isWorst ? 1.0 : 0.3))
                    .position(x: size.width * xFraction, y: size.height / 2 + 30)
            }
        }
    }
}

private extension PostureState {
    var isDrifting: Bool {
        if case .drifting = self { return true }
        return false
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant15View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .shoulderRounding,
        worstRatio: 0.9
    )
    let observer = PostureDisplayObserver(source: source)
    Variant15View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant15View()
        .environmentObject(observer)
}
