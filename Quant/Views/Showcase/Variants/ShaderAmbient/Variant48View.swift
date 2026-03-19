import SwiftUI
import PostureLogic

// MARK: - Metric Ratios

/// Snapshot of all five metric ratios for flow field calculations.
private struct FlowMetrics {
    let forwardCreep: Double
    let headDrop: Double
    let shoulderRounding: Double
    let lateralLean: Double
    let twist: Double

    var average: Double {
        (forwardCreep + headDrop + shoulderRounding + lateralLean + twist) / 5
    }
}

// MARK: - Sensor Node

/// Positioned sensor node displayed in the flow field.
private struct SensorNode {
    let key: MetricKey
    let fracX: CGFloat
    let fracY: CGFloat
}

private let sensorNodes: [SensorNode] = [
    SensorNode(key: .forwardCreep, fracX: 0.5, fracY: 0.5),
    SensorNode(key: .headDrop, fracX: 0.5, fracY: 0.22),
    SensorNode(key: .shoulderRounding, fracX: 0.18, fracY: 0.5),
    SensorNode(key: .lateralLean, fracX: 0.82, fracY: 0.5),
    SensorNode(key: .twist, fracX: 0.5, fracY: 0.78),
]

/// Variant 48: Turbulent Flow — Fluid dynamics particle flow visualization.
/// ~150 particles flow left-to-right with disruptions per metric. Color trails range
/// from cool blue (slow) to warm red (fast). Five sensor node circles are positioned in the flow.
struct Variant48View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false

    private let particleCount = 150

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
                        flowContent(size: geo.size)
                    }
                } else {
                    flowContent(size: geo.size)
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

    // MARK: - Flow Content

    private func flowContent(size: CGSize) -> some View {
        ZStack {
            flowBackground()

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isAbsent)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let metrics = currentMetrics()

                Canvas { context, canvasSize in
                    drawParticles(context: context, size: canvasSize, metrics: metrics, time: time)
                    drawSensorNodes(context: context, size: canvasSize)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            alertOverlay()
        }
    }

    // MARK: - Background

    private func flowBackground() -> some View {
        LinearGradient(
            colors: [
                Color(hue: 0.62, saturation: 0.7, brightness: 0.06),
                Color(hue: 0.65, saturation: 0.8, brightness: 0.08),
                Color(hue: 0.60, saturation: 0.6, brightness: 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Metrics Snapshot

    private func currentMetrics() -> FlowMetrics {
        guard !isAbsent else {
            return FlowMetrics(forwardCreep: 0, headDrop: 0, shoulderRounding: 0, lateralLean: 0, twist: 0)
        }
        return FlowMetrics(
            forwardCreep: Double(observer.data.metric(for: .forwardCreep).clampedRatio),
            headDrop: Double(observer.data.metric(for: .headDrop).clampedRatio),
            shoulderRounding: Double(observer.data.metric(for: .shoulderRounding).clampedRatio),
            lateralLean: Double(observer.data.metric(for: .lateralLean).clampedRatio),
            twist: Double(observer.data.metric(for: .twist).clampedRatio)
        )
    }

    // MARK: - Draw Particles

    /// Each particle position is computed deterministically from its seed and the current time.
    /// The particle wraps horizontally and has a cyclic lifetime for fade in/out.
    private func drawParticles(
        context: GraphicsContext, size: CGSize, metrics: FlowMetrics, time: TimeInterval
    ) {
        for i in 0..<particleCount {
            drawSingleParticle(context: context, size: size, metrics: metrics, time: time, index: i)
        }
    }

    private func drawSingleParticle(
        context: GraphicsContext, size: CGSize, metrics: FlowMetrics, time: TimeInterval, index: Int
    ) {
        let seed = Double(index)
        let period = 4.0 + fract(seed * 0.317) * 4.0 // 4-8 second cycle
        let phase = fract(seed * 0.713)

        // Cyclic time within this particle's period
        let t = fract((time / period) + phase)
        let baseY = fract(seed * 0.5917 + seed * 0.0037)

        // Base position: left-to-right flow
        var px = t
        var py = baseY

        // Apply flow disruptions at this position
        let flow = flowDisplacement(x: px, y: py, metrics: metrics, time: time, seed: seed)
        px += flow.0
        py += flow.1

        // Wrap and clamp
        px = fract(px + 1.0)
        py = max(0, min(1, py))

        // Speed estimate from displacement magnitude
        let speed = sqrt(flow.0 * flow.0 + flow.1 * flow.1)

        // Fade in/out at start and end of cycle
        let fade = min(t * 5, (1 - t) * 5, 1.0)

        drawParticleDot(context: context, size: size, px: px, py: py, speed: speed, fade: fade)
    }

    private func drawParticleDot(
        context: GraphicsContext, size: CGSize,
        px: Double, py: Double, speed: Double, fade: Double
    ) {
        let screenX = px * size.width
        let screenY = py * size.height

        // Color: cool blue (slow) to warm red (fast)
        let colorT = min(speed / 0.15, 1.0)
        let hue = 0.6 - colorT * 0.6
        let color = Color(hue: max(0, hue), saturation: 0.7, brightness: 0.8)

        let r: CGFloat = 2.0 + CGFloat(speed) * 12
        context.fill(
            Path(ellipseIn: CGRect(x: screenX - r, y: screenY - r, width: r * 2, height: r * 2)),
            with: .color(color.opacity(fade * 0.65))
        )
    }

    // MARK: - Flow Displacement

    /// Computes displacement from the base trajectory based on metric-driven flow disruptions.
    private func flowDisplacement(
        x: Double, y: Double, metrics: FlowMetrics, time: TimeInterval, seed: Double
    ) -> (Double, Double) {
        var dx = 0.0
        var dy = 0.0

        // forwardCreep: radial source from center
        let cdx = x - 0.5, cdy = y - 0.5
        let cDist = max(sqrt(cdx * cdx + cdy * cdy), 0.05)
        dx += (cdx / cDist) * metrics.forwardCreep * 0.08
        dy += (cdy / cDist) * metrics.forwardCreep * 0.08

        // headDrop: downward pull near top
        dy += metrics.headDrop * 0.1 * max(0, 1.0 - y * 2)

        // shoulderRounding: side vortex pair
        let vStr = metrics.shoulderRounding * 0.06
        let lDist = max(hypot(x - 0.2, y - 0.5), 0.05)
        dx += -(y - 0.5) / lDist * vStr
        dy += (x - 0.2) / lDist * vStr

        let rDist = max(hypot(x - 0.8, y - 0.5), 0.05)
        dx += (y - 0.5) / rDist * vStr
        dy += -(x - 0.8) / rDist * vStr

        // lateralLean: shear layer
        dy += metrics.lateralLean * 0.07 * (y > 0.5 ? 1 : -1)

        // twist: central rotation
        let tStr = metrics.twist * 0.08
        dx += -cdy * tStr
        dy += cdx * tStr

        // Add slight time-varying wobble per-particle
        dx += sin(time * 1.3 + seed * 2.7) * 0.01
        dy += cos(time * 0.9 + seed * 3.1) * 0.01

        return (dx, dy)
    }

    // MARK: - Draw Sensor Nodes

    private func drawSensorNodes(context: GraphicsContext, size: CGSize) {
        for node in sensorNodes {
            let ratio = isAbsent ? Float(0) : observer.data.metric(for: node.key).clampedRatio
            let cx = size.width * node.fracX
            let cy = size.height * node.fracY
            let nodeR: CGFloat = 14
            let color = PostureVisualStyle.metricColor(ratio: ratio)

            drawNodeCircle(context: context, cx: cx, cy: cy, nodeR: nodeR, ratio: ratio, color: color)
        }
    }

    private func drawNodeCircle(
        context: GraphicsContext, cx: CGFloat, cy: CGFloat,
        nodeR: CGFloat, ratio: Float, color: Color
    ) {
        // Outer ring
        context.stroke(
            Path(ellipseIn: CGRect(x: cx - nodeR, y: cy - nodeR, width: nodeR * 2, height: nodeR * 2)),
            with: .color(color.opacity(0.6)),
            style: StrokeStyle(lineWidth: 2)
        )

        // Inner fill proportional to ratio
        let fillR = nodeR * CGFloat(ratio)
        if fillR > 0 {
            context.fill(
                Path(ellipseIn: CGRect(x: cx - fillR, y: cy - fillR, width: fillR * 2, height: fillR * 2)),
                with: .color(color.opacity(0.3))
            )
        }
    }

    // MARK: - Alert Overlay

    @ViewBuilder
    private func alertOverlay() -> some View {
        if observer.data.isAlertMode, let worst = observer.data.worstOffender {
            VStack {
                Spacer()
                pressureGaugeBar(ratio: worst.clampedRatio)

                Text(worst.key.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.5)))

                if let seconds = observer.data.nudgeCountdownSeconds {
                    Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Pressure Gauge Bar

    private func pressureGaugeBar(ratio: Float) -> some View {
        let fillFraction = CGFloat(ratio)
        let barColor = PostureVisualStyle.metricColor(ratio: ratio)

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.15))
                .frame(width: 120, height: 8)

            Capsule()
                .fill(barColor)
                .frame(width: 120 * fillFraction, height: 8)
        }
    }

    // MARK: - Helpers

    private func fract(_ value: Double) -> Double {
        value - floor(value)
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant48View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant48View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant48View()
        .environmentObject(observer)
}
