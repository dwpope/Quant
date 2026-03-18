import SwiftUI
import PostureLogic

/// Variant 14: Breathing Dot — A single pulsing circle encodes posture state
/// through breathing rhythm, color, and wobble intensity.
struct Variant14View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var breathScale: CGFloat = 1.0
    @State private var outerRingScale: CGFloat = 1.08

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private var breathDuration: Double {
        switch observer.data.postureState {
        case .good: return 4.0
        case .drifting: return 2.5
        case .bad: return 1.5
        default: return 4.0
        }
    }

    private var dotColor: Color {
        switch observer.data.postureState {
        case .good: return .green
        case .drifting: return .yellow
        case .bad: return .red
        default: return .gray
        }
    }

    private var baseDiameter: CGFloat { 120 }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        dotContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    dotContent(size: geo.size, isLandscape: isLandscape)
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

    private func dotContent(size: CGSize, isLandscape: Bool) -> some View {
        let orbitalRadius: CGFloat = isLandscape ? 130 : 100

        return ZStack {
            breathingDotView

            satelliteDots(orbitalRadius: orbitalRadius)

            countdownLabel
        }
    }

    private var breathingDotView: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { _ in
            let wobbleActive = observer.data.isAlertMode && !isAbsent
            let wobbleAmount: CGFloat = observer.data.postureState.isBad ? 15 : 8
            let wx: CGFloat = wobbleActive ? .random(in: -wobbleAmount...wobbleAmount) : 0
            let wy: CGFloat = wobbleActive ? .random(in: -wobbleAmount...wobbleAmount) : 0
            let xScale: CGFloat = observer.data.postureState.isBad ? 1.1 : 1.0
            let yScale: CGFloat = observer.data.postureState.isBad ? 0.9 : 1.0

            ZStack {
                outerRing
                mainDot(xScale: xScale, yScale: yScale)
            }
            .offset(x: wx, y: wy)
        }
    }

    private var outerRing: some View {
        Circle()
            .stroke(dotColor.opacity(0.1), lineWidth: 1)
            .frame(width: baseDiameter * outerRingScale,
                   height: baseDiameter * outerRingScale)
    }

    private func mainDot(xScale: CGFloat, yScale: CGFloat) -> some View {
        let gradient = RadialGradient(
            colors: [dotColor.opacity(0.9), dotColor.opacity(0.3)],
            center: .center,
            startRadius: 0,
            endRadius: baseDiameter / 2
        )
        return Circle()
            .fill(gradient)
            .frame(width: baseDiameter, height: baseDiameter)
            .scaleEffect(x: breathScale * xScale, y: breathScale * yScale)
    }

    @ViewBuilder
    private func satelliteDots(orbitalRadius: CGFloat) -> some View {
        if !isAbsent {
            ForEach(Array(observer.data.metrics.enumerated()), id: \.element.key) { index, metric in
                satelliteDot(index: index, metric: metric, orbitalRadius: orbitalRadius)
            }
        }
    }

    private func satelliteDot(index: Int, metric: MetricInfo, orbitalRadius: CGFloat) -> some View {
        let angle = -(.pi / 2) + Double(index) * (2 * .pi / 5)
        let x = orbitalRadius * cos(angle)
        let y = orbitalRadius * sin(angle)
        let isWorst = metric.isWorstOffender && observer.data.isAlertMode
        let dotSize: CGFloat = isWorst ? 12 : 6

        return Circle()
            .fill(PostureVisualStyle.metricColor(ratio: metric.ratio))
            .frame(width: dotSize, height: dotSize)
            .opacity(Double(max(0.15, metric.clampedRatio)))
            .offset(x: x, y: y)
            .animation(.easeInOut(duration: 0.3), value: isWorst)
    }

    @ViewBuilder
    private var countdownLabel: some View {
        if observer.data.isAlertMode, let seconds = observer.data.nudgeCountdownSeconds {
            Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary.opacity(0.4))
                .offset(y: baseDiameter * 0.6)
                .transition(.opacity)
        }
    }

    private func startBreathing() {
        breathScale = 1.0
        outerRingScale = 1.08

        withAnimation(.easeInOut(duration: breathDuration).repeatForever(autoreverses: true)) {
            breathScale = 1.25
        }
        withAnimation(.easeInOut(duration: breathDuration).repeatForever(autoreverses: true).delay(breathDuration / 2)) {
            outerRingScale = 1.0
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant14View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .shoulderRounding,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant14View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant14View()
        .environmentObject(observer)
}
