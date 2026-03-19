import SwiftUI
import PostureLogic

/// Variant 49: Frosted Glass — Clean metric display that blurs as posture degrades.
/// Canvas overlay draws frost crystalline dots with regional intensity per metric.
/// Worst offender is shown on top of the frost with a circle background.
struct Variant49View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private var avgStress: Float {
        isAbsent ? 0 : (1.0 - observer.data.aggregateScore)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isAbsent {
                    AbsenceOverlay {
                        frostedContent(size: geo.size)
                    }
                } else {
                    frostedContent(size: geo.size)
                }

                settingsButton()
            }
        }
        .preferredColorScheme(.light)
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

    // MARK: - Frosted Content

    private func frostedContent(size: CGSize) -> some View {
        let blurRadius = CGFloat(avgStress) * 16

        return ZStack {
            // Light background
            Color(hue: 0.0, saturation: 0.0, brightness: 0.96)
                .ignoresSafeArea()

            // Clean metric display that gets blurred
            metricDisplay()
                .blur(radius: blurRadius)

            // Frost overlay canvas
            frostCanvas(size: size)

            // Glass edge highlight
            glassEdgeHighlight()

            // Worst offender on top of frost
            worstOffenderBadge()
        }
    }

    // MARK: - Metric Display (Blurred Layer)

    private func metricDisplay() -> some View {
        VStack(spacing: 20) {
            // State label
            Text(PostureVisualStyle.stateLabel(for: observer.data.postureState))
                .font(.title2.bold())
                .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))

            // Five metric bars
            ForEach(MetricKey.allCases) { key in
                metricRow(key: key)
            }
        }
        .padding(.horizontal, 32)
    }

    private func metricRow(key: MetricKey) -> some View {
        let ratio = isAbsent ? Float(0) : observer.data.metric(for: key).clampedRatio
        let color = PostureVisualStyle.metricColor(ratio: ratio)
        let percentage = Int(ratio * 100)

        return HStack {
            Image(systemName: key.symbolName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(key.displayName)
                .font(.caption)
                .foregroundStyle(.primary)
                .frame(width: 100, alignment: .leading)

            barFill(ratio: CGFloat(ratio), color: color)

            Text("\(percentage)%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func barFill(ratio: CGFloat, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.15))

                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * ratio)
            }
        }
        .frame(height: 8)
    }

    // MARK: - Frost Canvas

    private func frostCanvas(size: CGSize) -> some View {
        let metrics = frostMetrics()

        return Canvas { context, canvasSize in
            drawFrostDots(context: context, size: canvasSize, metrics: metrics)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func frostMetrics() -> [MetricKey: Float] {
        guard !isAbsent else {
            return MetricKey.allCases.reduce(into: [:]) { $0[$1] = 0 }
        }
        return MetricKey.allCases.reduce(into: [:]) { dict, key in
            dict[key] = observer.data.metric(for: key).clampedRatio
        }
    }

    private func drawFrostDots(context: GraphicsContext, size: CGSize, metrics: [MetricKey: Float]) {
        let dotCount = 300
        let cx = size.width / 2
        let cy = size.height / 2

        for i in 0..<dotCount {
            let seed = Double(i)
            let px = fract(seed * 0.8123 + seed * seed * 0.0019) * size.width
            let py = fract(seed * 0.5917 + seed * 0.0037) * size.height

            let intensity = frostIntensity(px: px, py: py, cx: cx, cy: cy,
                                           size: size, metrics: metrics)
            guard intensity > 0.05 else { continue }

            let r: CGFloat = 1.0 + CGFloat(intensity) * 2.5
            context.fill(
                Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)),
                with: .color(.white.opacity(Double(intensity) * 0.8))
            )
        }
    }

    /// Calculate frost intensity at a point based on regional metric mapping.
    private func frostIntensity(
        px: CGFloat, py: CGFloat, cx: CGFloat, cy: CGFloat,
        size: CGSize, metrics: [MetricKey: Float]
    ) -> Float {
        let fc = metrics[.forwardCreep] ?? 0
        let hd = metrics[.headDrop] ?? 0
        let sr = metrics[.shoulderRounding] ?? 0
        let ll = metrics[.lateralLean] ?? 0
        let tw = metrics[.twist] ?? 0

        var intensity: Float = 0

        // Center region: forwardCreep
        let centerDist = Float(hypot(px - cx, py - cy) / min(size.width, size.height))
        intensity += fc * max(0, 1.0 - centerDist * 3)

        // Top edge: headDrop
        let topProximity = Float(1.0 - py / size.height)
        intensity += hd * max(0, topProximity - 0.5) * 2

        // Side edges: shoulderRounding
        let leftProximity = Float(1.0 - px / size.width)
        let rightProximity = Float(px / size.width)
        let edgeProximity = max(max(0, leftProximity - 0.7), max(0, rightProximity - 0.7))
        intensity += sr * edgeProximity * 3

        // Asymmetric: lateralLean (stronger on right side)
        let asymmetry = Float(px / size.width)
        intensity += ll * asymmetry * 0.5

        // Spiral: twist (distance from center modulated by angle)
        let angle = Float(atan2(py - cy, px - cx))
        let spiralPhase = sin(angle * 3 + centerDist * 10)
        intensity += tw * max(0, spiralPhase) * 0.4

        return min(intensity, 1.0)
    }

    // MARK: - Glass Edge Highlight

    private func glassEdgeHighlight() -> some View {
        RoundedRectangle(cornerRadius: 0)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.4), .clear, .white.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    // MARK: - Worst Offender Badge

    @ViewBuilder
    private func worstOffenderBadge() -> some View {
        if observer.data.isAlertMode, let worst = observer.data.worstOffender {
            VStack {
                Spacer()

                VStack(spacing: 6) {
                    Image(systemName: worst.key.symbolName)
                        .font(.title3)
                        .foregroundStyle(PostureVisualStyle.metricColor(ratio: worst.clampedRatio))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.white.opacity(0.9)))

                    Text(worst.key.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)

                    if let seconds = observer.data.nudgeCountdownSeconds {
                        Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - Helpers

    private func fract(_ value: Double) -> CGFloat {
        CGFloat(value - floor(value))
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant49View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .shoulderRounding,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant49View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant49View()
        .environmentObject(observer)
}
