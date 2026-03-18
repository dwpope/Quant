import SwiftUI
import PostureLogic

struct Variant10View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var fractureProgress: CGFloat = 0

    private var data: PostureDisplayData { observer.data }

    private let dialSize: CGFloat = 80
    private let pentagonRadius: CGFloat = 100
    private let sweepDegrees: Double = 300
    private let startDegrees: Double = 210 // 7 o'clock

    private var isAbsent: Bool {
        switch data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private var isFire: Bool {
        if case .fire = data.nudgeDecision { return true }
        return false
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        dialContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    dialContent(size: geo.size, isLandscape: isLandscape)
                }

                VStack {
                    HStack {
                        Spacer()
                        SettingsGearButton { showingSettings = true }
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
        }
        .sensoryFeedback(.impact, trigger: data.postureState.isBad)
        .animation(PostureAnimations.alertOnset, value: data.isAlertMode)
        .onChange(of: isFire) { _, newValue in
            if newValue {
                withAnimation(.easeOut(duration: 0.5)) {
                    fractureProgress = 1.0
                }
            } else {
                fractureProgress = 0
            }
        }
    }

    // MARK: - Dial Content

    private func dialContent(size: CGSize, isLandscape: Bool) -> some View {
        Group {
            if isLandscape {
                landscapeLayout(size: size)
            } else {
                pentagonLayout(size: size)
            }
        }
    }

    // MARK: - Pentagon Layout (Portrait)

    private func pentagonLayout(size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        return ZStack {
            // Five dials in pentagon
            ForEach(Array(data.metrics.enumerated()), id: \.element.key) { index, metric in
                let angle = -90.0 + Double(index) * 72.0
                let rad = angle * .pi / 180
                let isWorst = metric.isWorstOffender && data.isAlertMode
                let currentDialSize = isWorst ? 120 : (data.isAlertMode ? 60 : dialSize)
                let radius = isWorst ? pentagonRadius * 0.5 : pentagonRadius

                dialView(metric: metric, size: currentDialSize)
                    .offset(
                        x: cos(rad) * radius,
                        y: sin(rad) * radius
                    )
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: isWorst)
            }

            // Center score
            VStack(spacing: 2) {
                if data.isAlertMode, let seconds = data.nudgeCountdownSeconds {
                    NudgeCountdownLabel(seconds: seconds, style: .compact)
                        .font(.title3.monospacedDigit())
                } else {
                    Text("\(Int(data.aggregateScore * 100))")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Landscape Layout (Row)

    private func landscapeLayout(size: CGSize) -> some View {
        VStack(spacing: 12) {
            // Score above
            if data.isAlertMode, let seconds = data.nudgeCountdownSeconds {
                NudgeCountdownLabel(seconds: seconds, style: .compact)
                    .font(.title3.monospacedDigit())
            } else {
                Text("\(Int(data.aggregateScore * 100))")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
            }

            HStack(spacing: 16) {
                ForEach(Array(data.metrics.enumerated()), id: \.element.key) { index, metric in
                    let isWorst = metric.isWorstOffender && data.isAlertMode
                    let currentDialSize: CGFloat = isWorst ? 110 : 90

                    dialView(metric: metric, size: currentDialSize)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: isWorst)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Individual Dial

    private func dialView(metric: MetricInfo, size: CGFloat) -> some View {
        let isWorst = metric.isWorstOffender && data.isAlertMode
        let displayRatio = data.postureState.isBad && !isWorst
            ? min(1.0, metric.clampedRatio + 0.1) // sympathetic swing
            : metric.clampedRatio
        let needleAngle = startDegrees + Double(displayRatio) * sweepDegrees
        let glowColor = data.postureState.isBad ? Color.red : Color.yellow

        return VStack(spacing: 4) {
            ZStack {
                // Background gradient (very subtle)
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.green.opacity(0.08), .yellow.opacity(0.08), .red.opacity(0.08), .red.opacity(0.08)],
                            center: .center,
                            startAngle: .degrees(startDegrees),
                            endAngle: .degrees(startDegrees + sweepDegrees)
                        )
                    )
                    .opacity(isWorst ? 0.25 : 0.08)

                // Bezel
                Circle()
                    .stroke(.secondary.opacity(0.5), lineWidth: 1.5)

                // Glow in alert
                if isWorst {
                    Circle()
                        .stroke(glowColor.opacity(0.5), lineWidth: 3)
                        .blur(radius: 6)
                }

                // Tick marks
                Canvas { context, canvasSize in
                    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    let tickRadius = min(canvasSize.width, canvasSize.height) / 2 - 4
                    for i in 0...4 {
                        let fraction = Double(i) / 4.0
                        let angleDeg = startDegrees + fraction * sweepDegrees
                        let angleRad = angleDeg * .pi / 180
                        let inner = tickRadius - 6
                        var tick = Path()
                        tick.move(to: CGPoint(
                            x: center.x + inner * cos(angleRad),
                            y: center.y + inner * sin(angleRad)
                        ))
                        tick.addLine(to: CGPoint(
                            x: center.x + tickRadius * cos(angleRad),
                            y: center.y + tickRadius * sin(angleRad)
                        ))
                        context.stroke(tick, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
                    }
                }

                // Needle
                needleView(angle: needleAngle, length: size * 0.35)

                // Countdown arc on bezel for worst
                if isWorst, let seconds = data.nudgeCountdownSeconds {
                    let maxSeconds: Double = 30
                    let progress = max(0, min(seconds, maxSeconds)) / maxSeconds
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(glowColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }

                // Fracture path in fire state
                if isWorst && isFire {
                    FracturePath()
                        .trim(from: 0, to: fractureProgress)
                        .stroke(.white.opacity(0.8), lineWidth: 1)
                }

                // Needle tip dot
                Circle()
                    .fill(PostureVisualStyle.metricColor(ratio: metric.clampedRatio))
                    .frame(width: 4, height: 4)
                    .offset(
                        x: cos(needleAngle * .pi / 180) * size * 0.32,
                        y: sin(needleAngle * .pi / 180) * size * 0.32
                    )
            }
            .frame(width: size, height: size)

            Text(metric.key.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Needle

    private func needleView(angle: Double, length: CGFloat) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.white, Color(white: 0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 2, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(angle))
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: angle)
    }
}

// MARK: - Fracture Path

private struct FracturePath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        // Jagged crack across the dial face
        path.move(to: CGPoint(x: cx - rect.width * 0.35, y: cy - rect.height * 0.1))
        path.addLine(to: CGPoint(x: cx - rect.width * 0.15, y: cy + rect.height * 0.05))
        path.addLine(to: CGPoint(x: cx - rect.width * 0.05, y: cy - rect.height * 0.08))
        path.addLine(to: CGPoint(x: cx + rect.width * 0.1, y: cy + rect.height * 0.03))
        path.addLine(to: CGPoint(x: cx + rect.width * 0.2, y: cy - rect.height * 0.12))
        path.addLine(to: CGPoint(x: cx + rect.width * 0.35, y: cy + rect.height * 0.05))
        return path
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant10View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant10View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant10View()
        .environmentObject(observer)
}
