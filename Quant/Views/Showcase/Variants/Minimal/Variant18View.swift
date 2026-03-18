import SwiftUI
import PostureLogic

/// Variant 18: Emoji Mood — A single large emoji expresses posture state.
/// Score ranges map to emoji faces from happy to distressed, with playful
/// flip transitions and bobbing animation.
struct Variant18View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var bobbingOffset: CGFloat = 0
    @State private var fireFlashCount = 0

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

    private var score: Float { observer.data.aggregateScore }

    private var currentEmoji: String {
        if isAbsent { return "😴" }
        switch score {
        case 0.9...Float.infinity: return "😄"
        case 0.7..<0.9:           return "🙂"
        case 0.5..<0.7:           return "😐"
        case 0.3..<0.5:           return "😟"
        case 0.1..<0.3:           return "😬"
        default:                   return "😵"
        }
    }

    private var stateText: String {
        if isAbsent { return "Waiting for Pose..." }
        switch observer.data.postureState {
        case .good: return "Feeling Good"
        case .drifting:
            if let worst = observer.data.worstOffender {
                return conversationalLabel(for: worst.key)
            }
            return "Getting Uncomfortable"
        case .bad:
            if let worst = observer.data.worstOffender {
                return "Sit up! \(worst.key.displayName)"
            }
            return "Ouch"
        default: return ""
        }
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                if observer.data.postureState.isBad && !isAbsent {
                    Color.red.opacity(0.02).ignoresSafeArea()
                }

                if isAbsent {
                    AbsenceOverlay {
                        if isLandscape {
                            landscapeLayout
                        } else {
                            portraitLayout
                        }
                    }
                } else {
                    if isLandscape {
                        landscapeLayout
                    } else {
                        portraitLayout
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
        .onAppear { startBobbing() }
        .onChange(of: observer.data.postureState) { _, _ in startBobbing() }
        .onChange(of: isFire) { _, newValue in
            if newValue { triggerFireFlash() }
        }
    }

    // MARK: - Portrait

    private var portraitLayout: some View {
        VStack(spacing: 16) {
            Spacer()

            emojiView
            stateLabel
            metricCapsules
            countdownLabel

            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Landscape

    private var landscapeLayout: some View {
        HStack(spacing: 0) {
            // Left 40%: emoji
            VStack {
                Spacer()
                emojiView
                Spacer()
            }
            .frame(maxWidth: .infinity)

            // Right 55%: details
            VStack(alignment: .leading, spacing: 12) {
                Spacer()
                stateLabel
                ForEach(observer.data.metrics, id: \.key) { metric in
                    metricRow(metric: metric)
                }
                countdownLabel
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.trailing)
        }
    }

    // MARK: - Components

    private var emojiView: some View {
        Text(currentEmoji)
            .font(.system(size: 120))
            .id(currentEmoji)
            .transition(.asymmetric(
                insertion: .scale(scale: 1.0).combined(with: .opacity),
                removal: .scale(scale: 0.0).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.3), value: currentEmoji)
            .offset(y: bobbingOffset)
            .modifier(ShakeModifier(isShaking: observer.data.postureState.isBad && !isAbsent))
    }

    private var stateLabel: some View {
        Text(stateText)
            .font(.title3)
            .foregroundStyle(
                observer.data.postureState.isBad
                    ? .red
                    : .primary
            )
            .contentTransition(.interpolate)
            .animation(.easeInOut(duration: 0.5), value: stateText)
    }

    private var metricCapsules: some View {
        HStack(spacing: 6) {
            ForEach(observer.data.metrics, id: \.key) { metric in
                let isWorst = metric.isWorstOffender && observer.data.isAlertMode

                HStack(spacing: 4) {
                    Text(abbreviation(for: metric.key))
                        .font(.caption2)
                    Text(String(format: "%.1f", metric.ratio))
                        .font(.caption2.monospacedDigit())
                }
                .padding(.horizontal, isWorst ? 10 : 8)
                .padding(.vertical, 4)
                .background(
                    PostureVisualStyle.metricColor(ratio: metric.ratio).opacity(0.2),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(PostureVisualStyle.metricColor(ratio: metric.ratio))
                .scaleEffect(isWorst ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: isWorst)
            }
        }
    }

    @ViewBuilder
    private var countdownLabel: some View {
        if observer.data.isAlertMode, let seconds = observer.data.nudgeCountdownSeconds {
            Text("Nudge in \(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }

    private func metricRow(metric: MetricInfo) -> some View {
        HStack(spacing: 8) {
            Text(metric.key.displayName)
                .font(.subheadline)
                .frame(width: 120, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(PostureVisualStyle.metricColor(ratio: metric.ratio))
                        .frame(width: geo.size.width * CGFloat(metric.clampedRatio))
                }
            }
            .frame(height: 4)

            Text(String(format: "%.0f%%", metric.clampedRatio * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func abbreviation(for key: MetricKey) -> String {
        switch key {
        case .forwardCreep: return "FC"
        case .headDrop: return "HD"
        case .shoulderRounding: return "SR"
        case .lateralLean: return "LL"
        case .twist: return "TW"
        }
    }

    private func conversationalLabel(for key: MetricKey) -> String {
        switch key {
        case .forwardCreep: return "Leaning Forward"
        case .headDrop: return "Your Head is Dropping"
        case .shoulderRounding: return "Shoulders Rounding"
        case .lateralLean: return "Leaning to One Side"
        case .twist: return "Twisting Your Torso"
        }
    }

    private func startBobbing() {
        bobbingOffset = 0
        if observer.data.postureState == .good {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                bobbingOffset = -5
            }
        } else if observer.data.isAlertMode {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                bobbingOffset = 3
            }
        }
    }

    private func triggerFireFlash() {
        Task { @MainActor in
            for _ in 0..<3 {
                fireFlashCount += 1
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }
}

// MARK: - Shake Modifier

private struct ShakeModifier: ViewModifier {
    let isShaking: Bool

    func body(content: Content) -> some View {
        if isShaking {
            TimelineView(.animation(minimumInterval: 0.1)) { _ in
                content
                    .offset(x: CGFloat.random(in: -5...5), y: 0)
            }
        } else {
            content
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant18View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant18View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant18View()
        .environmentObject(observer)
}
