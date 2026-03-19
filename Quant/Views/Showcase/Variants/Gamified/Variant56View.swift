import Combine
import SwiftUI
import PostureLogic

/// Variant 56: Streak Counter — A large, prominent counter showing the current unbroken
/// streak of good posture time, with personal best record, fire indicator, and five
/// checkmark circles that must all be met to keep the streak alive.
struct Variant56View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var streakSeconds: TimeInterval = 0
    @State private var bestStreak: TimeInterval = 0
    @State private var isStreakActive = true
    @State private var showCelebration = false

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private func ratio(for key: MetricKey) -> Float {
        isAbsent ? 0 : observer.data.metric(for: key).clampedRatio
    }

    private var allMetricsGood: Bool {
        MetricKey.allCases.allSatisfy { ratio(for: $0) < 1.0 }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hue: 0.0, saturation: 0.0, brightness: 0.06)
                    .ignoresSafeArea()

                if isAbsent {
                    AbsenceOverlay {
                        streakContent(size: geo.size)
                    }
                } else {
                    streakContent(size: geo.size)
                }

                if showCelebration {
                    celebrationBurst
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
            if allMetricsGood && !observer.data.isAlertMode {
                streakSeconds += 1
                isStreakActive = true
                if streakSeconds > bestStreak {
                    bestStreak = streakSeconds
                }
                // Milestone celebrations at 5m, 15m, 30m
                if [300, 900, 1800].contains(Int(streakSeconds)) {
                    withAnimation(.spring()) { showCelebration = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { showCelebration = false }
                    }
                }
            } else if observer.data.isAlertMode && observer.data.nudgeCountdownSeconds == nil {
                // Streak broken
                if isStreakActive {
                    isStreakActive = false
                    streakSeconds = 0
                }
            }
        }
    }

    // MARK: - Streak Content

    private func streakContent(size: CGSize) -> some View {
        VStack(spacing: 20) {
            Spacer()

            // Fire indicator (background)
            if streakSeconds > 300 && isStreakActive {
                fireIndicator
                    .transition(.scale.combined(with: .opacity))
            }

            // Main timer
            Text(formatTime(streakSeconds))
                .font(.system(size: 64, weight: .bold, design: .monospaced))
                .foregroundStyle(isStreakActive ? .white : .white.opacity(0.3))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(isStreakActive ? "CURRENT STREAK" : "STREAK PAUSED")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(isStreakActive ? .white.opacity(0.5) : .orange.opacity(0.7))

            Text("PERSONAL BEST: \(formatTime(bestStreak))")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))

            Spacer()

            // Check circles
            checkCircleRow

            Spacer()

            // Grace period
            if let seconds = observer.data.nudgeCountdownSeconds, observer.data.isAlertMode {
                gracePeriod(seconds: seconds)
                    .padding(.horizontal, 24)
            }

            // Streak breaker info
            if !isStreakActive, let worst = observer.data.worstOffender, observer.data.isAlertMode {
                Text("BROKEN BY: \(worst.key.displayName)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.bottom, 16)
            }

            Spacer()
        }
    }

    // MARK: - Format Time

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins >= 60 {
            let hrs = mins / 60
            let remainMins = mins % 60
            return String(format: "%d:%02d:%02d", hrs, remainMins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    // MARK: - Fire Indicator

    private var fireIndicator: some View {
        let scale = min(1.0 + streakSeconds / 3600, 2.0)
        return Canvas { context, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let baseH = size.height * 0.4 * scale

            // Outer flame
            var flame = Path()
            flame.move(to: CGPoint(x: cx, y: cy - baseH / 2))
            flame.addQuadCurve(
                to: CGPoint(x: cx + baseH * 0.3, y: cy + baseH / 2),
                control: CGPoint(x: cx + baseH * 0.5, y: cy)
            )
            flame.addQuadCurve(
                to: CGPoint(x: cx - baseH * 0.3, y: cy + baseH / 2),
                control: CGPoint(x: cx, y: cy + baseH * 0.3)
            )
            flame.addQuadCurve(
                to: CGPoint(x: cx, y: cy - baseH / 2),
                control: CGPoint(x: cx - baseH * 0.5, y: cy)
            )
            context.fill(flame, with: .linearGradient(
                Gradient(colors: [.orange, .red.opacity(0.3)]),
                startPoint: CGPoint(x: cx, y: cy - baseH / 2),
                endPoint: CGPoint(x: cx, y: cy + baseH / 2)
            ))
        }
        .frame(width: 120, height: 120)
        .opacity(0.3)
    }

    // MARK: - Check Circle Row

    private var checkCircleRow: some View {
        HStack(spacing: 16) {
            ForEach(MetricKey.allCases) { key in
                let r = ratio(for: key)
                let good = r < 1.0
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .stroke(good ? Color.green : Color.red, lineWidth: 2)
                            .frame(width: 32, height: 32)

                        if good {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.red)
                        }
                    }
                    Text(String(key.displayName.prefix(3)).uppercased())
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    // MARK: - Grace Period

    private func gracePeriod(seconds: TimeInterval) -> some View {
        VStack(spacing: 6) {
            Text("FIX IN \(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds)) TO SAVE STREAK")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)

            Text(isStreakActive ? "STREAK AT RISK" : "RECOVERING...")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.orange.opacity(0.6))
        }
    }

    // MARK: - Celebration Burst

    private var celebrationBurst: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Circle()
                    .stroke(Color.yellow.opacity(0.3), lineWidth: 2)
                    .frame(width: CGFloat(40 + i * 30), height: CGFloat(40 + i * 30))
                    .scaleEffect(showCelebration ? 1.5 : 0.5)
                    .opacity(showCelebration ? 0 : 0.8)
                    .animation(
                        .easeOut(duration: 1.2).delay(Double(i) * 0.1),
                        value: showCelebration
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant56View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 1.2
    )
    let observer = PostureDisplayObserver(source: source)
    Variant56View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant56View()
        .environmentObject(observer)
}
