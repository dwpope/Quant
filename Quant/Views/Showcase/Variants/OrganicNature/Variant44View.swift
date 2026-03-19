import SwiftUI
import PostureLogic

/// Variant 44: Terrain Map — A topographic contour map where five peaks represent the five
/// posture metrics. Good posture = tall, well-defined peaks. Bad posture = peaks flatten and
/// erode. Uses a cartographic aesthetic with contour lines, elevation colors, and grid overlay.
struct Variant44View: View {
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
                PostureStateAmbientBackground(state: observer.data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        terrainCanvas(size: geo.size)
                    }
                } else {
                    terrainCanvas(size: geo.size)
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

    // Peak layout: head at top-center, shoulders flanking, lean and twist lower
    private struct Peak {
        let key: MetricKey
        let label: String
        let fracX: CGFloat
        let fracY: CGFloat
    }

    private let peaks: [Peak] = [
        Peak(key: .headDrop, label: "HEAD", fracX: 0.5, fracY: 0.25),
        Peak(key: .shoulderRounding, label: "SHLD", fracX: 0.25, fracY: 0.38),
        Peak(key: .forwardCreep, label: "FWD", fracX: 0.75, fracY: 0.38),
        Peak(key: .lateralLean, label: "LEAN", fracX: 0.3, fracY: 0.62),
        Peak(key: .twist, label: "TWST", fracX: 0.7, fracY: 0.62),
    ]

    private func terrainCanvas(size: CGSize) -> some View {
        let metrics: [MetricKey: Float] = [
            .forwardCreep: isAbsent ? 0 : observer.data.metric(for: .forwardCreep).clampedRatio,
            .headDrop: isAbsent ? 0 : observer.data.metric(for: .headDrop).clampedRatio,
            .shoulderRounding: isAbsent ? 0 : observer.data.metric(for: .shoulderRounding).clampedRatio,
            .lateralLean: isAbsent ? 0 : observer.data.metric(for: .lateralLean).clampedRatio,
            .twist: isAbsent ? 0 : observer.data.metric(for: .twist).clampedRatio,
        ]
        let worst = observer.data.worstOffender

        return ZStack {
            Canvas { context, canvasSize in
                let s = min(canvasSize.width, canvasSize.height) * 0.003

                // Grid overlay
                let gridSpacing: CGFloat = 30 * s
                for x in stride(from: CGFloat(0), through: canvasSize.width, by: gridSpacing) {
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    context.stroke(line, with: .color(.secondary.opacity(0.06)), style: StrokeStyle(lineWidth: 0.5))
                }
                for y in stride(from: CGFloat(0), through: canvasSize.height, by: gridSpacing) {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    context.stroke(line, with: .color(.secondary.opacity(0.06)), style: StrokeStyle(lineWidth: 0.5))
                }

                // Draw contour rings for each peak
                for peak in peaks {
                    let ratio = metrics[peak.key] ?? 0
                    let health = 1.0 - CGFloat(ratio) // 1 = good (tall peak), 0 = bad (flat)
                    let peakX = canvasSize.width * peak.fracX
                    let peakY = canvasSize.height * peak.fracY
                    let isWorst = worst?.key == peak.key
                    let maxRings = Int(max(1, health * 6))
                    let baseRadius: CGFloat = 15 * s
                    let ringSpacing: CGFloat = 8 * s

                    for ring in 0..<maxRings {
                        let ringFrac = CGFloat(ring) / max(1, CGFloat(maxRings - 1))
                        let radius = baseRadius + CGFloat(ring) * ringSpacing

                        // Contour color ramp: green at base -> brown -> white at summit
                        let color = elevationColor(fraction: 1.0 - ringFrac, health: health, isWorst: isWorst)

                        // Add slight Perlin-like noise to contour shape
                        var contourPath = Path()
                        let segments = 24
                        for seg in 0...segments {
                            let angle = CGFloat(seg) * .pi * 2 / CGFloat(segments)
                            let noise = sin(angle * 3.7 + CGFloat(ring) * 2.1) * 0.12 + sin(angle * 7.3) * 0.06
                            let r = radius * (1.0 + noise)
                            let pt = CGPoint(x: peakX + r * cos(angle), y: peakY + r * sin(angle) * 0.7)
                            if seg == 0 { contourPath.move(to: pt) } else { contourPath.addLine(to: pt) }
                        }
                        contourPath.closeSubpath()

                        // Fragmented lines for degraded peaks
                        if health < 0.4 && ring > 0 {
                            context.stroke(contourPath, with: .color(color),
                                           style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        } else {
                            context.stroke(contourPath, with: .color(color),
                                           style: StrokeStyle(lineWidth: 1.2))
                        }
                    }

                    // Peak label
                    let labelColor: Color = isWorst ? .red : .secondary
                    let fontSize: CGFloat = isWorst ? 9 * s : 7 * s
                    context.draw(
                        Text(peak.label).font(.system(size: fontSize, weight: isWorst ? .bold : .medium, design: .monospaced))
                            .foregroundColor(labelColor),
                        at: CGPoint(x: peakX, y: peakY)
                    )

                    // Elevation percentage
                    let pct = Int((1.0 - ratio) * 100)
                    context.draw(
                        Text("\(pct)%").font(.system(size: 6 * s, weight: .light, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6)),
                        at: CGPoint(x: peakX, y: peakY + 10 * s)
                    )
                }

                // Storm front (nudge countdown)
                if let worst = worst, let seconds = observer.data.nudgeCountdownSeconds {
                    let maxSeconds: Double = 30
                    let progress = 1.0 - min(seconds / maxSeconds, 1.0)
                    let frontX = canvasSize.width * CGFloat(progress)

                    var stormLine = Path()
                    for y in stride(from: CGFloat(0), through: canvasSize.height, by: 4 * s) {
                        let waveX = frontX + sin(y * 0.03) * 10 * s
                        if y < 1 { stormLine.move(to: CGPoint(x: waveX, y: y)) }
                        else { stormLine.addLine(to: CGPoint(x: waveX, y: y)) }
                    }
                    context.stroke(stormLine, with: .color(.red.opacity(0.4)),
                                   style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Alert overlay
            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                VStack {
                    Spacer()
                    Text(worst.key.displayName)
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))

                    if let seconds = observer.data.nudgeCountdownSeconds {
                        Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    private func elevationColor(fraction: CGFloat, health: CGFloat, isWorst: Bool) -> Color {
        if isWorst && health < 0.5 {
            // Red-tinted contours for degraded worst offender
            return Color(hue: 0.02, saturation: 0.6 * (1 - fraction), brightness: 0.5 + fraction * 0.3)
        }

        // Normal elevation ramp: green -> yellow -> brown -> white
        let adjustedFrac = fraction * health
        if adjustedFrac < 0.25 {
            return Color(hue: 0.33, saturation: 0.6, brightness: 0.4)
        } else if adjustedFrac < 0.5 {
            return Color(hue: 0.15, saturation: 0.5, brightness: 0.5)
        } else if adjustedFrac < 0.75 {
            return Color(hue: 0.08, saturation: 0.4, brightness: 0.45)
        } else {
            return Color(white: 0.8)
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant44View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant44View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant44View()
        .environmentObject(observer)
}
