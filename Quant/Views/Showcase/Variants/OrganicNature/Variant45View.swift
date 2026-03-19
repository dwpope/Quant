import SwiftUI
import PostureLogic

// MARK: - Rain Drop Model

struct RainDrop: Identifiable {
    let id: Int
    var x: CGFloat
    var y: CGFloat
    var speed: CGFloat
    var length: CGFloat

    mutating func update(dt: CGFloat, viewHeight: CGFloat, windAngle: CGFloat) {
        y += speed * dt
        x += windAngle * speed * dt * 0.3
        if y > viewHeight + 20 {
            y = CGFloat.random(in: -40 ... -10)
            x = CGFloat.random(in: 0...400)
        }
    }

    /// Whether the drop is within visible bounds (with margin).
    var isInBounds: Bool { y >= -40 }
}

// MARK: - Weather Drawing Helpers

private enum WeatherDraw {
    static func drawSun(context: inout GraphicsContext, sunX: CGFloat, sunY: CGFloat,
                        radius: CGFloat, opacity: Double, now: TimeInterval) {
        guard opacity > 0.01 else { return }
        let sunColor = Color(hue: 0.12, saturation: 0.9, brightness: 0.95).opacity(opacity)
        let rect = CGRect(x: sunX - radius, y: sunY - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(sunColor))

        let rayCount = 12
        let rayRotation = CGFloat(now * 0.2)
        let innerR = radius * 1.2
        let outerR = radius * 1.8
        let rayColor = Color.yellow.opacity(opacity * 0.5)
        for i in 0..<rayCount {
            let angle = CGFloat(i) * .pi * 2 / CGFloat(rayCount) + rayRotation
            var ray = Path()
            ray.move(to: CGPoint(x: sunX + innerR * cos(angle), y: sunY + innerR * sin(angle)))
            ray.addLine(to: CGPoint(x: sunX + outerR * cos(angle), y: sunY + outerR * sin(angle)))
            context.stroke(ray, with: .color(rayColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }

    static func drawCloud(context: inout GraphicsContext, x: CGFloat, y: CGFloat,
                           width: CGFloat, thickness: CGFloat, darkness: Double, label: String, s: CGFloat) {
        let cloudColor = Color(white: 1.0 - darkness).opacity(0.5 + darkness * 0.3)
        for j in 0..<3 {
            let cx = x + CGFloat(j - 1) * width * 0.3
            let w: CGFloat = width * (j == 1 ? 1.0 : 0.7)
            let h: CGFloat = thickness * (j == 1 ? 1.0 : 0.7)
            let rect = CGRect(x: cx - w / 2, y: y - h / 2, width: w, height: h)
            context.fill(Path(ellipseIn: rect), with: .color(cloudColor))
        }
        let labelPt = CGPoint(x: x, y: y + thickness / 2 + 6 * s)
        context.draw(
            Text(label).font(.system(size: 6 * s, weight: .light)).foregroundColor(.secondary.opacity(0.4)),
            at: labelPt
        )
    }

    static func drawRain(context: inout GraphicsContext, drops: [RainDrop], activeCount: Int,
                          windAngle: CGFloat, hdRatio: Float) {
        let rainColor = Color.white.opacity(0.3 + Double(hdRatio) * 0.3)
        let lineWidth: CGFloat = 0.8 + CGFloat(hdRatio)
        for i in 0..<min(activeCount, drops.count) {
            let drop = drops[i]
            let lineLen = drop.length * (1 + CGFloat(hdRatio) * 2)
            var dropPath = Path()
            dropPath.move(to: CGPoint(x: drop.x, y: drop.y))
            dropPath.addLine(to: CGPoint(x: drop.x + windAngle * lineLen * 0.3, y: drop.y + lineLen))
            context.stroke(dropPath, with: .color(rainColor), style: StrokeStyle(lineWidth: lineWidth))
        }
    }

    static func drawFog(context: inout GraphicsContext, fc: Float, canvasSize: CGSize) {
        guard fc > 0.1 else { return }
        let fogHeight = canvasSize.height * CGFloat(fc) * 0.6
        let fogRect = CGRect(x: 0, y: canvasSize.height - fogHeight, width: canvasSize.width, height: fogHeight)
        context.fill(Path(fogRect), with: .color(.white.opacity(Double(fc) * 0.35)))
    }

    static func drawLightning(context: inout GraphicsContext, opacity: Double, tw: Float,
                               canvasSize: CGSize, s: CGFloat) {
        guard opacity > 0.01, tw > 0.2 else { return }
        let boltX = canvasSize.width * 0.5
        let boltTop = canvasSize.height * 0.2
        let boltBottom = canvasSize.height * 0.6
        var bolt = Path()
        bolt.move(to: CGPoint(x: boltX, y: boltTop))
        var y = boltTop
        var toggle: CGFloat = 1
        while y < boltBottom {
            y += 20 * s
            let jag = toggle * 10 * s
            toggle *= -1
            bolt.addLine(to: CGPoint(x: boltX + jag, y: min(y, boltBottom)))
        }
        context.stroke(bolt, with: .color(.white.opacity(opacity)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    static func drawGauge(context: inout GraphicsContext, seconds: TimeInterval,
                           canvasSize: CGSize, s: CGFloat) {
        let gaugeX = canvasSize.width - 35 * s
        let gaugeY = canvasSize.height - 40 * s
        let gaugeR: CGFloat = 20 * s
        let maxSeconds: Double = 30
        let progress = 1.0 - min(seconds / maxSeconds, 1.0)

        var arc = Path()
        arc.addArc(center: CGPoint(x: gaugeX, y: gaugeY), radius: gaugeR,
                   startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        context.stroke(arc, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 2))

        let needleAngle: CGFloat = .pi - (.pi * progress)
        var needle = Path()
        needle.move(to: CGPoint(x: gaugeX, y: gaugeY))
        needle.addLine(to: CGPoint(x: gaugeX + gaugeR * 0.8 * cos(needleAngle),
                                    y: gaugeY - gaugeR * 0.8 * sin(needleAngle)))
        context.stroke(needle, with: .color(.red.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }
}

/// Variant 45: Weather System — A dynamic sky scene reflecting overall posture quality as weather.
/// Good posture = clear blue sky with gentle sun. Bad posture = clouds darken, fog rolls in,
/// rain falls, and lightning flickers. Each metric maps to a different weather phenomenon.
struct Variant45View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var rainDrops: [RainDrop] = []
    @State private var lightningOpacity: Double = 0
    @State private var lightningTimer: Timer?

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isAbsent {
                    AbsenceOverlay {
                        weatherContent(size: geo.size)
                    }
                } else {
                    weatherContent(size: geo.size)
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
        .onAppear { initRainDrops() }
        .onDisappear { lightningTimer?.invalidate() }
    }

    private func weatherContent(size: CGSize) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio
        let avgStress: CGFloat = (CGFloat(fc) + CGFloat(hd) + CGFloat(sr) + CGFloat(ll) + CGFloat(tw)) / 5

        let skyTopColor = Color(hue: 0.58,
                                saturation: max(0.2, 0.8 - Double(avgStress) * 0.7),
                                brightness: max(0.15, 0.55 - Double(avgStress) * 0.4))
        let skyBottomColor = Color(hue: 0.1,
                                   saturation: max(0.1, 0.3 - Double(avgStress) * 0.2),
                                   brightness: max(0.2, 0.6 - Double(avgStress) * 0.3))

        return WeatherContentView(
            skyTopColor: skyTopColor,
            skyBottomColor: skyBottomColor,
            fc: fc, hd: hd, sr: sr, ll: ll, tw: tw,
            avgStress: avgStress,
            rainDrops: $rainDrops,
            lightningOpacity: lightningOpacity,
            nudgeSeconds: observer.data.nudgeCountdownSeconds,
            isAlertMode: observer.data.isAlertMode,
            worstOffender: observer.data.worstOffender,
            postureState: observer.data.postureState,
            isAbsent: isAbsent
        )
        .onChange(of: tw) { _, newTw in
            updateLightningTimer(twistRatio: newTw)
        }
    }

    private func initRainDrops() {
        rainDrops = (0..<60).map { i in
            RainDrop(
                id: i,
                x: CGFloat.random(in: 0...400),
                y: CGFloat.random(in: -200...600),
                speed: CGFloat.random(in: 3...8),
                length: CGFloat.random(in: 5...15)
            )
        }
    }

    private func updateLightningTimer(twistRatio: Float) {
        lightningTimer?.invalidate()
        guard twistRatio > 0.2 else {
            lightningOpacity = 0
            return
        }
        let interval = max(0.5, 3.0 - Double(twistRatio) * 2.5)
        lightningTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                lightningOpacity = 1.0
                withAnimation(.easeOut(duration: 0.2)) {
                    lightningOpacity = 0
                }
            }
        }
    }
}

// MARK: - Weather Content (extracted for type-checker)

private struct WeatherContentView: View {
    let skyTopColor: Color
    let skyBottomColor: Color
    let fc: Float
    let hd: Float
    let sr: Float
    let ll: Float
    let tw: Float
    let avgStress: CGFloat
    @Binding var rainDrops: [RainDrop]
    let lightningOpacity: Double
    let nudgeSeconds: TimeInterval?
    let isAlertMode: Bool
    let worstOffender: MetricInfo?
    let postureState: PostureState
    let isAbsent: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [skyTopColor, skyBottomColor], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isAbsent)) { timeline in
                weatherCanvas(now: timeline.date.timeIntervalSinceReferenceDate)
            }

            lightningFlash

            alertOverlay
        }
    }

    private func weatherCanvas(now: TimeInterval) -> some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height) * 0.003
            let windAngle = CGFloat(ll) * 0.4

            // Sun
            let sunX = canvasSize.width * 0.7 - CGFloat(ll) * 30 * s
            let sunY = canvasSize.height * 0.15
            let sunOpacity = max(0.0, 1.0 - Double(avgStress) * 1.5)
            WeatherDraw.drawSun(context: &context, sunX: sunX, sunY: sunY,
                                radius: 25 * s, opacity: sunOpacity, now: now)

            // Clouds
            let cloudNames = ["FWD", "HEAD", "SHLD", "LEAN", "TWST"]
            let cloudRatios: [Float] = [fc, hd, sr, ll, tw]
            let cloudBaseY: [CGFloat] = [0.2, 0.25, 0.22, 0.28, 0.24]
            for idx in 0..<5 {
                let ratio = cloudRatios[idx]
                let cloudX = canvasSize.width * (CGFloat(idx) + 0.5) / 5 +
                             CGFloat(sin(now * 0.1 + Double(idx) * 1.5)) * 15 * s
                let cloudY = canvasSize.height * cloudBaseY[idx]
                let thickness = 5 * s + CGFloat(ratio) * 25 * s
                let cloudWidth = 40 * s + CGFloat(ratio) * 20 * s
                let darkness = min(1.0, Double(ratio) * 0.8)
                WeatherDraw.drawCloud(context: &context, x: cloudX, y: cloudY,
                                      width: cloudWidth, thickness: thickness,
                                      darkness: darkness, label: cloudNames[idx], s: s)
            }

            // Rain
            let activeDropCount = Int(CGFloat(hd) * CGFloat(rainDrops.count))
            WeatherDraw.drawRain(context: &context, drops: rainDrops, activeCount: activeDropCount,
                                 windAngle: windAngle, hdRatio: hd)

            // Update rain positions
            let dt: CGFloat = 2.0 // pre-scaled
            for i in 0..<rainDrops.count {
                rainDrops[i].update(dt: dt, viewHeight: canvasSize.height, windAngle: windAngle)
            }

            // Fog
            WeatherDraw.drawFog(context: &context, fc: fc, canvasSize: canvasSize)

            // Lightning
            WeatherDraw.drawLightning(context: &context, opacity: lightningOpacity, tw: tw,
                                       canvasSize: canvasSize, s: s)

            // Horizon
            var horizonPath = Path()
            horizonPath.move(to: CGPoint(x: 0, y: canvasSize.height * 0.75))
            horizonPath.addLine(to: CGPoint(x: canvasSize.width, y: canvasSize.height * 0.75))
            context.stroke(horizonPath, with: .color(.secondary.opacity(0.15)), style: StrokeStyle(lineWidth: 0.5))

            // Gauge
            if let seconds = nudgeSeconds {
                WeatherDraw.drawGauge(context: &context, seconds: seconds, canvasSize: canvasSize, s: s)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var lightningFlash: some View {
        if lightningOpacity > 0.01 {
            Color.white.opacity(lightningOpacity * 0.15)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var alertOverlay: some View {
        if isAlertMode, let worst = worstOffender {
            VStack {
                Spacer()
                Text(worst.key.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(PostureVisualStyle.stateColor(for: postureState))

                if let seconds = nudgeSeconds {
                    Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant45View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.9
    )
    let observer = PostureDisplayObserver(source: source)
    Variant45View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant45View()
        .environmentObject(observer)
}
