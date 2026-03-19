import Combine
import SwiftUI
import PostureLogic

/// Variant 58: Boss Battle — Side-view RPG combat interface where posture maintenance
/// is framed as battling five monsters. Each metric is a monster that awakens when its
/// ratio rises. The worst offender becomes the current "boss".
struct Variant58View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var heroHealth: Float = 1.0
    @State private var flashAttack = false

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private func ratio(for key: MetricKey) -> Float {
        isAbsent ? 0 : observer.data.metric(for: key).clampedRatio
    }

    private var worstKey: MetricKey? {
        observer.data.worstOffender?.key
    }

    // MARK: - Monster Definitions

    private struct MonsterInfo {
        let key: MetricKey
        let name: String
        let color: Color
    }

    private let monsters: [MonsterInfo] = [
        MonsterInfo(key: .forwardCreep, name: "Charger", color: .red),
        MonsterInfo(key: .headDrop, name: "Anvil", color: .orange),
        MonsterInfo(key: .shoulderRounding, name: "Serpent", color: .purple),
        MonsterInfo(key: .lateralLean, name: "Tower", color: .blue),
        MonsterInfo(key: .twist, name: "Vortex", color: .green),
    ]

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hue: 0.7, saturation: 0.2, brightness: 0.08)
                    .ignoresSafeArea()

                if isAbsent {
                    AbsenceOverlay {
                        battleScene(size: geo.size)
                    }
                } else {
                    battleScene(size: geo.size)
                }

                if flashAttack {
                    Color.red.opacity(0.2)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
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
            if observer.data.isAlertMode {
                let damage: Float = 0.005 * (observer.data.worstOffender?.clampedRatio ?? 0.5)
                heroHealth = max(0, heroHealth - damage)
            } else {
                heroHealth = min(1.0, heroHealth + 0.01)
            }
        }
        .onChange(of: observer.data.nudgeDecision.isFire) { _, isFire in
            if isFire {
                heroHealth = max(0, heroHealth - 0.15)
                withAnimation(.easeOut(duration: 0.1)) { flashAttack = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation { flashAttack = false }
                }
            }
        }
    }

    // MARK: - Battle Scene

    private func battleScene(size: CGSize) -> some View {
        VStack(spacing: 0) {
            // Status bar
            statusBar(width: size.width)
                .padding(.top, 40)

            Spacer()

            // Battle field
            HStack(spacing: 0) {
                // Hero side
                heroPanel(size: CGSize(width: size.width * 0.35, height: size.height * 0.5))

                Spacer()

                // Action area
                if observer.data.isAlertMode, let worst = worstKey {
                    actionArea(worstKey: worst)
                }

                Spacer()

                // Monster panel
                monsterPanel(size: CGSize(width: size.width * 0.35, height: size.height * 0.5))
            }
            .padding(.horizontal, 8)

            Spacer()

            // Attack timer
            if let seconds = observer.data.nudgeCountdownSeconds {
                attackBar(seconds: seconds, width: size.width - 48)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Status Bar

    private func statusBar(width: CGFloat) -> some View {
        let defeatedCount = monsters.filter { ratio(for: $0.key) < 0.3 }.count

        return HStack {
            Text("ENEMIES DEFEATED: \(defeatedCount)/5")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(defeatedCount == 5 ? .green : .white.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Hero Panel

    private func heroPanel(size: CGSize) -> some View {
        VStack(spacing: 8) {
            // Hero avatar (knight silhouette)
            Canvas { context, canvasSize in
                drawHero(context: &context, size: canvasSize)
            }
            .frame(width: size.width * 0.6, height: size.height * 0.5)

            // Hero health bar
            VStack(spacing: 2) {
                HStack {
                    Text("HP")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                    Spacer()
                    Text("\(Int(heroHealth * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(width: size.width * 0.7)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: size.width * 0.7, height: 8)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(heroHealth > 0.5 ? .green : heroHealth > 0.25 ? .yellow : .red)
                        .frame(width: size.width * 0.7 * CGFloat(heroHealth), height: 8)
                        .animation(.easeInOut(duration: 0.3), value: heroHealth)
                }
            }

            if heroHealth <= 0 {
                Text("DEFEATED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red)
            }
        }
    }

    private func drawHero(context: inout GraphicsContext, size: CGSize) {
        let cx = size.width / 2
        let baseY = size.height * 0.9

        // Simple shield + sword warrior silhouette
        var path = Path()

        // Head
        let headR = size.width * 0.12
        path.addEllipse(in: CGRect(x: cx - headR, y: baseY - size.height * 0.85 - headR,
                                     width: headR * 2, height: headR * 2))

        // Body
        path.move(to: CGPoint(x: cx, y: baseY - size.height * 0.7))
        path.addLine(to: CGPoint(x: cx - size.width * 0.15, y: baseY - size.height * 0.35))
        path.addLine(to: CGPoint(x: cx + size.width * 0.15, y: baseY - size.height * 0.35))
        path.closeSubpath()

        // Legs
        path.move(to: CGPoint(x: cx - size.width * 0.08, y: baseY - size.height * 0.35))
        path.addLine(to: CGPoint(x: cx - size.width * 0.12, y: baseY))
        path.move(to: CGPoint(x: cx + size.width * 0.08, y: baseY - size.height * 0.35))
        path.addLine(to: CGPoint(x: cx + size.width * 0.12, y: baseY))

        // Shield (left hand)
        let shieldRect = CGRect(x: cx - size.width * 0.35, y: baseY - size.height * 0.6,
                                width: size.width * 0.2, height: size.height * 0.25)
        path.addRoundedRect(in: shieldRect, cornerSize: CGSize(width: 4, height: 4))

        // Sword (right hand) - vertical line
        path.move(to: CGPoint(x: cx + size.width * 0.25, y: baseY - size.height * 0.75))
        path.addLine(to: CGPoint(x: cx + size.width * 0.25, y: baseY - size.height * 0.35))

        let auraColor = heroHealth > 0 ? Color.green.opacity(Double(heroHealth) * 0.3) : Color.clear
        context.fill(Path(ellipseIn: CGRect(x: cx - size.width * 0.3, y: baseY - size.height * 0.7,
                                             width: size.width * 0.6, height: size.height * 0.7)),
                     with: .color(auraColor))
        context.fill(path, with: .color(.white.opacity(0.8)))
        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    // MARK: - Monster Panel

    private func monsterPanel(size: CGSize) -> some View {
        VStack(spacing: 6) {
            ForEach(monsters, id: \.key) { monster in
                let r = ratio(for: monster.key)
                let active = r > 0.3
                let isBoss = worstKey == monster.key && observer.data.isAlertMode

                HStack(spacing: 6) {
                    // Monster icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(active ? monster.color.opacity(0.2) : Color.gray.opacity(0.1))
                            .frame(width: isBoss ? 36 : 28, height: isBoss ? 36 : 28)

                        monsterSymbol(key: monster.key)
                            .font(.system(size: isBoss ? 16 : 12))
                            .foregroundStyle(active ? monster.color : .gray.opacity(0.3))

                        if isBoss {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.yellow)
                                .offset(y: -22)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(active ? monster.name : "DEFEATED")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(active ? .white.opacity(0.8) : .gray.opacity(0.4))

                        if active {
                            // Monster health bar
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: size.width * 0.35, height: 4)

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(monster.color)
                                    .frame(width: size.width * 0.35 * CGFloat(min(r, 1.0)), height: 4)
                            }
                        }
                    }
                }
                .animation(.spring(response: 0.4), value: active)
            }
        }
    }

    private func monsterSymbol(key: MetricKey) -> some View {
        Group {
            switch key {
            case .forwardCreep: Image(systemName: "hare.fill")
            case .headDrop: Image(systemName: "chevron.down.2")
            case .shoulderRounding: Image(systemName: "tornado")
            case .lateralLean: Image(systemName: "building.columns.fill")
            case .twist: Image(systemName: "hurricane")
            }
        }
    }

    // MARK: - Action Area

    private func actionArea(worstKey: MetricKey) -> some View {
        VStack(spacing: 6) {
            Text("BOSS")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.yellow)

            Text(monsters.first { $0.key == worstKey }?.name ?? "")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            Text("CORRECTING...")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.orange.opacity(0.7))
        }
    }

    // MARK: - Attack Bar

    private func attackBar(seconds: TimeInterval, width: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text("INCOMING ATTACK")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.red)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: width, height: 6)

                RoundedRectangle(cornerRadius: 3)
                    .fill(.red)
                    .frame(width: width * min(CGFloat(seconds / 30.0), 1.0), height: 6)
            }

            Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
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
    Variant58View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .bad(since: Date().timeIntervalSince1970 - 10),
        worstMetric: .twist,
        worstRatio: 1.1
    )
    let observer = PostureDisplayObserver(source: source)
    Variant58View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant58View()
        .environmentObject(observer)
}
