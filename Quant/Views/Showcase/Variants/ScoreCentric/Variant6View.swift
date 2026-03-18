import SwiftUI
import PostureLogic

struct Variant6View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @Namespace private var metricNamespace
    @State private var showingSettings = false
    @State private var isFireFlashVisible = true
    @State private var isPulsingBorder = false

    private let lightDiameter: CGFloat = 90

    private var data: PostureDisplayData { observer.data }

    private var isAbsent: Bool {
        switch data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private var isFire: Bool {
        if case .fire = data.nudgeDecision { return true }
        return false
    }

    // 0 = green, 1 = yellow, 2 = red
    private var activeLight: Int {
        switch data.postureState {
        case .bad: return 2
        case .drifting: return 1
        default: return 0
        }
    }

    private var countdownProgress: CGFloat {
        guard let seconds = data.nudgeCountdownSeconds else { return 0 }
        let maxSeconds: CGFloat = 30
        return CGFloat(max(0, min(seconds, Double(maxSeconds)))) / maxSeconds
    }

    private var statusLabel: String {
        switch data.postureState {
        case .good:
            return "All Clear"
        case .drifting:
            if let worst = data.worstOffender {
                return "Caution: \(worst.key.displayName)"
            }
            return "Caution"
        case .bad:
            return "Correct Now"
        default:
            return ""
        }
    }

    private var statusColor: Color {
        switch data.postureState {
        case .good: return Color(hue: 0.38, saturation: 0.6, brightness: 0.7)
        case .drifting: return Color(hue: 0.12, saturation: 0.7, brightness: 0.8)
        case .bad: return Color(hue: 0.02, saturation: 0.9, brightness: 0.8)
        default: return .secondary
        }
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: data.postureState)

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
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
        }
        .sensoryFeedback(.impact, trigger: data.postureState.isBad)
        .animation(.easeInOut(duration: 0.5), value: activeLight)
        .animation(PostureAnimations.alertOnset, value: data.isAlertMode)
        .onAppear {
            if data.postureState.isBad {
                isPulsingBorder = true
            }
            if isFire {
                startFireFlash()
            }
        }
        .onChange(of: data.postureState.isBad) { _, isBad in
            isPulsingBorder = isBad
        }
        .onChange(of: isFire) { _, newValue in
            if newValue {
                startFireFlash()
            }
        }
    }

    // MARK: - Portrait Layout

    private var portraitLayout: some View {
        VStack(spacing: 16) {
            Spacer()
            housing(isLandscape: false)
            Text(statusLabel)
                .font(.headline)
                .foregroundStyle(statusColor)
            Spacer()
        }
    }

    // MARK: - Landscape Layout

    private var landscapeLayout: some View {
        VStack(spacing: 12) {
            Spacer()
            housing(isLandscape: true)
            Text(statusLabel)
                .font(.headline)
                .foregroundStyle(statusColor)
            Spacer()
        }
    }

    // MARK: - Housing

    @ViewBuilder
    private func housing(isLandscape: Bool) -> some View {
        let spacing: CGFloat = 12
        let padding: CGFloat = 20
        let cr = lightDiameter / 2 + padding

        if isLandscape {
            VStack(spacing: 4) {
                // Caption labels above each light
                HStack(spacing: spacing) {
                    Text("Good").font(.caption2).foregroundStyle(.secondary)
                        .frame(width: lightDiameter)
                    Text("Caution").font(.caption2).foregroundStyle(.secondary)
                        .frame(width: lightDiameter)
                    Text("Alert").font(.caption2).foregroundStyle(.secondary)
                        .frame(width: lightDiameter)
                }

                HStack(spacing: spacing) {
                    greenLightView
                    yellowLightView
                    redLightView
                }
                .padding(padding)
                .background(housingBackground(cornerRadius: cr))
                .overlay(alignment: .top) {
                    gearButton
                        .offset(y: -12)
                }
            }
        } else {
            VStack(spacing: spacing) {
                gearButton
                greenLightView
                yellowLightView
                redLightView
            }
            .padding(padding)
            .background(housingBackground(cornerRadius: cr))
        }
    }

    private var gearButton: some View {
        SettingsGearButton { showingSettings = true }
            .font(.caption2)
            .padding(4)
            .background(Color.primary.opacity(0.15), in: Circle())
    }

    private func housingBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.primary.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.black.opacity(0.4), lineWidth: 4)
                    .blur(radius: 4)
                    .mask(RoundedRectangle(cornerRadius: cornerRadius))
            )
    }

    // MARK: - Green Light

    private var greenLightView: some View {
        let isActive = activeLight == 0
        return ZStack {
            // Radial glow when active
            if isActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.green.opacity(0.5), Color.green.opacity(0)],
                            center: .center,
                            startRadius: lightDiameter * 0.3,
                            endRadius: lightDiameter * 0.75
                        )
                    )
                    .frame(width: lightDiameter * 1.4, height: lightDiameter * 1.4)
            }

            // Light circle
            Circle()
                .fill(Color.green)
                .frame(width: lightDiameter, height: lightDiameter)
                .opacity(isActive ? 1.0 : 0.15)

            // Five concentric metric rings when active
            if isActive {
                metricRingsInGreen
            }
        }
        .frame(width: lightDiameter, height: lightDiameter)
    }

    // MARK: - Yellow Light

    private var yellowLightView: some View {
        let isActive = activeLight == 1
        return ZStack {
            if isActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.orange.opacity(0.5), Color.orange.opacity(0)],
                            center: .center,
                            startRadius: lightDiameter * 0.3,
                            endRadius: lightDiameter * 0.75
                        )
                    )
                    .frame(width: lightDiameter * 1.4, height: lightDiameter * 1.4)
            }

            Circle()
                .fill(Color.orange)
                .frame(width: lightDiameter, height: lightDiameter)
                .opacity(isActive ? 1.0 : 0.15)

            // Worst offender ring + metric name
            if isActive {
                worstOffenderRing(color: .orange, fullyFilled: false)
            }

            // Countdown arc around circumference
            if isActive {
                Circle()
                    .trim(from: 0, to: countdownProgress)
                    .stroke(Color.orange.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: lightDiameter + 6, height: lightDiameter + 6)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: countdownProgress)
            }
        }
        .frame(width: lightDiameter, height: lightDiameter)
    }

    // MARK: - Red Light

    private var redLightView: some View {
        let isActive = activeLight == 2
        return ZStack {
            // Aggressive red glow
            if isActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.red.opacity(0.6), Color.red.opacity(0)],
                            center: .center,
                            startRadius: lightDiameter * 0.2,
                            endRadius: lightDiameter * 0.85
                        )
                    )
                    .frame(width: lightDiameter * 1.6, height: lightDiameter * 1.6)
            }

            Circle()
                .fill(Color.red)
                .frame(width: lightDiameter, height: lightDiameter)
                .opacity(isActive ? 1.0 : 0.15)

            // Worst offender ring fully filled
            if isActive {
                worstOffenderRing(color: .red, fullyFilled: true)
            }

            // Pulsing border replaces countdown arc
            if isActive {
                Circle()
                    .stroke(Color.red, lineWidth: 3)
                    .frame(width: lightDiameter + 6, height: lightDiameter + 6)
                    .opacity(isPulsingBorder ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                        value: isPulsingBorder
                    )
            }
        }
        .frame(width: lightDiameter, height: lightDiameter)
        .opacity(isActive && isFire ? (isFireFlashVisible ? 1.0 : 0.0) : 1.0)
    }

    // MARK: - Metric Rings in Green Light

    private var metricRingsInGreen: some View {
        ZStack {
            ForEach(Array(data.metrics.enumerated()), id: \.element.key) { index, metric in
                let ringSize = lightDiameter * 0.7 - CGFloat(index) * 10

                if metric.isWorstOffender {
                    Circle()
                        .trim(from: 0, to: CGFloat(metric.clampedRatio))
                        .stroke(Color.green.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: ringSize, height: ringSize)
                        .rotationEffect(.degrees(-90))
                        .matchedGeometryEffect(id: "activeMetric", in: metricNamespace)
                } else {
                    Circle()
                        .trim(from: 0, to: CGFloat(metric.clampedRatio))
                        .stroke(Color.green.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: ringSize, height: ringSize)
                        .rotationEffect(.degrees(-90))
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Worst Offender Ring

    @ViewBuilder
    private func worstOffenderRing(color: Color, fullyFilled: Bool) -> some View {
        if let worst = data.worstOffender {
            VStack(spacing: 2) {
                Circle()
                    .trim(from: 0, to: fullyFilled ? 1.0 : CGFloat(worst.clampedRatio))
                    .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: lightDiameter * 0.5, height: lightDiameter * 0.5)
                    .rotationEffect(.degrees(-90))
                    .matchedGeometryEffect(id: "activeMetric", in: metricNamespace)

                Text(worst.key.displayName)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    // MARK: - Fire Flash

    private func startFireFlash() {
        Task { @MainActor in
            for _ in 0..<3 {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isFireFlashVisible = false
                }
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation(.easeInOut(duration: 0.1)) {
                    isFireFlashVisible = true
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant6View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant6View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant6View()
        .environmentObject(observer)
}
