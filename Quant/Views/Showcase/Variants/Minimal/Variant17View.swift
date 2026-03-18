import SwiftUI
import PostureLogic

/// Variant 17: Clock Face — A large digital clock dominates the screen.
/// Posture quality is communicated through background color, font style,
/// indicator dots, and a score underline bar.
struct Variant17View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private var score: Float { observer.data.aggregateScore }

    private var clockColor: Color {
        let t = Double(1.0 - score)
        if t < 0.3 { return .primary }
        return Color(hue: max(0, 0.12 - t * 0.12), saturation: 0.6 * t, brightness: 0.85)
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        if isLandscape {
                            landscapeContent(size: geo.size)
                        } else {
                            portraitContent(size: geo.size)
                        }
                    }
                } else {
                    if isLandscape {
                        landscapeContent(size: geo.size)
                    } else {
                        portraitContent(size: geo.size)
                    }
                }

                // Settings gear at "3 o'clock" position
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

    // MARK: - Portrait

    private func portraitContent(size: CGSize) -> some View {
        VStack(spacing: 12) {
            Spacer()

            // Metric indicator dots in arc above time
            metricDotsArc

            // Time display
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(Date.now, format: .dateTime.hour().minute().second())
                    .font(.system(size: 96, weight: .thin, design: .rounded))
                    .foregroundStyle(clockColor)
                    .monospacedDigit()
            }

            // Score underline bar
            scoreUnderline(width: size.width * 0.6)

            // Date
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                if observer.data.isAlertMode, let seconds = observer.data.nudgeCountdownSeconds {
                    Text("Nudge in \(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                        .font(.title3.weight(.light))
                        .foregroundStyle(.secondary)
                }
            }

            // Worst offender in alert mode
            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                Text("Correct: \(worst.key.displayName)")
                    .font(.caption)
                    .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                    .transition(.opacity)
            }

            Spacer()
        }
    }

    // MARK: - Landscape

    private func landscapeContent(size: CGSize) -> some View {
        HStack(spacing: 0) {
            // Left: clock
            VStack(spacing: 12) {
                Spacer()
                metricDotsArc

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Date.now, format: .dateTime.hour().minute().second())
                        .font(.system(size: 72, weight: .thin, design: .rounded))
                        .foregroundStyle(clockColor)
                        .monospacedDigit()
                }

                scoreUnderline(width: size.width * 0.35)

                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    if observer.data.isAlertMode, let seconds = observer.data.nudgeCountdownSeconds {
                        Text("Nudge in \(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                            .font(.subheadline.weight(.light))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .frame(width: size.width * 0.55)

            // Right: metric detail column
            VStack(alignment: .leading, spacing: 10) {
                ForEach(observer.data.metrics, id: \.key) { metric in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(PostureVisualStyle.metricColor(ratio: metric.ratio))
                            .frame(width: 8, height: 8)
                        Text(metric.key.displayName)
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.0f%%", metric.clampedRatio * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(width: size.width * 0.4)
        }
    }

    // MARK: - Components

    private var metricDotsArc: some View {
        HStack(spacing: 16) {
            ForEach(observer.data.metrics, id: \.key) { metric in
                let isWorst = metric.isWorstOffender && observer.data.isAlertMode

                VStack(spacing: 2) {
                    Circle()
                        .fill(PostureVisualStyle.metricColor(ratio: metric.ratio))
                        .frame(width: isWorst ? 10 : 6, height: isWorst ? 10 : 6)

                    if isWorst {
                        Text(metric.key.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    private func scoreUnderline(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.secondary.opacity(0.2))
                .frame(width: width, height: 1)

            Rectangle()
                .fill(PostureVisualStyle.stateColor(for: observer.data.postureState).opacity(0.6))
                .frame(width: width * CGFloat(score), height: 1)
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant17View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant17View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant17View()
        .environmentObject(observer)
}
