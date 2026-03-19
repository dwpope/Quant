import SwiftUI
import PostureLogic

// MARK: - Constellation Data

/// A grouping of connected stars forming a constellation for one metric.
private struct Constellation {
    let key: MetricKey
    /// Fractional positions within the canvas (0-1 range).
    let stars: [(CGFloat, CGFloat)]
    /// Pairs of star indices that should be connected by lines.
    let connections: [(Int, Int)]
}

private let constellations: [Constellation] = [
    Constellation(
        key: .forwardCreep,
        stars: [(0.20, 0.18), (0.25, 0.25), (0.18, 0.30), (0.28, 0.32)],
        connections: [(0, 1), (1, 2), (1, 3)]
    ),
    Constellation(
        key: .headDrop,
        stars: [(0.50, 0.10), (0.45, 0.18), (0.55, 0.18)],
        connections: [(0, 1), (0, 2), (1, 2)]
    ),
    Constellation(
        key: .shoulderRounding,
        stars: [(0.75, 0.14), (0.80, 0.22), (0.72, 0.26), (0.82, 0.30)],
        connections: [(0, 1), (0, 2), (1, 3)]
    ),
    Constellation(
        key: .lateralLean,
        stars: [(0.30, 0.42), (0.35, 0.48), (0.28, 0.52)],
        connections: [(0, 1), (1, 2)]
    ),
    Constellation(
        key: .twist,
        stars: [(0.68, 0.40), (0.72, 0.46), (0.64, 0.50), (0.70, 0.54)],
        connections: [(0, 1), (1, 2), (2, 3)]
    ),
]

/// Variant 47: Aurora Borealis — Full-screen aurora simulation over a dark night sky.
/// Star field rendered in Canvas, aurora curtains via Metal shader, and five constellation
/// groupings represent posture metrics with brightness proportional to ratio.
struct Variant47View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false

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
                        auroraContent(size: geo.size)
                    }
                } else {
                    auroraContent(size: geo.size)
                }

                settingsButton()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
        }
        .animation(PostureAnimations.alertOnset, value: observer.data.isAlertMode)
    }

    // MARK: - Settings Button

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

    // MARK: - Aurora Content

    @ViewBuilder
    private func auroraContent(size: CGSize) -> some View {
        PostureShaderFallback {
            shaderAuroraView(size: size)
        } fallbackContent: {
            fallbackAuroraView(size: size)
        }
    }

    // MARK: - Shader Path

    @available(iOS 17, *)
    private func shaderAuroraView(size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isAbsent)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                nightSkyBackground()

                starFieldCanvas(size: size, time: time)

                // Aurora curtain via Metal shader
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .ignoresSafeArea()
                    .postureAuroraEffect(data: observer.data, time: time, size: size)

                constellationCanvas(size: size, time: time)

                alertOverlay()
            }
        }
    }

    // MARK: - Fallback Path

    private func fallbackAuroraView(size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: isAbsent)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                nightSkyBackground()

                starFieldCanvas(size: size, time: time)

                fallbackAuroraGradient(size: size)

                constellationCanvas(size: size, time: time)

                alertOverlay()
            }
        }
    }

    // MARK: - Night Sky

    private func nightSkyBackground() -> some View {
        LinearGradient(
            colors: [
                Color(hue: 0.68, saturation: 0.4, brightness: 0.05),
                Color(hue: 0.72, saturation: 0.5, brightness: 0.08),
                Color(hue: 0.65, saturation: 0.3, brightness: 0.03)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Fallback Aurora Gradient

    private func fallbackAuroraGradient(size: CGSize) -> some View {
        let score = 1.0 - Double(observer.data.aggregateScore)
        let hue = 0.33 - score * 0.2

        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.6, brightness: 0.3).opacity(0.4),
                Color(hue: hue + 0.1, saturation: 0.5, brightness: 0.25).opacity(0.3),
                .clear
            ],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }

    // MARK: - Star Field

    private func starFieldCanvas(size: CGSize, time: TimeInterval) -> some View {
        Canvas { context, canvasSize in
            drawStarField(context: context, size: canvasSize, time: time)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func drawStarField(context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let starCount = 80

        for i in 0..<starCount {
            let seed = Double(i)
            let px = fract(seed * 0.7123 + seed * seed * 0.0031) * size.width
            let py = fract(seed * 0.3917 + seed * 0.0047) * size.height

            let twinkle = (sin(time * (1.5 + seed * 0.3) + seed * 2.1) + 1.0) / 2.0
            let brightness = 0.3 + twinkle * 0.7
            let radius: CGFloat = (i % 5 == 0) ? 1.8 : 1.0

            context.fill(
                Path(ellipseIn: CGRect(x: px - radius, y: py - radius,
                                        width: radius * 2, height: radius * 2)),
                with: .color(.white.opacity(brightness))
            )
        }
    }

    // MARK: - Constellation Canvas

    private func constellationCanvas(size: CGSize, time: TimeInterval) -> some View {
        Canvas { context, canvasSize in
            drawConstellations(context: context, size: canvasSize, time: time)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func drawConstellations(context: GraphicsContext, size: CGSize, time: TimeInterval) {
        for constellation in constellations {
            let ratio = isAbsent ? Float(0) : observer.data.metric(for: constellation.key).clampedRatio
            let brightness = Double(max(0.15, 1.0 - ratio))
            let color = PostureVisualStyle.metricColor(ratio: ratio)

            drawSingleConstellation(
                context: context, size: size, constellation: constellation,
                brightness: brightness, color: color, time: time
            )
        }
    }

    private func drawSingleConstellation(
        context: GraphicsContext, size: CGSize, constellation: Constellation,
        brightness: Double, color: Color, time: TimeInterval
    ) {
        // Draw connection lines
        for (a, b) in constellation.connections {
            let starA = constellation.stars[a]
            let starB = constellation.stars[b]
            var line = Path()
            line.move(to: CGPoint(x: starA.0 * size.width, y: starA.1 * size.height))
            line.addLine(to: CGPoint(x: starB.0 * size.width, y: starB.1 * size.height))
            context.stroke(line, with: .color(color.opacity(brightness * 0.4)),
                           style: StrokeStyle(lineWidth: 1))
        }

        // Draw stars
        for (idx, star) in constellation.stars.enumerated() {
            let px = star.0 * size.width
            let py = star.1 * size.height
            let twinkle = (sin(time * 2.0 + Double(idx) * 1.5) + 1.0) / 2.0
            let starBrightness = brightness * (0.6 + twinkle * 0.4)
            let r: CGFloat = 3.0

            // Glow halo
            context.fill(
                Path(ellipseIn: CGRect(x: px - r * 2, y: py - r * 2, width: r * 4, height: r * 4)),
                with: .color(color.opacity(starBrightness * 0.2))
            )

            // Star core
            context.fill(
                Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)),
                with: .color(color.opacity(starBrightness))
            )
        }
    }

    // MARK: - Alert Overlay

    @ViewBuilder
    private func alertOverlay() -> some View {
        if observer.data.isAlertMode, let worst = observer.data.worstOffender {
            VStack {
                Spacer()
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

    // MARK: - Helpers

    /// Fractional part of a double (0..<1).
    private func fract(_ value: Double) -> CGFloat {
        CGFloat(value - floor(value))
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant47View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant47View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant47View()
        .environmentObject(observer)
}
