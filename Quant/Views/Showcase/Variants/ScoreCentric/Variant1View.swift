import SwiftUI
import PostureLogic

struct Variant1View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var isBezelPulsing = false
    @State private var worstShakeOffset: CGFloat = 0

    private let gaugeStartAngle: Double = 150
    private let gaugeSweep: Double = 240

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
        VStack(spacing: 16) {
            Spacer()

            gaugeView(diameter: min(size.width * 0.9, size.height * 0.55))

            capsuleMetricsRow

            if observer.data.isAlertMode {
                NudgeCountdownLabel(
                    seconds: observer.data.nudgeCountdownSeconds,
                    style: .verbose
                )
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Landscape Layout

    private func landscapeLayout(size: CGSize) -> some View {
        HStack(spacing: 24) {
            gaugeView(diameter: min(size.width * 0.45, size.height * 0.8))
                .frame(maxWidth: size.width * 0.55)

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
            .frame(maxWidth: size.width * 0.4)
        }
        .padding()
    }

    private func landscapeMetricRow(metric: MetricInfo) -> some View {
        let isWorst = metric.isWorstOffender && observer.data.isAlertMode
        return HStack(spacing: 10) {
            Text(metric.key.displayName)
                .font(.subheadline)
                .foregroundStyle(isWorst ? .primary : .secondary)

            Spacer()

            capsuleFill(ratio: metric.clampedRatio)
                .frame(width: 80, height: 10)

            Text(String(format: "%.0f%%", metric.clampedRatio * 100))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(isWorst ? .primary : .secondary)
        }
        .opacity(observer.data.isAlertMode && !metric.isWorstOffender ? 0.5 : 1.0)
    }

    // MARK: - Gauge View

    private func gaugeView(diameter: CGFloat) -> some View {
        let data = observer.data
        let score = Double(data.aggregateScore)
        let needleAngleDeg = (1.0 - score) * gaugeSweep - gaugeSweep / 2
        let arcRadius = diameter * 0.4
        let frameHeight = diameter * 0.75
        let pivotFromCenter = frameHeight * 0.2
        let needleHeight = arcRadius * 0.85

        return ZStack {
            // Colored arc + tick marks
            Canvas { context, size in
                let pivot = CGPoint(x: size.width / 2, y: size.height / 2 + pivotFromCenter)

                // Arc segments (60 segments for smooth gradient)
                let segmentCount = 60
                for i in 0..<segmentCount {
                    let fraction = Double(i) / Double(segmentCount)
                    let startDeg = gaugeStartAngle + fraction * gaugeSweep
                    let endDeg = gaugeStartAngle + Double(i + 1) / Double(segmentCount) * gaugeSweep + 0.5

                    var segPath = Path()
                    segPath.addArc(
                        center: pivot, radius: arcRadius,
                        startAngle: .degrees(startDeg),
                        endAngle: .degrees(endDeg),
                        clockwise: false
                    )
                    context.stroke(segPath, with: .color(zoneColor(fraction: fraction)), lineWidth: 14)
                }

                // Tick marks
                let tickCount = 24
                for i in 0...tickCount {
                    let fraction = Double(i) / Double(tickCount)
                    let angleDeg = gaugeStartAngle + fraction * gaugeSweep
                    let angleRad = angleDeg * .pi / 180
                    let isMajor = i % 6 == 0
                    let innerR = arcRadius - (isMajor ? 18 : 10)
                    let outerR = arcRadius + (isMajor ? 8 : 4)

                    var tick = Path()
                    tick.move(to: CGPoint(
                        x: pivot.x + innerR * cos(angleRad),
                        y: pivot.y + innerR * sin(angleRad)
                    ))
                    tick.addLine(to: CGPoint(
                        x: pivot.x + outerR * cos(angleRad),
                        y: pivot.y + outerR * sin(angleRad)
                    ))
                    context.stroke(
                        tick,
                        with: .color(.white.opacity(isMajor ? 0.8 : 0.4)),
                        lineWidth: isMajor ? 2 : 1
                    )
                }
            }

            // Bezel glow in alert mode
            if data.isAlertMode {
                GaugeArcShape(startAngle: gaugeStartAngle, sweepAngle: gaugeSweep)
                    .stroke(
                        PostureVisualStyle.stateColor(for: data.postureState),
                        lineWidth: 22
                    )
                    .blur(radius: 14)
                    .opacity(isBezelPulsing ? 0.7 : 0.3)
                    .frame(width: arcRadius * 2, height: arcRadius * 2)
                    .offset(y: pivotFromCenter)
                    .transition(.opacity)
            }

            // Score + countdown at center of arc
            VStack(spacing: 2) {
                scoreLabel

                if data.isAlertMode, let seconds = data.nudgeCountdownSeconds {
                    Text("Nudge in \(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))")
                        .font(.subheadline)
                        .foregroundStyle(PostureVisualStyle.stateColor(for: data.postureState))
                        .monospacedDigit()
                        .transition(.opacity)
                }
            }
            .offset(y: pivotFromCenter - arcRadius * 0.5)

            // Needle
            NeedleShape()
                .fill(
                    LinearGradient(
                        colors: [.white, Color(white: 0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 6, height: needleHeight)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .rotationEffect(.degrees(needleAngleDeg), anchor: .bottom)
                .offset(y: pivotFromCenter - needleHeight / 2)
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: score)

            // Pivot dot
            Circle()
                .fill(Color(white: 0.3))
                .frame(width: 14, height: 14)
                .shadow(color: .black.opacity(0.2), radius: 2)
                .offset(y: pivotFromCenter)
        }
        .frame(width: diameter, height: frameHeight)
        .onAppear {
            if observer.data.isAlertMode { isBezelPulsing = true }
        }
        .onChange(of: observer.data.isAlertMode) { _, isAlert in
            isBezelPulsing = isAlert
        }
        .animation(
            observer.data.isAlertMode
                ? .easeInOut(duration: observer.data.postureState.isBad ? 0.8 : 1.2)
                    .repeatForever(autoreverses: true)
                : .default,
            value: isBezelPulsing
        )
    }

    // MARK: - Score Label

    private var scoreLabel: some View {
        let score = observer.data.aggregateScore
        return Text("\(Int(score * 100))")
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .foregroundStyle(
                observer.data.isAlertMode
                    ? PostureVisualStyle.stateColor(for: observer.data.postureState)
                    : .primary
            )
            .contentTransition(.numericText())
            .animation(.snappy, value: Int(score * 100))
    }

    // MARK: - Capsule Metrics

    private var capsuleMetricsRow: some View {
        HStack(spacing: 12) {
            ForEach(observer.data.metrics, id: \.key) { metric in
                capsuleIndicator(metric: metric)
            }
        }
    }

    private func capsuleIndicator(metric: MetricInfo) -> some View {
        let data = observer.data
        let isWorst = metric.isWorstOffender && data.isAlertMode
        let isBadShake = data.postureState.isBad && isWorst

        return VStack(spacing: 4) {
            capsuleFill(ratio: metric.clampedRatio)
                .frame(width: 44, height: 6)
                .scaleEffect(isWorst ? 1.3 : 1.0)
                .overlay(
                    Group {
                        if isWorst {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(
                                    PostureVisualStyle.stateColor(for: data.postureState),
                                    lineWidth: 1
                                )
                                .scaleEffect(1.3)
                                .opacity(isBezelPulsing ? 1 : 0.4)
                        }
                    }
                )
                .offset(x: isBadShake ? worstShakeOffset : 0)

            Text(abbreviation(for: metric.key))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .opacity(data.isAlertMode && !metric.isWorstOffender ? 0.3 : 1.0)
        .animation(PostureAnimations.modeTransition, value: data.isAlertMode)
        .onChange(of: isBadShake) { _, shouldShake in
            if shouldShake { startShake() } else { worstShakeOffset = 0 }
        }
        .onAppear {
            if isBadShake { startShake() }
        }
    }

    private func capsuleFill(ratio: Float) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: geo.size.height / 2)
                    .fill(.quaternary)

                RoundedRectangle(cornerRadius: geo.size.height / 2)
                    .fill(PostureVisualStyle.metricColor(ratio: ratio))
                    .frame(width: max(geo.size.height, geo.size.width * CGFloat(min(ratio, 1.0))))
            }
        }
    }

    // MARK: - Helpers

    private func zoneColor(fraction: Double) -> Color {
        // fraction 0.0 = green (left/good), 1.0 = red (right/bad)
        if fraction < 0.4 {
            let t = fraction / 0.4
            return Color(
                hue: 0.38 - t * 0.26,
                saturation: 0.6 + t * 0.1,
                brightness: 0.7 + t * 0.1
            )
        } else {
            let t = (fraction - 0.4) / 0.6
            return Color(
                hue: 0.12 - t * 0.1,
                saturation: 0.7 + t * 0.2,
                brightness: 0.8 - t * 0.05
            )
        }
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

    private func startShake() {
        withAnimation(.linear(duration: 0.06).repeatForever(autoreverses: true)) {
            worstShakeOffset = 3
        }
    }
}

// MARK: - Needle Shape

private struct NeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tipWidth: CGFloat = 2
        let baseWidth = rect.width

        path.move(to: CGPoint(x: rect.midX - tipWidth / 2, y: 0))
        path.addLine(to: CGPoint(x: rect.midX + tipWidth / 2, y: 0))
        path.addLine(to: CGPoint(x: rect.midX + baseWidth / 2, y: rect.height))
        path.addLine(to: CGPoint(x: rect.midX - baseWidth / 2, y: rect.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Gauge Arc Shape

private struct GaugeArcShape: Shape {
    let startAngle: Double
    let sweepAngle: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(startAngle + sweepAngle),
            clockwise: false
        )
        return path
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant1View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant1View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant1View()
        .environmentObject(observer)
}
