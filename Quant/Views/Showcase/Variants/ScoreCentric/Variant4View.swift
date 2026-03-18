import SwiftUI
import PostureLogic

struct Variant4View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var markerOscillation: CGFloat = 0
    @State private var isGlowPulsing = false
    @State private var isCountdownFlashing = false

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        if isLandscape {
                            landscapeLayout(size: geo.size)
                        } else {
                            portraitLayout(size: geo.size)
                        }
                    }
                } else {
                    if isLandscape {
                        landscapeLayout(size: geo.size)
                    } else {
                        portraitLayout(size: geo.size)
                    }
                }

                // Settings gear at center-bottom of arc
                VStack {
                    Spacer()
                    SettingsGearButton { showingSettings = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
        }
        .sensoryFeedback(.impact, trigger: observer.data.postureState.isBad)
        .animation(PostureAnimations.alertOnset, value: observer.data.isAlertMode)
    }

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    // MARK: - Portrait Layout

    private func portraitLayout(size: CGSize) -> some View {
        VStack(spacing: 16) {
            arcSection(size: CGSize(width: size.width * 0.9, height: size.width * 0.5))

            scoreLabel

            if observer.data.isAlertMode {
                alertMetricInfo
                countdownBar(width: size.width * 0.8)
            } else {
                metricDotsList
            }

            Spacer()
        }
        .padding(.top, 40)
    }

    // MARK: - Landscape Layout

    private func landscapeLayout(size: CGSize) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                VStack(spacing: 12) {
                    arcSection(size: CGSize(width: size.width * 0.55, height: size.height * 0.45))
                    scoreLabel
                }

                VStack(alignment: .leading, spacing: 10) {
                    if observer.data.isAlertMode {
                        alertMetricInfo
                    } else {
                        metricDotsList
                    }
                }
                .frame(maxWidth: size.width * 0.35)
            }

            if observer.data.isAlertMode {
                countdownBar(width: size.width * 0.9)
            }
        }
        .padding()
    }

    // MARK: - Arc Section

    private func arcSection(size: CGSize) -> some View {
        let data = observer.data
        let score = CGFloat(data.aggregateScore)
        let arcAngleSpan: CGFloat = 180 // degrees
        let startAngle: CGFloat = 180   // left side (pi radians)
        let scoreAngle = startAngle + arcAngleSpan * (1.0 - score) + markerOscillation

        let radius = size.width * 0.42
        let centerX = size.width / 2
        let centerY = size.height * 0.85

        let markerX = centerX + radius * cos(scoreAngle * .pi / 180)
        let markerY = centerY + radius * sin(scoreAngle * .pi / 180)

        return ZStack {
            // Arc with gradient stroke
            ArcShape(startAngle: .degrees(startAngle), endAngle: .degrees(startAngle + arcAngleSpan))
                .stroke(
                    AngularGradient(
                        colors: [.green, .yellow, .red],
                        center: .center,
                        startAngle: .degrees(startAngle),
                        endAngle: .degrees(startAngle + arcAngleSpan)
                    ),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .frame(width: radius * 2, height: radius * 2)
                .position(x: centerX, y: centerY)

            // Glow behind marker
            Circle()
                .fill(markerColor(score: score).opacity(0.5))
                .frame(width: data.postureState.isBad ? (isGlowPulsing ? 36 : 12) : (data.isAlertMode ? 34 : 28), height: data.postureState.isBad ? (isGlowPulsing ? 36 : 12) : (data.isAlertMode ? 34 : 28))
                .blur(radius: data.postureState.isBad ? (isGlowPulsing ? 16 : 4) : (data.isAlertMode ? 12 : 8))
                .position(x: markerX, y: markerY)

            // Marker dot
            Circle()
                .fill(.white)
                .frame(width: 18, height: 18)
                .shadow(color: markerColor(score: score), radius: 8)
                .position(x: markerX, y: markerY)
        }
        .frame(width: size.width, height: size.height)
        .animation(.interpolatingSpring(stiffness: 100, damping: 10), value: score)
        .onAppear {
            if data.isAlertMode {
                startOscillation()
            }
            if data.postureState.isBad {
                isGlowPulsing = true
                isCountdownFlashing = true
            }
        }
        .onChange(of: data.isAlertMode) { _, isAlert in
            if isAlert {
                startOscillation()
            } else {
                stopOscillation()
            }
        }
        .onChange(of: data.postureState.isBad) { _, isBad in
            isGlowPulsing = isBad
            isCountdownFlashing = isBad
        }
        .animation(
            data.postureState.isBad
                ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                : .default,
            value: isGlowPulsing
        )
    }

    // MARK: - Score Label

    private var scoreLabel: some View {
        let data = observer.data
        let score = data.aggregateScore
        return Text("\(Int(score * 100))")
            .font(.system(size: 72, weight: .ultraLight, design: .rounded))
            .foregroundStyle(
                data.postureState.isBad
                    ? Color(hue: 0.02, saturation: 0.9, brightness: 0.8)
                    : .primary
            )
            .contentTransition(.numericText())
            .animation(.snappy, value: Int(score * 100))
    }

    // MARK: - Metric Dots List

    private var metricDotsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(observer.data.metrics, id: \.key) { metric in
                HStack(spacing: 8) {
                    Circle()
                        .fill(metricDotColor(ratio: metric.ratio))
                        .frame(width: 8, height: 8)

                    Text(metric.key.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Alert Mode Info

    private var alertMetricInfo: some View {
        VStack(spacing: 8) {
            if let worst = observer.data.worstOffender {
                Text(worst.key.displayName)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))

                Text(String(format: "%.0f%%", worst.clampedRatio * 100))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("\(observer.data.metrics.filter { !$0.isWorstOffender }.count) metrics OK")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Countdown Bar

    private func countdownBar(width: CGFloat) -> some View {
        Group {
            if let seconds = observer.data.nudgeCountdownSeconds {
                let maxSeconds: CGFloat = 30
                let progress = CGFloat(max(0, min(seconds, Double(maxSeconds)))) / maxSeconds

                RoundedRectangle(cornerRadius: 2)
                    .fill(PostureVisualStyle.stateColor(for: observer.data.postureState))
                    .frame(width: width * progress, height: 4)
                    .frame(maxWidth: width, alignment: .leading)
                    .animation(.linear(duration: 1), value: seconds)
                    .opacity(observer.data.postureState.isBad ? (isCountdownFlashing ? 0.3 : 1.0) : 1.0)
                    .animation(
                        observer.data.postureState.isBad
                            ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                            : .default,
                        value: isCountdownFlashing
                    )
            }
        }
    }

    // MARK: - Helpers

    private func markerColor(score: CGFloat) -> Color {
        if observer.data.postureState.isBad {
            return Color(hue: 0.02, saturation: 0.9, brightness: 0.8)
        }
        if score > 0.7 {
            return Color(hue: 0.38, saturation: 0.6, brightness: 0.7) // green
        } else if score > 0.4 {
            return Color(hue: 0.12, saturation: 0.7, brightness: 0.8) // yellow
        } else {
            return Color(hue: 0.02, saturation: 0.9, brightness: 0.8) // red
        }
    }

    private func metricDotColor(ratio: Float) -> Color {
        if ratio < 0.5 {
            return Color(hue: 0.38, saturation: 0.6, brightness: 0.7) // green
        } else if ratio <= 0.8 {
            return Color(hue: 0.12, saturation: 0.7, brightness: 0.8) // yellow
        } else {
            return Color(hue: 0.02, saturation: 0.9, brightness: 0.8) // red
        }
    }

    private func startOscillation() {
        // Start at -5.4 so autoreverses oscillates symmetrically: -5.4 → +5.4 → -5.4
        markerOscillation = -5.4
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            // +/- 3% of 180 degree arc = ~5.4 degrees
            markerOscillation = 5.4
        }
    }

    private func stopOscillation() {
        withAnimation(.easeOut(duration: 0.3)) {
            markerOscillation = 0
        }
    }
}

// MARK: - Arc Shape

private struct ArcShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant4View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant4View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant4View()
        .environmentObject(observer)
}
