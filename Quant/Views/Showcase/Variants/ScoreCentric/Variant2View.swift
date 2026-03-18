import SwiftUI
import PostureLogic

struct Variant2View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var isPulsing = false
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

                // Settings gear
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
        VStack(spacing: 20) {
            Spacer()

            ringStack(diameter: min(size.width * 0.7, size.height * 0.5))

            metricBadgesRow

            NudgeCountdownLabel(
                seconds: observer.data.nudgeCountdownSeconds,
                style: .verbose
            )

            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Landscape Layout

    private func landscapeLayout(size: CGSize) -> some View {
        HStack(spacing: 24) {
            ringStack(diameter: min(size.width * 0.4, size.height * 0.75))
                .frame(maxWidth: size.width * 0.5)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(observer.data.metrics, id: \.key) { metric in
                    landscapeMetricRow(metric: metric)
                }

                if observer.data.isAlertMode {
                    NudgeCountdownLabel(
                        seconds: observer.data.nudgeCountdownSeconds,
                        style: .verbose
                    )
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: size.width * 0.45)
        }
        .padding()
    }

    private func landscapeMetricRow(metric: MetricInfo) -> some View {
        let isWorst = metric.isWorstOffender && observer.data.isAlertMode
        return HStack(spacing: 10) {
            miniRing(ratio: metric.clampedRatio, color: PostureVisualStyle.metricColor(ratio: metric.ratio), size: 28)

            Text(metric.key.displayName)
                .font(.subheadline)
                .foregroundStyle(isWorst ? .primary : .secondary)

            Spacer()

            Text(String(format: "%.0f%%", metric.clampedRatio * 100))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(isWorst ? .primary : .secondary)
        }
        .opacity(observer.data.isAlertMode && !metric.isWorstOffender ? 0.5 : 1.0)
    }

    // MARK: - Ring Stack

    private func ringStack(diameter: CGFloat) -> some View {
        let data = observer.data
        let score = CGFloat(data.aggregateScore)
        let worstInverted = CGFloat(1.0 - (data.worstOffender?.clampedRatio ?? 0))
        let streakFraction = streakProgress

        return ZStack {
            // Countdown ring (outermost, alert mode only)
            if data.isAlertMode, let seconds = data.nudgeCountdownSeconds {
                let maxSeconds: CGFloat = 30
                let progress = CGFloat(max(0, min(seconds, Double(maxSeconds)))) / maxSeconds

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [6, 4])
                    )
                    .foregroundStyle(PostureVisualStyle.stateColor(for: data.postureState).opacity(0.7))
                    .rotationEffect(.degrees(-90))
                    .frame(width: diameter + 20, height: diameter + 20)
                    .animation(.linear(duration: 1), value: seconds)
                    .opacity(data.postureState.isBad ? (isCountdownFlashing ? 0.3 : 1.0) : 1.0)
                    .animation(
                        data.postureState.isBad
                            ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                            : .default,
                        value: isCountdownFlashing
                    )
                    .onChange(of: data.postureState.isBad) { _, isBad in
                        isCountdownFlashing = isBad
                    }
                    .onAppear {
                        if data.postureState.isBad { isCountdownFlashing = true }
                    }
            }

            // Outer ring — overall score
            ringArc(
                progress: score,
                lineWidth: 16,
                diameter: diameter,
                color: outerRingColor(score: score)
            )

            // Unfilled gap glow in alert mode
            if data.isAlertMode {
                Circle()
                    .trim(from: score, to: 1.0)
                    .stroke(style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .foregroundStyle(outerRingColor(score: score).opacity(isPulsing ? 0.3 : 0.1))
                    .rotationEffect(.degrees(-90))
                    .frame(width: diameter, height: diameter)
                    .onAppear { isPulsing = true }
                    .onDisappear { isPulsing = false }
                    .animation(PostureAnimations.nudgePulse, value: isPulsing)
            }

            // Middle ring — worst metric inverted
            ringArc(
                progress: worstInverted,
                lineWidth: 12,
                diameter: diameter - 40,
                color: .cyan
            )

            // Inner ring — streak timer
            ringArc(
                progress: streakFraction,
                lineWidth: 8,
                diameter: diameter - 72,
                color: .orange
            )

            // Center score + worst offender label
            VStack(spacing: 4) {
                scoreLabel

                if data.isAlertMode, let worst = data.worstOffender {
                    Text(worst.key.displayName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(PostureVisualStyle.stateColor(for: data.postureState))
                        .transition(.opacity)
                }
            }
        }
        .modifier(VibrationModifier(isActive: data.postureState.isBad))
    }

    private func ringArc(progress: CGFloat, lineWidth: CGFloat, diameter: CGFloat, color: Color) -> some View {
        ZStack {
            // Track
            Circle()
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .foregroundStyle(.quaternary)
                .frame(width: diameter, height: diameter)

            // Fill
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .foregroundStyle(color)
                .rotationEffect(.degrees(-90))
                .frame(width: diameter, height: diameter)
                .animation(.easeInOut(duration: 0.8), value: progress)
        }
    }

    // MARK: - Score Label

    private var scoreLabel: some View {
        let score = observer.data.aggregateScore
        return Text("\(Int(score * 100))")
            .font(.system(size: 56, weight: .heavy, design: .rounded))
            .foregroundStyle(
                observer.data.isAlertMode
                    ? PostureVisualStyle.stateColor(for: observer.data.postureState)
                    : .primary
            )
            .contentTransition(.numericText())
            .animation(.snappy, value: Int(score * 100))
    }

    // MARK: - Metric Badges Row

    private var metricBadgesRow: some View {
        HStack(spacing: 16) {
            ForEach(observer.data.metrics, id: \.key) { metric in
                metricBadge(metric: metric)
            }
        }
    }

    private func metricBadge(metric: MetricInfo) -> some View {
        let isWorst = metric.isWorstOffender && observer.data.isAlertMode
        return VStack(spacing: 4) {
            miniRing(
                ratio: metric.clampedRatio,
                color: PostureVisualStyle.metricColor(ratio: metric.ratio),
                size: 28
            )
            .scaleEffect(isWorst ? 1.15 : 1.0)
            .animation(isWorst ? PostureAnimations.nudgePulse : .default, value: isWorst)

            Text(abbreviation(for: metric.key))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .opacity(observer.data.isAlertMode && !metric.isWorstOffender ? 0.4 : 1.0)
        .animation(PostureAnimations.modeTransition, value: observer.data.isAlertMode)
    }

    private func miniRing(ratio: Float, color: Color, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .foregroundStyle(.quaternary)

            Circle()
                .trim(from: 0, to: CGFloat(max(0.001, ratio)))
                .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .foregroundStyle(color)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    // MARK: - Helpers

    private func outerRingColor(score: CGFloat) -> Color {
        let red = Color(hue: 0.02, saturation: 0.8, brightness: 0.75)
        if observer.data.postureState.isBad {
            return red
        }
        if score > 0.7 {
            return Color(hue: 0.38, saturation: 0.6, brightness: 0.7) // green
        } else if score > 0.4 {
            return Color(hue: 0.12, saturation: 0.7, brightness: 0.8) // yellow
        } else {
            return red
        }
    }

    private var streakProgress: CGFloat {
        guard case .good = observer.data.postureState else { return 0 }
        let time = observer.data.timeInCurrentState ?? 0
        let goalSeconds: Double = 30 * 60 // 30 min streak goal
        return CGFloat(min(time / goalSeconds, 1.0))
    }

    private func abbreviation(for key: MetricKey) -> String {
        switch key {
        case .forwardCreep:     return "FC"
        case .headDrop:         return "HD"
        case .shoulderRounding: return "SR"
        case .lateralLean:      return "LL"
        case .twist:            return "TW"
        }
    }
}

// MARK: - Vibration Modifier

private struct VibrationModifier: ViewModifier {
    let isActive: Bool
    @State private var isVibrating = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isVibrating && isActive ? 2 : 0))
            .animation(
                isActive
                    ? .linear(duration: 0.08).repeatForever(autoreverses: true)
                    : .default,
                value: isVibrating
            )
            .onChange(of: isActive) { _, newValue in
                isVibrating = newValue
            }
            .onAppear {
                if isActive { isVibrating = true }
            }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant2View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant2View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant2View()
        .environmentObject(observer)
}
