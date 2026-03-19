import SwiftUI
import PostureLogic

struct Variant7View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var flamePhase: TimeInterval = 0
    @State private var isActive = false

    private var data: PostureDisplayData { observer.data }

    private var isAbsent: Bool {
        switch data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        equalizerContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    equalizerContent(size: geo.size, isLandscape: isLandscape)
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
        .onAppear { isActive = true }
        .onDisappear { isActive = false }
        .sensoryFeedback(.impact, trigger: data.postureState.isBad)
        .animation(PostureAnimations.alertOnset, value: data.isAlertMode)
    }

    // MARK: - Equalizer Content

    private func equalizerContent(size: CGSize, isLandscape: Bool) -> some View {
        let barWidth: CGFloat = isLandscape ? 80 : 50
        let maxBarHeight = size.height * 0.75
        let minBarHeight: CGFloat = 20
        let spacing: CGFloat = isLandscape ? 24 : 12

        return VStack(spacing: 0) {
            // Countdown strip at top
            if data.isAlertMode, let seconds = data.nudgeCountdownSeconds {
                countdownStrip(seconds: seconds, width: size.width)
            }

            Spacer()

            // Threshold line + bars
            ZStack(alignment: .bottom) {
                // Threshold dashed line at ratio 1.0 height
                let thresholdY = maxBarHeight * 0.75
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Threshold")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(.secondary.opacity(0.4))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 20)
                    .offset(y: -thresholdY)
                }

                // Bars
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(data.metrics, id: \.key) { metric in
                        barColumn(
                            metric: metric,
                            barWidth: barWidth,
                            maxBarHeight: maxBarHeight,
                            minBarHeight: minBarHeight,
                            isLandscape: isLandscape
                        )
                    }
                }
                .padding(.horizontal)

                // Flame + shatter canvas overlay
                if data.isAlertMode {
                    TimelineView(.animation(paused: !isActive || isAbsent)) { timeline in
                        Canvas { context, canvasSize in
                            drawFlameAndShatter(
                                context: &context,
                                size: canvasSize,
                                date: timeline.date,
                                maxBarHeight: maxBarHeight,
                                minBarHeight: minBarHeight,
                                barWidth: barWidth,
                                spacing: spacing,
                                barCount: data.metrics.count
                            )
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    // MARK: - Bar Column

    private func barColumn(
        metric: MetricInfo,
        barWidth: CGFloat,
        maxBarHeight: CGFloat,
        minBarHeight: CGFloat,
        isLandscape: Bool
    ) -> some View {
        let isWorst = metric.isWorstOffender && data.isAlertMode
        let barHeight = minBarHeight + CGFloat(metric.clampedRatio) * (maxBarHeight * 0.75 - minBarHeight)

        return VStack(spacing: 4) {
            // Floating ratio label
            Text(String(format: "%.0f%%", metric.clampedRatio * 100))
                .font(isWorst ? .body.monospacedDigit() : .caption2.monospacedDigit())
                .foregroundStyle(isWorst ? .primary : .secondary)
                .animation(.default, value: isWorst)

            // The bar
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [.green, .yellow, .red],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: barWidth, height: barHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .saturation(data.isAlertMode && !isWorst ? 0.3 : 1.0)
                .shadow(
                    color: isWorst ? PostureVisualStyle.stateColor(for: data.postureState).opacity(0.6) : .clear,
                    radius: isWorst ? 12 : 0
                )
                .animation(PostureAnimations.metricUpdate, value: metric.clampedRatio)

            // Metric label
            Text(isLandscape ? metric.key.displayName : abbreviation(for: metric.key))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Countdown Strip

    private func countdownStrip(seconds: TimeInterval, width: CGFloat) -> some View {
        let maxSeconds: CGFloat = 30
        let progress = CGFloat(max(0, min(seconds, Double(maxSeconds)))) / maxSeconds
        let color: Color = data.postureState.isBad ? .red : .yellow

        return Rectangle()
            .fill(color)
            .frame(width: width * progress, height: 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.linear(duration: 1), value: progress)
    }

    // MARK: - Flame & Shatter Canvas

    private func drawFlameAndShatter(
        context: inout GraphicsContext,
        size: CGSize,
        date: Date,
        maxBarHeight: CGFloat,
        minBarHeight: CGFloat,
        barWidth: CGFloat,
        spacing: CGFloat,
        barCount: Int
    ) {
        guard let worst = data.worstOffender else { return }
        let worstIndex = data.metrics.firstIndex(where: { $0.key == worst.key }) ?? 0

        let totalBarsWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        let startX = (size.width - totalBarsWidth) / 2
        let barCenterX = startX + CGFloat(worstIndex) * (barWidth + spacing) + barWidth / 2
        let barHeight = minBarHeight + CGFloat(worst.clampedRatio) * (maxBarHeight * 0.75 - minBarHeight)
        let barTopY = size.height - barHeight - 30 // approximate bottom padding

        let time = date.timeIntervalSinceReferenceDate

        // Flame particles above worst bar
        for i in 0..<10 {
            let seed = Double(i) * 137.5
            let phase = (time * 1.5 + seed).truncatingRemainder(dividingBy: 2.0)
            let normalizedPhase = phase / 2.0
            let particleX = barCenterX + CGFloat(sin(seed + time * 2)) * barWidth * 0.3
            let particleY = barTopY - CGFloat(normalizedPhase) * 40
            let opacity = max(0, 1.0 - normalizedPhase)
            let radius: CGFloat = 4 + CGFloat(1.0 - normalizedPhase) * 4

            let rect = CGRect(x: particleX - radius, y: particleY - radius, width: radius * 2, height: radius * 2)
            let particleColor = Color.orange.opacity(opacity * 0.7)
            var blurred = context
            blurred.addFilter(.blur(radius: 3))
            blurred.fill(Path(ellipseIn: rect), with: .color(particleColor))
        }

        // Shatter effect at threshold line (only in bad state)
        if data.postureState.isBad {
            let thresholdY = size.height - maxBarHeight * 0.75 - 30
            let shatterCount = 7
            for i in 0..<shatterCount {
                let angle = Double(i) / Double(shatterCount) * .pi * 2
                let length: CGFloat = 12 + CGFloat(Darwin.sin(time * 3 + Double(i))) * 4
                var line = Path()
                line.move(to: CGPoint(x: barCenterX, y: thresholdY))
                line.addLine(to: CGPoint(
                    x: barCenterX + CGFloat(Darwin.cos(angle)) * length,
                    y: thresholdY + CGFloat(Darwin.sin(angle)) * length
                ))
                context.stroke(line, with: .color(.white.opacity(0.7)), lineWidth: 1.5)
            }
        }
    }

    // MARK: - Helpers

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

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant7View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant7View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant7View()
        .environmentObject(observer)
}
