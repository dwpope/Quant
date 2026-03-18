import SwiftUI
import PostureLogic

/// Variant 13: Single Word — A massive typographic word fills the screen,
/// changing between "GOOD", "DRIFTING", and "BAD" with semantic animations.
struct Variant13View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var tremorOffset: CGSize = .zero

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private var isFire: Bool {
        if case .fire = observer.data.nudgeDecision { return true }
        return false
    }

    private var stateWord: String {
        switch observer.data.postureState {
        case .good: return "GOOD"
        case .drifting: return "DRIFTING"
        case .bad: return isFire ? worstOffenderName : "BAD"
        case .absent: return "WAITING"
        case .calibrating: return "CALIBRATING"
        }
    }

    private var worstOffenderName: String {
        observer.data.worstOffender?.key.displayName.uppercased() ?? "BAD"
    }

    private var fontWeight: Font.Weight {
        switch observer.data.postureState {
        case .good: return .ultraLight
        case .drifting: return .light
        case .bad: return .bold
        default: return .ultraLight
        }
    }

    private var tracking: CGFloat {
        switch observer.data.postureState {
        case .good: return 20
        case .drifting: return 10
        case .bad: return -3
        default: return 20
        }
    }

    private var wordColor: Color {
        switch observer.data.postureState {
        case .good: return PostureVisualStyle.stateColor(for: .good)
        case .drifting: return Color(hue: 0.12, saturation: 0.7, brightness: 0.85)
        case .bad: return Color(hue: 0.02, saturation: 0.9, brightness: 0.8)
        default: return .secondary
        }
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                if observer.data.postureState.isBad {
                    Color.red.opacity(0.03).ignoresSafeArea()
                }

                if isAbsent {
                    AbsenceOverlay {
                        mainContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    mainContent(size: geo.size, isLandscape: isLandscape)
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

    private func mainContent(size: CGSize, isLandscape: Bool) -> some View {
        VStack(spacing: 16) {
            Spacer()

            // Main word
            TimelineView(.animation(minimumInterval: 0.1)) { timeline in
                let tremorActive = observer.data.postureState.isBad && !isAbsent
                let offset = tremorActive
                    ? CGSize(width: CGFloat.random(in: -2...2), height: CGFloat.random(in: -2...2))
                    : .zero

                Text(stateWord)
                    .font(.system(size: dynamicFontSize(for: size), weight: fontWeight, design: .rounded))
                    .tracking(tracking)
                    .foregroundStyle(wordColor)
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .offset(offset)
                    .contentTransition(.interpolate)
                    .animation(.easeInOut(duration: 0.8), value: stateWord)
                    .animation(.easeInOut(duration: 0.8), value: tracking)
                    .modifier(DriftModifier(isDrifting: observer.data.postureState.isDrifting && !isAbsent))
            }

            // Metric dots
            if !isAbsent {
                metricDots
            }

            // Countdown
            if observer.data.isAlertMode, let seconds = observer.data.nudgeCountdownSeconds {
                Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    private func dynamicFontSize(for size: CGSize) -> CGFloat {
        let wordLength = CGFloat(stateWord.count)
        let maxWidth = size.width * 0.85
        // Rough estimate: each character at weight ultraLight is ~0.55 of font size
        let charWidthFactor: CGFloat = 0.55
        let estimated = maxWidth / (wordLength * charWidthFactor)
        return min(estimated, size.height * 0.35)
    }

    private var metricDots: some View {
        HStack(spacing: 12) {
            ForEach(observer.data.metrics, id: \.key) { metric in
                VStack(spacing: 4) {
                    Circle()
                        .fill(PostureVisualStyle.metricColor(ratio: metric.ratio))
                        .frame(width: metric.isWorstOffender && observer.data.isAlertMode ? 12 : 8,
                               height: metric.isWorstOffender && observer.data.isAlertMode ? 12 : 8)

                    if metric.isWorstOffender && observer.data.isAlertMode {
                        Text(metric.key.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: metric.isWorstOffender)
            }
        }
    }
}

// MARK: - Drift Animation Modifier

private struct DriftModifier: ViewModifier {
    let isDrifting: Bool
    @State private var driftOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: isDrifting ? driftOffset : 0)
            .onAppear {
                if isDrifting { startDrift() }
            }
            .onChange(of: isDrifting) { _, newValue in
                if newValue { startDrift() }
            }
    }

    private func startDrift() {
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
            driftOffset = 5
        }
    }
}

// MARK: - PostureState convenience

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
    Variant13View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant13View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant13View()
        .environmentObject(observer)
}
