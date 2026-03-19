import SwiftUI
import PostureLogic

/// Variant 54: Starfield — First-person starfield with 200 deterministic stars expanding from
/// a vanishing point. Posture metrics drive speed, vanishing point position, FOV, rotation,
/// and streak length. HUD-style metric labels in corners with a "SHIELDS" countdown bar.
struct Variant54View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    // MARK: - Metric Accessors

    private func ratio(for key: MetricKey) -> Float {
        isAbsent ? 0 : observer.data.metric(for: key).clampedRatio
    }

    private var avgStress: Float {
        MetricKey.allCases.map { ratio(for: $0) }.reduce(0, +) / 5
    }

    // MARK: - Star Data

    private struct Star {
        let id: Int
        /// Angle from vanishing point (radians)
        let angle: Double
        /// Base distance fraction from center (0-1)
        let depthSeed: Double
        let brightness: Double
    }

    /// Deterministic star positions generated from seed values.
    private static let stars: [Star] = {
        var result: [Star] = []
        for i in 0..<200 {
            let angleSeed = Double(i) * 1.618033988749 * .pi * 2
            let angle = angleSeed.truncatingRemainder(dividingBy: .pi * 2)
            let depthSeed = (sin(Double(i) * 3.7) * 0.5 + 0.5)
            let brightness = 0.3 + (cos(Double(i) * 2.3) * 0.5 + 0.5) * 0.7
            result.append(Star(id: i, angle: angle, depthSeed: depthSeed, brightness: brightness))
        }
        return result
    }()

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isAbsent {
                    AbsenceOverlay {
                        starfieldContent(size: geo.size)
                    }
                } else {
                    starfieldContent(size: geo.size)
                }

                settingsButton
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
        }
        .animation(PostureAnimations.alertOnset, value: observer.data.isAlertMode)
    }

    private var settingsButton: some View {
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

    // MARK: - Starfield Content

    private func starfieldContent(size: CGSize) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            starfieldCanvas(size: size)
            peripheralDarkening(size: size)
            reticle(size: size)
            hudOverlay(size: size)
            shieldsBar(size: size)
            cautionLabel
        }
    }

    // MARK: - Starfield Canvas

    private func starfieldCanvas(size: CGSize) -> some View {
        let fc = ratio(for: .forwardCreep)
        let hd = ratio(for: .headDrop)
        let ll = ratio(for: .lateralLean)
        let tw = ratio(for: .twist)
        let speed = 0.3 + Double(fc) * 1.5
        let stars = Self.stars

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isAbsent)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, canvasSize in
                let vpX = canvasSize.width * (0.5 + CGFloat(ll) * 0.25)
                let vpY = canvasSize.height * (0.4 + CGFloat(hd) * 0.2)
                let maxRadius = max(canvasSize.width, canvasSize.height) * 0.7
                let twistAngle = Double(tw) * 0.5

                drawStars(
                    context: &context,
                    stars: stars,
                    canvasSize: canvasSize,
                    vpX: vpX, vpY: vpY,
                    maxRadius: maxRadius,
                    time: now,
                    speed: speed,
                    twistAngle: twistAngle,
                    streakFactor: fc
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func drawStars(
        context: inout GraphicsContext,
        stars: [Star],
        canvasSize: CGSize,
        vpX: CGFloat, vpY: CGFloat,
        maxRadius: CGFloat,
        time: TimeInterval,
        speed: Double,
        twistAngle: Double,
        streakFactor: Float
    ) {
        for star in stars {
            // Depth cycles over time with speed
            let rawDepth = (star.depthSeed + time * speed * 0.1)
                .truncatingRemainder(dividingBy: 1.0)
            let depth = max(0.01, rawDepth)

            let angle = star.angle + twistAngle * depth
            let dist = depth * maxRadius

            let sx = vpX + dist * cos(angle)
            let sy = vpY + dist * sin(angle)

            guard sx > -10, sx < canvasSize.width + 10,
                  sy > -10, sy < canvasSize.height + 10 else { continue }

            let size = 1.0 + depth * 2.5
            let opacity = star.brightness * min(depth * 2, 1.0)

            // Motion-blur streaks when speed is high
            let streakLen = CGFloat(streakFactor) * depth * 15
            if streakLen > 1 {
                var streak = Path()
                let dx = cos(angle) * streakLen
                let dy = sin(angle) * streakLen
                streak.move(to: CGPoint(x: sx - dx, y: sy - dy))
                streak.addLine(to: CGPoint(x: sx, y: sy))
                context.stroke(
                    streak,
                    with: .color(.white.opacity(opacity * 0.6)),
                    style: StrokeStyle(lineWidth: size * 0.5, lineCap: .round)
                )
            }

            // Star point
            let rect = CGRect(x: sx - size / 2, y: sy - size / 2, width: size, height: size)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
        }
    }

    // MARK: - Peripheral Darkening (FOV)

    private func peripheralDarkening(size: CGSize) -> some View {
        let sr = ratio(for: .shoulderRounding)
        let vignetteStrength = 0.3 + Double(sr) * 0.5

        return RadialGradient(
            colors: [.clear, Color.black.opacity(vignetteStrength)],
            center: .center,
            startRadius: min(size.width, size.height) * (0.35 - CGFloat(sr) * 0.15),
            endRadius: max(size.width, size.height) * 0.55
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Reticle

    private func reticle(size: CGSize) -> some View {
        let ll = ratio(for: .lateralLean)
        let hd = ratio(for: .headDrop)
        let cx = size.width * (0.5 + CGFloat(ll) * 0.25)
        let cy = size.height * (0.4 + CGFloat(hd) * 0.2)

        return Canvas { context, canvasSize in
            let armLen: CGFloat = 12
            let gap: CGFloat = 4

            var crosshair = Path()
            // Horizontal arms
            crosshair.move(to: CGPoint(x: cx - armLen - gap, y: cy))
            crosshair.addLine(to: CGPoint(x: cx - gap, y: cy))
            crosshair.move(to: CGPoint(x: cx + gap, y: cy))
            crosshair.addLine(to: CGPoint(x: cx + armLen + gap, y: cy))
            // Vertical arms
            crosshair.move(to: CGPoint(x: cx, y: cy - armLen - gap))
            crosshair.addLine(to: CGPoint(x: cx, y: cy - gap))
            crosshair.move(to: CGPoint(x: cx, y: cy + gap))
            crosshair.addLine(to: CGPoint(x: cx, y: cy + armLen + gap))

            context.stroke(
                crosshair,
                with: .color(.white.opacity(0.4)),
                style: StrokeStyle(lineWidth: 1, lineCap: .round)
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - HUD Overlay

    private func hudOverlay(size: CGSize) -> some View {
        VStack {
            HStack(alignment: .top) {
                hudLabel(key: .forwardCreep, alignment: .leading)
                Spacer()
                hudLabel(key: .headDrop, alignment: .trailing)
            }
            Spacer()
            HStack(alignment: .bottom) {
                hudLabel(key: .shoulderRounding, alignment: .leading)
                Spacer()
                hudLabel(key: .twist, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 50)
    }

    private func hudLabel(key: MetricKey, alignment: HorizontalAlignment) -> some View {
        let r = ratio(for: key)
        let color = PostureVisualStyle.metricColor(ratio: r)
        let barWidth: CGFloat = 50
        let fillWidth = barWidth * CGFloat(r)

        return VStack(alignment: alignment, spacing: 3) {
            Text(key.displayName.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color.opacity(0.8))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: barWidth, height: 4)

                Capsule()
                    .fill(color)
                    .frame(width: max(2, fillWidth), height: 4)
            }
        }
    }

    // MARK: - Lateral Lean HUD (center-bottom)

    private var cautionLabel: some View {
        Group {
            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                VStack {
                    HStack(spacing: 4) {
                        Text("CAUTION:")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.red)
                        Text(worst.key.displayName.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.yellow)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.5), in: Capsule())

                    Spacer()
                }
                .padding(.top, 80)
            }
        }
    }

    // MARK: - Shields Bar

    private func shieldsBar(size: CGSize) -> some View {
        Group {
            if let seconds = observer.data.nudgeCountdownSeconds {
                shieldsCountdown(seconds: seconds, width: size.width)
            }
        }
    }

    private func shieldsCountdown(seconds: TimeInterval, width: CGFloat) -> some View {
        let maxSeconds: Double = 30
        let fraction = min(seconds / maxSeconds, 1.0)

        return VStack(spacing: 4) {
            Spacer()

            HStack(spacing: 6) {
                Text("SHIELDS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan.opacity(0.7))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: width * 0.5, height: 6)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width * 0.5 * fraction, height: 6)
                }

                Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant54View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant54View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant54View()
        .environmentObject(observer)
}
