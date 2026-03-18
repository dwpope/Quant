import SwiftUI
import PostureLogic

struct Variant9View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var shimmerOffset: CGFloat = -1

    private var data: PostureDisplayData { observer.data }

    private var isAbsent: Bool {
        switch data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private var summaryLabel: String {
        "Posture: \(PostureVisualStyle.stateLabel(for: data.postureState))"
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        railsContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    railsContent(size: geo.size, isLandscape: isLandscape)
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
        .onAppear { startShimmer() }
    }

    // MARK: - Rails Content

    private func railsContent(size: CGSize, isLandscape: Bool) -> some View {
        VStack(spacing: 16) {
            // Summary label
            HStack {
                Text(summaryLabel)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(PostureVisualStyle.stateColor(for: data.postureState))
                Spacer()
            }
            .padding(.horizontal)

            Spacer()

            // Five horizontal bars
            VStack(spacing: 20) {
                ForEach(data.metrics, id: \.key) { metric in
                    railBar(metric: metric, isLandscape: isLandscape)
                }
            }
            .padding(.horizontal)

            // Time in state
            if let time = data.timeInCurrentState {
                Text("In state for \(Int(time))s")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Countdown for worst offender
            if data.isAlertMode, let worst = data.worstOffender {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.caption)
                    NudgeCountdownLabel(seconds: data.nudgeCountdownSeconds, style: .compact)
                }
                .foregroundStyle(PostureVisualStyle.stateColor(for: data.postureState))
            }

            Spacer()
        }
        .padding(.top, 40)
    }

    // MARK: - Rail Bar

    private func railBar(metric: MetricInfo, isLandscape: Bool) -> some View {
        let isWorst = metric.isWorstOffender && data.isAlertMode
        let barHeight: CGFloat = isWorst ? 18 : 12
        let fillColor = barFillColor(ratio: metric.clampedRatio)

        return VStack(alignment: .leading, spacing: 2) {
            if isLandscape {
                Text(metric.key.displayName)
                    .font(.caption)
                    .foregroundStyle(isWorst ? .primary : .secondary)
                    .fontWeight(isWorst ? .bold : .medium)
            }

            HStack(spacing: 10) {
                if !isLandscape {
                    Text(metric.key.displayName)
                        .font(.subheadline.weight(isWorst ? .bold : .medium))
                        .foregroundStyle(isWorst ? .primary : .secondary)
                        .frame(width: 120, alignment: .leading)
                }

                // Track + fill
                GeometryReader { geo in
                    let trackWidth = geo.size.width
                    let fillWidth = trackWidth * CGFloat(metric.clampedRatio)
                    let overflowWidth = data.postureState.isBad && isWorst
                        ? trackWidth * CGFloat(min(metric.clampedRatio, 1.2))
                        : fillWidth

                    ZStack(alignment: .leading) {
                        // Track background
                        RoundedRectangle(cornerRadius: barHeight / 2)
                            .fill(.secondary.opacity(0.2))

                        // Fill bar
                        RoundedRectangle(cornerRadius: barHeight / 2)
                            .fill(fillColor)
                            .frame(width: max(barHeight, overflowWidth))

                        // Shimmer on worst offender
                        if isWorst {
                            RoundedRectangle(cornerRadius: barHeight / 2)
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, .white.opacity(0.3), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: fillWidth * 0.4)
                                .offset(x: shimmerOffset * fillWidth)
                                .mask(
                                    RoundedRectangle(cornerRadius: barHeight / 2)
                                        .frame(width: fillWidth)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                )
                        }

                        // Threshold marker
                        Rectangle()
                            .fill(.secondary)
                            .frame(width: 1, height: barHeight)
                            .offset(x: trackWidth - 1)
                    }
                }
                .frame(height: barHeight)
                .clipShape(data.postureState.isBad && isWorst
                    ? AnyShape(Rectangle())
                    : AnyShape(RoundedRectangle(cornerRadius: barHeight / 2)))

                Text(String(format: "%.0f%%", metric.clampedRatio * 100))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(isWorst ? .primary : .secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, isWorst ? 6 : 0)
        .padding(.horizontal, isWorst ? 8 : 0)
        .background(
            isWorst
                ? AnyShapeStyle(.thinMaterial)
                : AnyShapeStyle(.clear)
            , in: RoundedRectangle(cornerRadius: 12)
        )
        .opacity(data.isAlertMode && !isWorst ? 0.6 : 1.0)
        .animation(PostureAnimations.metricUpdate, value: metric.clampedRatio)
    }

    // MARK: - Helpers

    private func barFillColor(ratio: Float) -> Color {
        if ratio < 0.5 {
            return .green
        } else if ratio < 0.8 {
            let t = Double(ratio - 0.5) / 0.3
            return Color(hue: 0.15 - t * 0.05, saturation: 0.7 + t * 0.1, brightness: 0.8)
        } else {
            return .red
        }
    }

    private func startShimmer() {
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            shimmerOffset = 1
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant9View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant9View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant9View()
        .environmentObject(observer)
}
