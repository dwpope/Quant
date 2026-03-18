import SwiftUI
import PostureLogic

struct Variant8View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var badRotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0

    private var data: PostureDisplayData { observer.data }

    private let segmentColors: [Color] = [.teal, .indigo, .orange, .mint, .pink]

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
                        donutContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    donutContent(size: geo.size, isLandscape: isLandscape)
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
        .onChange(of: data.postureState.isBad) { _, isBad in
            if isBad {
                withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                    badRotation = 360
                }
            } else {
                badRotation = 0
            }
        }
    }

    // MARK: - Donut Content

    private func donutContent(size: CGSize, isLandscape: Bool) -> some View {
        Group {
            if isLandscape {
                landscapeLayout(size: size)
            } else {
                portraitLayout(size: size)
            }
        }
    }

    // MARK: - Portrait Layout

    private func portraitLayout(size: CGSize) -> some View {
        let donutDiameter = min(size.width * 0.85, size.height * 0.55)

        return VStack(spacing: 16) {
            Spacer()

            donutView(diameter: donutDiameter)

            // Legend below donut
            legendRows

            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Landscape Layout

    private func landscapeLayout(size: CGSize) -> some View {
        let donutDiameter = min(size.width * 0.4, size.height * 0.8)

        return HStack(spacing: 24) {
            donutView(diameter: donutDiameter)

            VStack(alignment: .leading, spacing: 8) {
                legendRows
            }
            .frame(maxWidth: size.width * 0.4)
        }
        .padding()
    }

    // MARK: - Donut View

    private func donutView(diameter: CGFloat) -> some View {
        let center = CGPoint(x: diameter / 2, y: diameter / 2)
        let baseInnerRadius = diameter * 0.28
        let minRingWidth: CGFloat = 12
        let maxRingWidth: CGFloat = 40

        return ZStack {
            // Donut segments
            ForEach(Array(data.metrics.enumerated()), id: \.element.key) { index, metric in
                let isWorst = metric.isWorstOffender && data.isAlertMode
                let startAngle = Angle(degrees: Double(index) * 72 - 90)
                let endAngle = Angle(degrees: Double(index + 1) * 72 - 90)
                let ringWidth = minRingWidth + CGFloat(metric.clampedRatio) * (maxRingWidth - minRingWidth)
                let outerRadius = baseInnerRadius + ringWidth + (isWorst ? 15 : 0)
                let segmentColor = data.postureState.isBad && isWorst ? Color.red : segmentColors[index]

                DonutSegment(
                    center: center,
                    innerRadius: baseInnerRadius,
                    outerRadius: outerRadius,
                    startAngle: startAngle,
                    endAngle: endAngle
                )
                .fill(segmentColor)
                .opacity(data.isAlertMode && !isWorst ? 0.5 : 1.0)
                .animation(PostureAnimations.metricUpdate, value: metric.clampedRatio)
            }

            // Radial pulse for worst offender in alert mode
            if data.isAlertMode {
                Circle()
                    .stroke(PostureVisualStyle.stateColor(for: data.postureState).opacity(0.3), lineWidth: 2)
                    .frame(width: diameter * 0.8 * pulseScale, height: diameter * 0.8 * pulseScale)
                    .onAppear {
                        withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                            pulseScale = 1.3
                        }
                    }
                    .onDisappear { pulseScale = 1.0 }
            }

            // Center score
            VStack(spacing: 2) {
                if data.isAlertMode, let worst = data.worstOffender {
                    Text(String(format: "%.0f%%", worst.clampedRatio * 100))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .foregroundStyle(PostureVisualStyle.stateColor(for: data.postureState))
                    Text(worst.key.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let seconds = data.nudgeCountdownSeconds {
                        NudgeCountdownLabel(seconds: seconds, style: .compact)
                    }
                } else {
                    Text("\(Int(data.aggregateScore * 100))")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("Posture Score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(badRotation))
    }

    // MARK: - Legend

    private var legendRows: some View {
        ForEach(Array(data.metrics.enumerated()), id: \.element.key) { index, metric in
            let isWorst = metric.isWorstOffender && data.isAlertMode
            HStack(spacing: 8) {
                Circle()
                    .fill(segmentColors[index])
                    .frame(width: 10, height: 10)

                Text(metric.key.displayName)
                    .font(.subheadline)
                    .foregroundStyle(isWorst ? .primary : .secondary)

                Spacer()

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(segmentColors[index])
                            .frame(width: geo.size.width * CGFloat(metric.clampedRatio))
                    }
                }
                .frame(width: 60, height: 6)

                Text(String(format: "%.0f%%", metric.clampedRatio * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .opacity(data.isAlertMode && !isWorst ? 0.5 : 1.0)
        }
    }
}

// MARK: - Donut Segment Shape

private struct DonutSegment: Shape {
    let center: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: center, radius: outerRadius,
                     startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: innerRadius,
                     startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant8View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant8View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant8View()
        .environmentObject(observer)
}
