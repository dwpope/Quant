import SwiftUI
import PostureLogic

struct Variant12View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var displayedState: String = "GOOD"
    @State private var metricDisplayValues: [MetricKey: String] = [:]
    @State private var isFlipping = false

    private var data: PostureDisplayData { observer.data }

    private let flapAmber = Color(hue: 0.12, saturation: 0.8, brightness: 0.85)
    private let flapBackground = Color(white: 0.15)
    private let boardBackground = Color.black.opacity(0.9)

    private var isAbsent: Bool {
        switch data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private var stateText: String {
        switch data.postureState {
        case .good: return "GOOD"
        case .drifting: return "DRIFTING"
        case .bad: return "BAD"
        default: return "----"
        }
    }

    private var flapColor: Color {
        data.postureState.isBad ? .red : flapAmber
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                boardBackground.ignoresSafeArea()

                if isAbsent {
                    AbsenceOverlay {
                        boardContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    boardContent(size: geo.size, isLandscape: isLandscape)
                }

                // Settings as split-flap styled button
                VStack {
                    HStack {
                        Spacer()
                        Button { showingSettings = true } label: {
                            Text("[S]")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(flapAmber.opacity(0.7))
                                .padding(6)
                                .background(flapBackground, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
        }
        .sensoryFeedback(.impact, trigger: data.postureState.isBad)
        .animation(PostureAnimations.alertOnset, value: data.isAlertMode)
        .onChange(of: stateText) { _, newText in
            flipToState(newText)
        }
        .onAppear {
            displayedState = stateText
            updateMetricValues()
        }
        .onChange(of: data.metrics.map(\.clampedRatio)) { _, _ in
            updateMetricValues()
        }
    }

    // MARK: - Board Content

    private func boardContent(size: CGSize, isLandscape: Bool) -> some View {
        VStack(spacing: 0) {
            // State row
            stateRow(width: size.width, isLandscape: isLandscape)

            // Separator rib
            Rectangle()
                .fill(Color(white: 0.25))
                .frame(height: 2)

            // Countdown row (only in alert mode)
            if data.isAlertMode, let seconds = data.nudgeCountdownSeconds {
                countdownRow(seconds: seconds, width: size.width, isLandscape: isLandscape)
                Rectangle()
                    .fill(Color(white: 0.25))
                    .frame(height: 2)
            }

            // Metric rows
            ForEach(data.metrics, id: \.key) { metric in
                metricRow(metric: metric, isLandscape: isLandscape)
                Rectangle()
                    .fill(Color(white: 0.25))
                    .frame(height: 1)
            }

            Spacer()

            // Time strip
            if let time = data.timeInCurrentState {
                Text(String(format: "%02d:%02d", Int(time) / 60, Int(time) % 60))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(flapAmber.opacity(0.5))
                    .padding(.bottom, 8)
            }
        }
        .padding(.top, 40)
    }

    // MARK: - State Row

    private func stateRow(width: CGFloat, isLandscape: Bool) -> some View {
        let maxChars = isLandscape ? 12 : 8
        let padded = displayedState.padding(toLength: maxChars, withPad: " ", startingAt: 0)

        return HStack(spacing: 2) {
            Spacer()
            ForEach(Array(padded.enumerated()), id: \.offset) { _, char in
                SplitFlapCell(character: char, color: flapColor, fontSize: .title3)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Countdown Row

    private func countdownRow(seconds: TimeInterval, width: CGFloat, isLandscape: Bool) -> some View {
        let clamped = max(0, Int(seconds))
        let m = clamped / 60
        let s = clamped % 60
        let text = String(format: "NUDGE IN  %02d:%02d", m, s)
        let maxChars = isLandscape ? 18 : 14
        let padded = text.padding(toLength: maxChars, withPad: " ", startingAt: 0)

        return HStack(spacing: 2) {
            Spacer()
            ForEach(Array(padded.enumerated()), id: \.offset) { _, char in
                SplitFlapCell(character: char, color: flapAmber, fontSize: .caption)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Metric Row

    private func metricRow(metric: MetricInfo, isLandscape: Bool) -> some View {
        let isWorst = metric.isWorstOffender && data.isAlertMode
        let nameText = abbreviatedName(for: metric.key, isLandscape: isLandscape)
        let valueText = String(format: "%03d", Int(metric.clampedRatio * 100))

        return HStack(spacing: 2) {
            // Worst offender marker
            if isWorst {
                Text("▶")
                    .font(.system(size: 8))
                    .foregroundStyle(flapColor)
                    .frame(width: 12)
            } else {
                Spacer().frame(width: 12)
            }

            // Name cells
            ForEach(Array(nameText.enumerated()), id: \.offset) { _, char in
                SplitFlapCell(character: char, color: flapColor, fontSize: .caption)
            }

            Spacer()

            // Value cells
            ForEach(Array(valueText.enumerated()), id: \.offset) { _, char in
                SplitFlapCell(character: char, color: flapColor, fontSize: .caption)
            }

            Spacer().frame(width: 12)
        }
        .padding(.vertical, 3)
        .background(isWorst ? Color(white: 0.2) : .clear)
    }

    // MARK: - Helpers

    private func abbreviatedName(for key: MetricKey, isLandscape: Bool) -> String {
        if isLandscape {
            switch key {
            case .forwardCreep:     return "FORWARD CREEP  "
            case .headDrop:         return "HEAD DROP      "
            case .shoulderRounding: return "SHOULDER ROUND "
            case .lateralLean:      return "LATERAL LEAN   "
            case .twist:            return "TWIST          "
            }
        } else {
            switch key {
            case .forwardCreep:     return "FWD CREP"
            case .headDrop:         return "HEAD DRP"
            case .shoulderRounding: return "SHLDR RD"
            case .lateralLean:      return "LAT LEAN"
            case .twist:            return "TWIST   "
            }
        }
    }

    private func flipToState(_ newText: String) {
        Task { @MainActor in
            let maxLen = max(displayedState.count, newText.count)
            let padTarget = newText.padding(toLength: maxLen, withPad: " ", startingAt: 0)
            var current = Array(displayedState.padding(toLength: maxLen, withPad: " ", startingAt: 0))
            let target = Array(padTarget)

            for i in 0..<maxLen {
                try? await Task.sleep(nanoseconds: UInt64(i) * 150_000_000)
                // Cycle through chars to reach target
                if current[i] != target[i] {
                    let steps = min(5, abs(Int(current[i].asciiValue ?? 65) - Int(target[i].asciiValue ?? 65)))
                    for step in 0..<steps {
                        let intermediate = Character(UnicodeScalar(
                            (Int(current[i].asciiValue ?? 65) + step + 1) % 91 + 32
                        ) ?? UnicodeScalar(65))
                        current[i] = intermediate
                        displayedState = String(current)
                        try? await Task.sleep(nanoseconds: 60_000_000)
                    }
                    current[i] = target[i]
                    displayedState = String(current)
                }
            }
        }
    }

    private func updateMetricValues() {
        for metric in data.metrics {
            metricDisplayValues[metric.key] = String(format: "%03d", Int(metric.clampedRatio * 100))
        }
    }
}

// MARK: - Split Flap Cell

struct SplitFlapCell: View {
    let character: Character
    let color: Color
    var fontSize: Font.TextStyle = .title3

    @State private var flipAngle: Double = 0

    var body: some View {
        let cellWidth: CGFloat = fontSize == .title3 ? 24 : 16
        let cellHeight: CGFloat = fontSize == .title3 ? 32 : 22

        ZStack {
            // Background
            VStack(spacing: 1) {
                // Top half
                Rectangle()
                    .fill(Color(white: 0.18))
                    .overlay(alignment: .bottom) {
                        Text(String(character))
                            .font(.system(fontSize, design: .monospaced))
                            .foregroundStyle(color)
                            .offset(y: cellHeight * 0.25)
                    }
                    .clipShape(Rectangle())

                // Bottom half
                Rectangle()
                    .fill(Color(white: 0.15))
                    .overlay(alignment: .top) {
                        Text(String(character))
                            .font(.system(fontSize, design: .monospaced))
                            .foregroundStyle(color)
                            .offset(y: -cellHeight * 0.25)
                    }
                    .clipShape(Rectangle())
            }

            // Hinge line
            Rectangle()
                .fill(Color.black)
                .frame(height: 1)
        }
        .frame(width: cellWidth, height: cellHeight)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant12View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant12View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant12View()
        .environmentObject(observer)
}
