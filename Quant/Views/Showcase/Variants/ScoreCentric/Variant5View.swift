import SwiftUI
import PostureLogic

struct Variant5View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var displayScore: Int = 100
    @State private var isFireFlashVisible: Bool = true

    private var actualScore: Int {
        Int(observer.data.aggregateScore * 100)
    }

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

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                // Red vignette in bad state
                if observer.data.postureState.isBad {
                    RadialGradient(
                        colors: [.clear, .red],
                        center: .center,
                        startRadius: min(geo.size.width, geo.size.height) * 0.3,
                        endRadius: max(geo.size.width, geo.size.height) * 0.7
                    )
                    .opacity(0.05)
                    .ignoresSafeArea()
                }

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

                // Gear icon top-right in ultraThinMaterial
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
        .sensoryFeedback(.impact, trigger: observer.data.postureState.isBad)
        .animation(PostureAnimations.alertOnset, value: observer.data.isAlertMode)
        .onAppear {
            displayScore = actualScore
            if isFire {
                startFireFlash()
            }
        }
        .task(id: countdownTaskKey) {
            let target = actualScore
            guard observer.data.isAlertMode else {
                displayScore = target
                return
            }
            if displayScore <= target {
                displayScore = target
                return
            }
            while displayScore > target && !Task.isCancelled {
                let interval: Duration = observer.data.postureState.isBad ? .milliseconds(200) : .seconds(1)
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }
                if displayScore > target {
                    withAnimation(.snappy) {
                        displayScore -= 1
                    }
                }
            }
        }
        .onChange(of: actualScore) { _, newValue in
            if !observer.data.isAlertMode {
                withAnimation(.snappy) {
                    displayScore = newValue
                }
            }
        }
        .onChange(of: observer.data.isAlertMode) { _, isAlert in
            if !isAlert {
                withAnimation(.snappy) {
                    displayScore = actualScore
                }
            }
        }
        .onChange(of: isFire) { _, newValue in
            if newValue {
                startFireFlash()
            }
        }
    }

    private var countdownTaskKey: String {
        observer.data.isAlertMode ? "alert-\(actualScore)" : "none"
    }

    // MARK: - Portrait Layout

    private func portraitLayout(size: CGSize) -> some View {
        VStack(spacing: 20) {
            Spacer()

            // Main score with optional countdown number beside it
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                scoreNumber

                if observer.data.isAlertMode, let seconds = observer.data.nudgeCountdownSeconds {
                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(.secondary.opacity(0.3))
                            .frame(width: 1, height: 48)

                        Text("\(Int(seconds))")
                            .font(.system(size: 48, design: .monospaced))
                            .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: Int(seconds))
                    }
                    .padding(.leading, 16)
                }
            }

            stateLabel

            if observer.data.isAlertMode {
                worstOffenderLabel
            }

            metricChips

            Spacer()
        }
    }

    // MARK: - Landscape Layout

    private func landscapeLayout(size: CGSize) -> some View {
        HStack(spacing: 0) {
            // Left 60%: number, state, worst offender, countdown
            VStack(spacing: 12) {
                Spacer()

                scoreNumber

                stateLabel

                if observer.data.isAlertMode {
                    worstOffenderLabel

                    if let seconds = observer.data.nudgeCountdownSeconds {
                        Text("\(Int(seconds))")
                            .font(.system(size: 48, design: .monospaced))
                            .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: Int(seconds))
                    }
                }

                Spacer()
            }
            .frame(width: size.width * 0.6)

            // Right 35%: vertical metric list with full names, progress bars, values
            VStack(alignment: .leading, spacing: 10) {
                ForEach(observer.data.metrics, id: \.key) { metric in
                    landscapeMetricRow(metric: metric)
                }
            }
            .frame(width: size.width * 0.35)
            .padding(.trailing, 8)
        }
    }

    // MARK: - Score Number

    private var scoreNumber: some View {
        let t = CGFloat(displayScore) / 100.0
        let fontSize: CGFloat = 160 + (1 - t) * 20
        let tracking: CGFloat = -2 + t * 10

        return Text("\(displayScore)")
            .font(.system(size: fontSize, weight: scoreWeight, design: .rounded))
            .tracking(tracking)
            .foregroundStyle(scoreColor)
            .contentTransition(.numericText(countsDown: true))
            .animation(.snappy, value: displayScore)
            .opacity(isFireFlashVisible ? 1 : 0)
    }

    private var scoreWeight: Font.Weight {
        if displayScore > 66 { return .bold }
        if displayScore > 33 { return .heavy }
        return .black
    }

    private var scoreColor: Color {
        if observer.data.postureState.isBad {
            return Color(hue: 0.02, saturation: 0.9, brightness: 0.8)
        }
        return Color(hue: Double(displayScore) / 360.0, saturation: 0.8, brightness: 0.9)
    }

    // MARK: - State Label

    private var stateLabel: some View {
        let label: String
        switch observer.data.postureState {
        case .good:
            label = "Posture: Good"
        case .drifting:
            label = "Posture: Drifting"
        case .bad:
            label = "Posture: Poor"
        default:
            label = ""
        }
        return Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Worst Offender Label

    private var worstOffenderLabel: some View {
        Group {
            if let worst = observer.data.worstOffender {
                Text("\(worst.key.displayName) \(String(format: "%.2f", worst.clampedRatio))")
                    .font(.title3)
                    .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Metric Chips (Portrait)

    private var metricChips: some View {
        HStack(spacing: 6) {
            ForEach(observer.data.metrics, id: \.key) { metric in
                HStack(spacing: 4) {
                    Text(chipAbbreviation(for: metric.key))
                        .font(.caption2)
                    Text(String(format: "%.1f", metric.ratio))
                        .font(.caption2.monospacedDigit())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    chipColor(ratio: metric.ratio).opacity(0.2),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(chipColor(ratio: metric.ratio))
            }
        }
    }

    // MARK: - Landscape Metric Row

    private func landscapeMetricRow(metric: MetricInfo) -> some View {
        HStack(spacing: 8) {
            Text(metric.key.displayName)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(width: 100, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.secondary.opacity(0.2))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(chipColor(ratio: metric.ratio))
                        .frame(width: geo.size.width * CGFloat(metric.clampedRatio))
                }
            }
            .frame(height: 4)

            Text(String(format: "%.2f", metric.ratio))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func chipAbbreviation(for key: MetricKey) -> String {
        switch key {
        case .forwardCreep: return "FC"
        case .headDrop: return "HD"
        case .shoulderRounding: return "SR"
        case .lateralLean: return "LL"
        case .twist: return "TW"
        }
    }

    private func chipColor(ratio: Float) -> Color {
        if ratio < 0.5 {
            return Color(hue: 0.38, saturation: 0.6, brightness: 0.7)
        } else if ratio <= 0.8 {
            return Color(hue: 0.12, saturation: 0.7, brightness: 0.8)
        } else {
            return Color(hue: 0.02, saturation: 0.9, brightness: 0.8)
        }
    }

    private func startFireFlash() {
        Task { @MainActor in
            for _ in 0..<3 {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isFireFlashVisible = false
                }
                try? await Task.sleep(for: .milliseconds(200))
                withAnimation(.easeInOut(duration: 0.15)) {
                    isFireFlashVisible = true
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant5View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant5View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant5View()
        .environmentObject(observer)
}
