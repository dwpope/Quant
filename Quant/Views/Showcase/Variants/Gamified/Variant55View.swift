import SwiftUI
import PostureLogic

/// Variant 55: XP Health Bar — RPG heads-up display with a health bar that depletes
/// with bad posture, an XP counter that accumulates during good posture, level indicator,
/// and five debuff icons that activate when metric ratios exceed thresholds.
struct Variant55View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var flashCritical = false

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private func ratio(for key: MetricKey) -> Float {
        isAbsent ? 0 : observer.data.metric(for: key).clampedRatio
    }

    /// Overall health: 1.0 at good, 0.0 at worst.
    private var health: Float {
        isAbsent ? 1 : observer.data.aggregateScore
    }

    /// XP fill: inverse of stress — higher score = more XP accumulation.
    private var xpFill: Float {
        isAbsent ? 0.5 : observer.data.aggregateScore
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hue: 0.68, saturation: 0.25, brightness: 0.1)
                    .ignoresSafeArea()

                if isAbsent {
                    AbsenceOverlay {
                        rpgHUD(size: geo.size)
                    }
                } else {
                    rpgHUD(size: geo.size)
                }

                if flashCritical {
                    criticalHitOverlay
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
        .onChange(of: observer.data.nudgeDecision.isFire) { _, isFire in
            if isFire {
                withAnimation(.easeOut(duration: 0.1)) { flashCritical = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeIn(duration: 0.3)) { flashCritical = false }
                }
            }
        }
    }

    // MARK: - RPG HUD

    private func rpgHUD(size: CGSize) -> some View {
        VStack(spacing: 16) {
            Spacer()

            // Character name and level
            HStack {
                Text("POSTURE HERO")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text("Lv. \(max(1, Int(xpFill * 20) + 1))")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.yellow)
            }
            .padding(.horizontal, 24)

            // Health bar
            healthBar(width: size.width - 48)
                .padding(.horizontal, 24)

            // XP bar
            xpBar(width: size.width - 48)
                .padding(.horizontal, 24)

            Spacer()

            // Debuff icons
            debuffRow
                .padding(.horizontal, 16)

            Spacer()

            // Status text
            statusText

            Spacer()

            // Nudge countdown (boss attack timer)
            if let seconds = observer.data.nudgeCountdownSeconds {
                attackTimer(seconds: seconds, width: size.width - 48)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Health Bar

    private func healthBar(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("HP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.8))
                Spacer()
                Text("\(Int(health * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: width, height: 16)

                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: healthBarColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * CGFloat(health), height: 16)
                    .animation(.easeInOut(duration: 0.5), value: health)

                // Notch marks
                HStack(spacing: 0) {
                    ForEach(1..<10, id: \.self) { i in
                        Spacer()
                        Rectangle()
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 1, height: 16)
                    }
                    Spacer()
                }
                .frame(width: width)
            }
        }
    }

    private var healthBarColors: [Color] {
        if health > 0.6 {
            return [.green, .green.opacity(0.8)]
        } else if health > 0.3 {
            return [.yellow, .orange]
        } else {
            return [.red, .red.opacity(0.6)]
        }
    }

    // MARK: - XP Bar

    private func xpBar(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("XP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.blue.opacity(0.8))
                Spacer()
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: width, height: 8)

                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * CGFloat(xpFill), height: 8)
                    .animation(.easeInOut(duration: 0.5), value: xpFill)
            }
        }
    }

    // MARK: - Debuff Icons

    private struct DebuffInfo {
        let key: MetricKey
        let symbol: String
        let label: String
        let color: Color
    }

    private var debuffs: [DebuffInfo] {
        [
            DebuffInfo(key: .forwardCreep, symbol: "arrow.right", label: "Pushed", color: .red),
            DebuffInfo(key: .headDrop, symbol: "arrow.down", label: "Weakened", color: .orange),
            DebuffInfo(key: .shoulderRounding, symbol: "arrow.left.and.right", label: "Cursed", color: .purple),
            DebuffInfo(key: .lateralLean, symbol: "line.diagonal", label: "Off-Balance", color: .blue),
            DebuffInfo(key: .twist, symbol: "arrow.triangle.2.circlepath", label: "Twisted", color: .green),
        ]
    }

    private var debuffRow: some View {
        HStack(spacing: 12) {
            ForEach(debuffs, id: \.key) { debuff in
                let r = ratio(for: debuff.key)
                let active = r > 0.3
                let isWorst = observer.data.worstOffender?.key == debuff.key && observer.data.isAlertMode

                VStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(active ? debuff.color : .gray.opacity(0.3), lineWidth: 1.5)
                            .frame(width: isWorst ? 44 : 36, height: isWorst ? 44 : 36)

                        Image(systemName: debuff.symbol)
                            .font(.system(size: isWorst ? 18 : 14))
                            .foregroundStyle(active ? debuff.color : .gray.opacity(0.3))
                    }

                    if active {
                        Text(debuff.label)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(debuff.color.opacity(0.8))
                    }
                }
                .animation(.spring(response: 0.4), value: active)
            }
        }
    }

    // MARK: - Status Text

    private var statusText: some View {
        Group {
            if observer.data.isAlertMode {
                if let worst = observer.data.worstOffender {
                    Text("ALERT: \(worst.key.displayName)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red)
                }
            } else if !isAbsent {
                Text("ALL CLEAR")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.7))
            }
        }
    }

    // MARK: - Attack Timer

    private func attackTimer(seconds: TimeInterval, width: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text("INCOMING ATTACK IN \(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.red)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: width, height: 6)

                RoundedRectangle(cornerRadius: 3)
                    .fill(.red)
                    .frame(width: width * min(CGFloat(seconds / 30.0), 1.0), height: 6)
            }
        }
    }

    // MARK: - Critical Hit

    private var criticalHitOverlay: some View {
        ZStack {
            Color.red.opacity(0.15)
                .ignoresSafeArea()

            Text("CRITICAL HIT!")
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundStyle(.red)
                .scaleEffect(flashCritical ? 1.0 : 2.0)
                .opacity(flashCritical ? 1.0 : 0.0)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - NudgeDecision Helper

private extension NudgeDecision {
    var isFire: Bool {
        if case .fire = self { return true }
        return false
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant55View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant55View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant55View()
        .environmentObject(observer)
}
