import SwiftUI
import PostureLogic

/// Variant 50: Chromatic Split — Clean, precise monochrome metric display with center checkmark
/// lens and thin horizontal bars. When posture degrades, Metal chromatic aberration shader splits
/// RGB channels. Worst offender shown as aberration-free capsule pill. Focus ring countdown.
struct Variant50View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private var avgStress: Float {
        isAbsent ? 0 : (1.0 - observer.data.aggregateScore)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isAbsent {
                    AbsenceOverlay {
                        chromaticContent(size: geo.size)
                    }
                } else {
                    chromaticContent(size: geo.size)
                }

                settingsButton()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
        }
        .animation(PostureAnimations.alertOnset, value: observer.data.isAlertMode)
    }

    // MARK: - Settings

    private func settingsButton() -> some View {
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

    // MARK: - Chromatic Content

    @ViewBuilder
    private func chromaticContent(size: CGSize) -> some View {
        PostureShaderFallback {
            shaderChromaticView(size: size)
        } fallbackContent: {
            fallbackChromaticView(size: size)
        }
    }

    // MARK: - Shader Path

    @available(iOS 17, *)
    private func shaderChromaticView(size: CGSize) -> some View {
        ZStack {
            monochromeDisplay()
                .postureChromaticEffect(data: observer.data, size: size)

            worstOffenderPill()

            countdownRing()
        }
    }

    // MARK: - Fallback Path

    private func fallbackChromaticView(size: CGSize) -> some View {
        ZStack {
            monochromeDisplay()

            // Simulated chromatic offset with colored overlays
            if avgStress > 0.2 {
                fallbackAberration()
            }

            worstOffenderPill()

            countdownRing()
        }
    }

    private func fallbackAberration() -> some View {
        let offset = CGFloat(avgStress) * 6

        return ZStack {
            Color.red.opacity(Double(avgStress) * 0.08)
                .offset(x: -offset, y: -offset * 0.5)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            Color.blue.opacity(Double(avgStress) * 0.08)
                .offset(x: offset, y: offset * 0.5)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .blendMode(.screen)
    }

    // MARK: - Monochrome Display

    private func monochromeDisplay() -> some View {
        ZStack {
            Color(white: 0.06)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                checkmarkLens()

                metricBars()

                Spacer()
                Spacer()
            }
        }
    }

    // MARK: - Checkmark Lens

    private func checkmarkLens() -> some View {
        let stateColor = PostureVisualStyle.stateColor(for: observer.data.postureState)
        let score = isAbsent ? Float(1) : observer.data.aggregateScore
        let isGood = score > 0.7

        return ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.15), lineWidth: 2)
                .frame(width: 72, height: 72)

            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: 72, height: 72)

            Image(systemName: isGood ? "checkmark" : "exclamationmark")
                .font(.title.bold())
                .foregroundStyle(stateColor)
        }
    }

    // MARK: - Metric Bars

    private func metricBars() -> some View {
        VStack(spacing: 12) {
            ForEach(MetricKey.allCases) { key in
                thinMetricBar(key: key)
            }
        }
        .padding(.horizontal, 40)
    }

    private func thinMetricBar(key: MetricKey) -> some View {
        let ratio = isAbsent ? Float(0) : observer.data.metric(for: key).clampedRatio

        return HStack(spacing: 10) {
            Text(key.displayName)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 80, alignment: .trailing)

            barTrack(ratio: CGFloat(ratio))

            Text(Int(ratio * 100), format: .number)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 28, alignment: .leading)
        }
    }

    private func barTrack(ratio: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.08))

                Capsule()
                    .fill(.white.opacity(0.5))
                    .frame(width: geo.size.width * ratio)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Worst Offender Pill

    @ViewBuilder
    private func worstOffenderPill() -> some View {
        if observer.data.isAlertMode, let worst = observer.data.worstOffender {
            VStack {
                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: worst.key.symbolName)
                        .font(.caption2)
                    Text(worst.key.displayName)
                        .font(.caption.bold())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(white: 0.15)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
            }
            .padding(.bottom, 54)
        }
    }

    // MARK: - Countdown Ring

    @ViewBuilder
    private func countdownRing() -> some View {
        if let seconds = observer.data.nudgeCountdownSeconds {
            let maxSeconds: Double = 30
            let fraction = min(seconds / maxSeconds, 1.0)

            VStack {
                Spacer()

                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 2)
                        .frame(width: 28, height: 28)

                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(-90))

                    Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                        .font(.system(size: 7).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant50View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .twist,
        worstRatio: 0.9
    )
    let observer = PostureDisplayObserver(source: source)
    Variant50View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant50View()
        .environmentObject(observer)
}
