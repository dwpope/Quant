import SwiftUI
import PostureLogic

/// Variant 46: Coral Reef — An underwater coral reef scene with five distinct coral formations
/// representing the five metrics. Good posture = vibrant, extended polyps with gentle sway.
/// Bad posture = corals retract, bleach, water darkens. Small particles add life to the scene.
struct Variant46View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    // Coral types mapped to metrics
    private struct CoralConfig {
        let key: MetricKey
        let name: String
        let color: Color
        let fracX: CGFloat
        let fracY: CGFloat
    }

    private let corals: [CoralConfig] = [
        CoralConfig(key: .forwardCreep, name: "Staghorn", color: Color(hue: 0.9, saturation: 0.7, brightness: 0.7), fracX: 0.5, fracY: 0.4),
        CoralConfig(key: .headDrop, name: "Brain", color: Color(hue: 0.08, saturation: 0.8, brightness: 0.75), fracX: 0.3, fracY: 0.5),
        CoralConfig(key: .shoulderRounding, name: "Fan", color: Color(hue: 0.5, saturation: 0.6, brightness: 0.65), fracX: 0.7, fracY: 0.5),
        CoralConfig(key: .lateralLean, name: "Pillar", color: Color(hue: 0.13, saturation: 0.7, brightness: 0.7), fracX: 0.25, fracY: 0.65),
        CoralConfig(key: .twist, name: "Spiral", color: Color(hue: 0.75, saturation: 0.5, brightness: 0.7), fracX: 0.75, fracY: 0.65),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isAbsent {
                    AbsenceOverlay {
                        reefCanvas(size: geo.size)
                    }
                } else {
                    reefCanvas(size: geo.size)
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
    }

    private func reefCanvas(size: CGSize) -> some View {
        let metrics: [MetricKey: Float] = [
            .forwardCreep: isAbsent ? 0 : observer.data.metric(for: .forwardCreep).clampedRatio,
            .headDrop: isAbsent ? 0 : observer.data.metric(for: .headDrop).clampedRatio,
            .shoulderRounding: isAbsent ? 0 : observer.data.metric(for: .shoulderRounding).clampedRatio,
            .lateralLean: isAbsent ? 0 : observer.data.metric(for: .lateralLean).clampedRatio,
            .twist: isAbsent ? 0 : observer.data.metric(for: .twist).clampedRatio,
        ]
        let avgStress = metrics.values.reduce(0, +) / 5
        let worst = observer.data.worstOffender

        return ZStack {
            // Ocean background
            RadialGradient(
                colors: [
                    Color(hue: 0.55, saturation: 0.5, brightness: max(0.15, 0.4 - Double(avgStress) * 0.2)),
                    Color(hue: 0.6, saturation: 0.7, brightness: max(0.08, 0.2 - Double(avgStress) * 0.1))
                ],
                center: .center,
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.8
            )
            .ignoresSafeArea()

            // Murky overlay for bad state
            if avgStress > 0.5 {
                Color.brown.opacity(Double(avgStress - 0.5) * 0.3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isAbsent)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate

                Canvas { context, canvasSize in
                    let s = min(canvasSize.width, canvasSize.height) * 0.003

                    // --- Plankton particles ---
                    let particleCount = avgStress > 0.7 ? 15 : 25
                    for i in 0..<particleCount {
                        let phase = Double(i) * 1.7
                        let px = (sin(now * 0.3 + phase) * 0.5 + 0.5) * canvasSize.width
                        let py = (cos(now * 0.2 + phase * 0.7) * 0.5 + 0.5) * canvasSize.height
                        let particleColor: Color = avgStress > 0.7
                            ? Color(hue: 0.08, saturation: 0.5, brightness: 0.4) // sediment
                            : .white
                        context.fill(
                            Path(ellipseIn: CGRect(x: px - 1.5, y: py - 1.5, width: 3, height: 3)),
                            with: .color(particleColor.opacity(0.3))
                        )
                    }

                    // --- Draw each coral ---
                    for coral in corals {
                        let ratio = metrics[coral.key] ?? 0
                        let isWorst = worst?.key == coral.key
                        let cx = canvasSize.width * coral.fracX
                        let cy = canvasSize.height * coral.fracY
                        let sway = sin(now * 1.5 + Double(coral.fracX) * 5) * 3 * s * Double(1 - ratio)

                        // Bleaching: reduce saturation toward 0
                        let bleachSat = max(0.1, 1.0 - Double(ratio) * 0.8)
                        let coralColor = coral.color.opacity(bleachSat)

                        switch coral.key {
                        case .forwardCreep:
                            // Staghorn: branching coral that retracts
                            drawStaghorn(context: context, cx: cx + sway, cy: cy,
                                         ratio: CGFloat(ratio), color: coralColor, scale: s)
                        case .headDrop:
                            // Brain coral: dome that flattens
                            drawBrainCoral(context: context, cx: cx + sway, cy: cy,
                                           ratio: CGFloat(ratio), color: coralColor, scale: s)
                        case .shoulderRounding:
                            // Fan coral: folds shut
                            drawFanCoral(context: context, cx: cx + sway, cy: cy,
                                         ratio: CGFloat(ratio), color: coralColor, scale: s)
                        case .lateralLean:
                            // Pillar coral: tilts
                            drawPillarCoral(context: context, cx: cx + sway, cy: cy,
                                            ratio: CGFloat(ratio), color: coralColor, scale: s)
                        case .twist:
                            // Spiral coral: tightens
                            drawSpiralCoral(context: context, cx: cx + sway, cy: cy,
                                            ratio: CGFloat(ratio), color: coralColor, scale: s, time: now)
                        }

                        // Warning halo for worst offender
                        if isWorst && ratio > 0.3 {
                            let haloRadius: CGFloat = 25 * s + sin(now * 3) * 3 * s
                            context.stroke(
                                Path(ellipseIn: CGRect(x: cx - haloRadius, y: cy - haloRadius,
                                                        width: haloRadius * 2, height: haloRadius * 2)),
                                with: .color(.red.opacity(0.3 + sin(now * 2) * 0.1)),
                                style: StrokeStyle(lineWidth: 2)
                            )
                        }

                        // Label
                        context.draw(
                            Text(coral.name).font(.system(size: 6 * s, weight: .light))
                                .foregroundColor(.white.opacity(0.4)),
                            at: CGPoint(x: cx, y: cy + 25 * s)
                        )
                    }

                    // --- Oxygen meter (nudge countdown) ---
                    if let seconds = observer.data.nudgeCountdownSeconds {
                        let maxSeconds: Double = 30
                        let fill = min(seconds / maxSeconds, 1.0)
                        let meterX = canvasSize.width - 20 * s
                        let meterTop = canvasSize.height * 0.3
                        let meterH: CGFloat = 80 * s
                        let meterW: CGFloat = 10 * s

                        // Outline
                        let meterRect = CGRect(x: meterX - meterW / 2, y: meterTop, width: meterW, height: meterH)
                        context.stroke(Path(roundedRect: meterRect, cornerRadius: meterW / 2),
                                       with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 1))

                        // Fill
                        let fillH = meterH * CGFloat(fill)
                        let fillRect = CGRect(x: meterX - meterW / 2 + 1, y: meterTop + meterH - fillH,
                                              width: meterW - 2, height: fillH)
                        context.fill(Path(roundedRect: fillRect, cornerRadius: (meterW - 2) / 2),
                                     with: .color(.cyan.opacity(0.6)))

                        // O2 label
                        context.draw(
                            Text("O₂").font(.system(size: 6 * s, weight: .bold)).foregroundColor(.cyan.opacity(0.5)),
                            at: CGPoint(x: meterX, y: meterTop - 8 * s)
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Alert overlay
            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                VStack {
                    Spacer()
                    Text(worst.key.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.5)))

                    if let seconds = observer.data.nudgeCountdownSeconds {
                        Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Coral Drawing

    private func drawStaghorn(context: GraphicsContext, cx: CGFloat, cy: CGFloat,
                               ratio: CGFloat, color: Color, scale s: CGFloat) {
        // Branching coral: branches retract inward with ratio
        let branchLen: CGFloat = 20 * s * (1.0 - ratio * 0.6)
        let baseWidth: CGFloat = 4 * s

        // Central trunk
        var trunk = Path()
        trunk.move(to: CGPoint(x: cx, y: cy + 10 * s))
        trunk.addLine(to: CGPoint(x: cx, y: cy - branchLen))
        context.stroke(trunk, with: .color(color), style: StrokeStyle(lineWidth: baseWidth, lineCap: .round))

        // Branches
        for angle in [-0.6, -0.3, 0.3, 0.6] as [CGFloat] {
            let branchY = cy - branchLen * 0.4 + angle * 8 * s
            var branch = Path()
            branch.move(to: CGPoint(x: cx, y: branchY))
            branch.addLine(to: CGPoint(x: cx + branchLen * sin(angle) * (1.0 - ratio * 0.5),
                                        y: branchY - branchLen * 0.4 * cos(angle)))
            context.stroke(branch, with: .color(color.opacity(0.8)),
                           style: StrokeStyle(lineWidth: baseWidth * 0.6, lineCap: .round))
        }
    }

    private func drawBrainCoral(context: GraphicsContext, cx: CGFloat, cy: CGFloat,
                                 ratio: CGFloat, color: Color, scale s: CGFloat) {
        // Dome that flattens and loses texture
        let domeW: CGFloat = 22 * s
        let domeH: CGFloat = 16 * s * (1.0 - ratio * 0.5)

        context.fill(
            Path(ellipseIn: CGRect(x: cx - domeW, y: cy - domeH, width: domeW * 2, height: domeH * 2)),
            with: .color(color)
        )

        // Concentric wrinkle lines
        let wrinkleCount = max(1, Int((1.0 - ratio) * 4))
        for i in 0..<wrinkleCount {
            let frac = CGFloat(i + 1) / CGFloat(wrinkleCount + 1)
            let r = domeW * frac
            let h = domeH * frac
            context.stroke(
                Path(ellipseIn: CGRect(x: cx - r, y: cy - h, width: r * 2, height: h * 2)),
                with: .color(color.opacity(0.4)),
                style: StrokeStyle(lineWidth: 0.8)
            )
        }
    }

    private func drawFanCoral(context: GraphicsContext, cx: CGFloat, cy: CGFloat,
                               ratio: CGFloat, color: Color, scale s: CGFloat) {
        // Fan that folds shut (width decreases with ratio)
        let fanW: CGFloat = 20 * s * (1.0 - ratio * 0.7)
        let fanH: CGFloat = 25 * s

        var fan = Path()
        fan.move(to: CGPoint(x: cx, y: cy + fanH * 0.3))
        fan.addLine(to: CGPoint(x: cx - fanW, y: cy - fanH * 0.7))
        fan.addQuadCurve(to: CGPoint(x: cx + fanW, y: cy - fanH * 0.7),
                         control: CGPoint(x: cx, y: cy - fanH))
        fan.closeSubpath()
        context.fill(fan, with: .color(color.opacity(0.6)))
        context.stroke(fan, with: .color(color), style: StrokeStyle(lineWidth: 1.5))

        // Internal lattice
        if fanW > 5 * s {
            let gridCount = 4
            for i in 1..<gridCount {
                let frac = CGFloat(i) / CGFloat(gridCount)
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: cx - fanW * (1 - frac), y: cy - fanH * 0.7 + fanH * frac * 0.3))
                gridLine.addLine(to: CGPoint(x: cx + fanW * (1 - frac), y: cy - fanH * 0.7 + fanH * frac * 0.3))
                context.stroke(gridLine, with: .color(color.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5))
            }
        }
    }

    private func drawPillarCoral(context: GraphicsContext, cx: CGFloat, cy: CGFloat,
                                  ratio: CGFloat, color: Color, scale s: CGFloat) {
        // Pillar that tilts with ratio
        let pillarW: CGFloat = 8 * s
        let pillarH: CGFloat = 30 * s
        let tilt = ratio * 12 * s

        var pillar = Path()
        pillar.move(to: CGPoint(x: cx - pillarW / 2, y: cy + pillarH * 0.3))
        pillar.addLine(to: CGPoint(x: cx - pillarW / 2 + tilt, y: cy - pillarH * 0.7))
        pillar.addLine(to: CGPoint(x: cx + pillarW / 2 + tilt, y: cy - pillarH * 0.7))
        pillar.addLine(to: CGPoint(x: cx + pillarW / 2, y: cy + pillarH * 0.3))
        pillar.closeSubpath()
        context.fill(pillar, with: .color(color))

        // Fracture lines when tilting
        if ratio > 0.4 {
            let fractureCount = Int(ratio * 3)
            for i in 0..<fractureCount {
                let fy = cy - pillarH * 0.3 + CGFloat(i) * pillarH * 0.2
                let fx = cx + tilt * CGFloat(i) / 3
                var fracture = Path()
                fracture.move(to: CGPoint(x: fx - 3 * s, y: fy))
                fracture.addLine(to: CGPoint(x: fx + 3 * s, y: fy))
                context.stroke(fracture, with: .color(.white.opacity(Double(ratio) * 0.5)),
                               style: StrokeStyle(lineWidth: 0.8))
            }
        }
    }

    private func drawSpiralCoral(context: GraphicsContext, cx: CGFloat, cy: CGFloat,
                                  ratio: CGFloat, color: Color, scale s: CGFloat, time: TimeInterval) {
        // Spiral that tightens with ratio
        let coils = 3
        let maxR: CGFloat = 18 * s
        let tightness = 1.0 + ratio * 2.0 // Coils wind tighter
        let rotSpeed = 0.5 + Double(ratio) * 1.5

        var spiral = Path()
        let steps = 60
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps) * CGFloat(coils) * .pi * 2
            let r = maxR * (1.0 - CGFloat(step) / CGFloat(steps) * 0.7) / tightness
            let angle = t + CGFloat(time * rotSpeed)
            let px = cx + r * cos(angle)
            let py = cy + r * sin(angle) * 0.6
            if step == 0 { spiral.move(to: CGPoint(x: px, y: py)) }
            else { spiral.addLine(to: CGPoint(x: px, y: py)) }
        }
        context.stroke(spiral, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant46View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant46View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant46View()
        .environmentObject(observer)
}
