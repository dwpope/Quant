import Combine
import SwiftUI
import PostureLogic

/// Variant 57: Achievement Rings — Three concentric Apple Watch-style activity rings
/// (Active Time, Consistency, Awareness) with five metric progress bars below.
/// Rings fill as goals are met; desaturate during bad posture.
struct Variant57View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var activeMinutes: Double = 0
    @State private var longestStreak: Double = 0
    @State private var currentStreak: Double = 0
    @State private var corrections: Int = 0
    @State private var wasAlertMode = false

    // Goals
    private let activeGoal: Double = 240  // 4 hours in minutes
    private let streakGoal: Double = 30   // 30-minute streak target
    private let correctionGoal: Int = 12

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private func ratio(for key: MetricKey) -> Float {
        isAbsent ? 0 : observer.data.metric(for: key).clampedRatio
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                Color(hue: 0.0, saturation: 0.0, brightness: 0.05)
                    .ignoresSafeArea()

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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard !isAbsent else { return }
            if !observer.data.isAlertMode {
                activeMinutes += 1.0 / 60.0
                currentStreak += 1.0 / 60.0
                if currentStreak > longestStreak {
                    longestStreak = currentStreak
                }
            }
            // Track corrections (alert → good transition)
            if wasAlertMode && !observer.data.isAlertMode {
                corrections += 1
                currentStreak = 0
            }
            wasAlertMode = observer.data.isAlertMode
        }
    }

    // MARK: - Layouts

    private func portraitLayout(size: CGSize) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ringsView(size: min(size.width, size.height) * 0.55)
            ringLabels
            Spacer()
            metricBars(width: size.width - 48)
            Spacer()

            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                alertBanner(metric: worst)
                    .padding(.bottom, 16)
            }
        }
    }

    private func landscapeLayout(size: CGSize) -> some View {
        HStack(spacing: 16) {
            VStack {
                Spacer()
                ringsView(size: min(size.width * 0.45, size.height * 0.8))
                ringLabels
                Spacer()
            }

            VStack(spacing: 8) {
                Spacer()
                metricBars(width: size.width * 0.4)
                Spacer()
                if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                    alertBanner(metric: worst)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Rings

    private func ringsView(size: CGFloat) -> some View {
        let desaturated = observer.data.isAlertMode
        let activeRatio = min(activeMinutes / activeGoal, 1.0)
        let streakRatio = min(longestStreak / streakGoal, 1.0)
        let correctionRatio = min(Double(corrections) / Double(correctionGoal), 1.0)

        return ZStack {
            // Outer ring — Active Time (red)
            ringArc(fill: activeRatio, color: .red, lineWidth: 20, diameter: size)
                .saturation(desaturated ? 0.3 : 1.0)

            // Middle ring — Consistency (green)
            ringArc(fill: streakRatio, color: .green, lineWidth: 20, diameter: size * 0.72)
                .saturation(desaturated ? 0.3 : 1.0)

            // Inner ring — Awareness (blue)
            ringArc(fill: correctionRatio, color: .blue, lineWidth: 20, diameter: size * 0.44)
                .saturation(desaturated ? 0.3 : 1.0)

            // Center values
            VStack(spacing: 2) {
                Text("\(Int(activeMinutes))m")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                Text("\(Int(longestStreak))m")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                Text("\(corrections)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: size, height: size)
    }

    private func ringArc(fill: Double, color: Color, lineWidth: CGFloat, diameter: CGFloat) -> some View {
        ZStack {
            // Track
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
                .frame(width: diameter, height: diameter)

            // Fill
            Circle()
                .trim(from: 0, to: fill)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: fill)

            // Glow if complete
            if fill >= 1.0 {
                Circle()
                    .stroke(color.opacity(0.4), lineWidth: lineWidth + 6)
                    .frame(width: diameter, height: diameter)
                    .blur(radius: 4)
            }
        }
    }

    // MARK: - Ring Labels

    private var ringLabels: some View {
        HStack(spacing: 16) {
            ringLabel(color: .red, text: "Active Time")
            ringLabel(color: .green, text: "Consistency")
            ringLabel(color: .blue, text: "Awareness")
        }
    }

    private func ringLabel(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Metric Bars

    private func metricBars(width: CGFloat) -> some View {
        VStack(spacing: 8) {
            ForEach(MetricKey.allCases) { key in
                let r = ratio(for: key)
                let isWorst = observer.data.worstOffender?.key == key && observer.data.isAlertMode

                HStack(spacing: 8) {
                    Text(key.displayName)
                        .font(.system(size: 11, weight: isWorst ? .bold : .regular))
                        .foregroundStyle(.white.opacity(isWorst ? 0.9 : 0.6))
                        .frame(width: 80, alignment: .trailing)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: width * 0.55, height: 10)

                        Capsule()
                            .fill(PostureVisualStyle.metricColor(ratio: r))
                            .frame(width: width * 0.55 * CGFloat(min(r, 1.0)), height: 10)
                            .animation(.easeInOut(duration: 0.3), value: r)
                    }
                }
            }
        }
    }

    // MARK: - Alert Banner

    private func alertBanner(metric: MetricInfo) -> some View {
        Text("Posture Alert: \(metric.key.displayName)")
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(.orange)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.15), in: Capsule())
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant57View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .shoulderRounding,
        worstRatio: 0.9
    )
    let observer = PostureDisplayObserver(source: source)
    Variant57View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant57View()
        .environmentObject(observer)
}
