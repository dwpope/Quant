import SwiftUI
import PostureLogic

/// Variant 52: Lava Lamp — Dark lamp interior with soft blobs that drift vertically.
/// Blob count, drift, compression, and rotation are driven by the five posture metrics.
/// Color temperature shifts from cool blue-teal to hot red based on average stress.
struct Variant52View: View {
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

    // MARK: - Blob Configuration

    private struct Blob: Identifiable {
        let id: Int
        let phaseX: Double
        let phaseY: Double
        let baseRadius: CGFloat
        let speed: Double
    }

    private var blobs: [Blob] {
        let fc = ratio(for: .forwardCreep)
        let count = max(4, min(10, Int(4 + fc * 6)))
        var result: [Blob] = []
        for i in 0..<count {
            let blob = Blob(
                id: i,
                phaseX: Double(i) * 2.37,
                phaseY: Double(i) * 1.63,
                baseRadius: CGFloat(30 + (i % 3) * 15),
                speed: 0.3 + Double(i % 4) * 0.15
            )
            result.append(blob)
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isAbsent {
                    AbsenceOverlay {
                        lampContent(size: geo.size)
                    }
                } else {
                    lampContent(size: geo.size)
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

    // MARK: - Lamp Content

    private func lampContent(size: CGSize) -> some View {
        ZStack {
            // Dark lamp interior
            Color(hue: 0.0, saturation: 0.0, brightness: 0.06)
                .ignoresSafeArea()

            blobCanvas(size: size)
            metricRings(size: size)
            countdownBar(size: size)
        }
    }

    // MARK: - Blob Canvas

    private func blobCanvas(size: CGSize) -> some View {
        let hd = ratio(for: .headDrop)
        let sr = ratio(for: .shoulderRounding)
        let ll = ratio(for: .lateralLean)
        let tw = ratio(for: .twist)
        let stress = avgStress
        let currentBlobs = blobs

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isAbsent)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, canvasSize in
                context.drawLayer { layerCtx in
                    for blob in currentBlobs {
                        drawBlob(
                            context: &layerCtx,
                            blob: blob,
                            canvasSize: canvasSize,
                            time: now,
                            headDrop: hd,
                            shoulderRounding: sr,
                            lateralLean: ll,
                            twist: tw,
                            stress: stress
                        )
                    }
                }
            }
            .blur(radius: 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func drawBlob(
        context: inout GraphicsContext,
        blob: Blob,
        canvasSize: CGSize,
        time: TimeInterval,
        headDrop: Float,
        shoulderRounding: Float,
        lateralLean: Float,
        twist: Float,
        stress: Float
    ) {
        // Vertical drift: headDrop makes blobs sink
        let sinkBias = Double(headDrop) * 0.3
        let baseY = (sin(time * blob.speed + blob.phaseY) * 0.4 + 0.5 + sinkBias)
        let normalizedY = baseY.truncatingRemainder(dividingBy: 1.0)
        let cy = normalizedY * canvasSize.height

        // Horizontal: lateralLean drifts sideways
        let leanShift = Double(lateralLean) * 0.15
        let baseX = sin(time * blob.speed * 0.7 + blob.phaseX) * 0.3 + 0.5 + leanShift
        var cx = min(max(baseX, 0.05), 0.95) * canvasSize.width

        // Twist: orbital rotation
        let orbitRadius = Double(twist) * 30
        cx += orbitRadius * cos(time * 1.2 + blob.phaseX)
        let cyAdjusted = cy + orbitRadius * sin(time * 1.2 + blob.phaseY)

        // Shoulder rounding: horizontal compression
        let hScale = CGFloat(1.0 - Double(shoulderRounding) * 0.4)
        let vScale: CGFloat = 1.0
        let r = blob.baseRadius

        // Color: hue shifts from cool (0.55) to hot (0.0) with stress
        let hue = Double(0.55 * (1.0 - stress))
        let blobColor = Color(hue: max(0, hue), saturation: 0.7, brightness: 0.8)

        let rect = CGRect(
            x: cx - r * hScale,
            y: cyAdjusted - r * vScale,
            width: r * 2 * hScale,
            height: r * 2 * vScale
        )
        context.fill(Path(ellipseIn: rect), with: .color(blobColor.opacity(0.6)))
    }

    // MARK: - Metric Rings

    private func metricRings(size: CGSize) -> some View {
        let keys = MetricKey.allCases
        let positions: [(CGFloat, CGFloat)] = [
            (0.08, 0.2), (0.92, 0.2), (0.08, 0.8), (0.92, 0.8), (0.5, 0.95)
        ]

        return Canvas { context, canvasSize in
            for (index, key) in keys.enumerated() {
                guard index < positions.count else { break }
                let pos = positions[index]
                let cx = canvasSize.width * pos.0
                let cy = canvasSize.height * pos.1
                let r: CGFloat = 14
                let metricRatio = ratio(for: key)

                // Background ring
                context.stroke(
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                    with: .color(.white.opacity(0.15)),
                    style: StrokeStyle(lineWidth: 2.5)
                )

                // Filled arc
                var arc = Path()
                arc.addArc(
                    center: CGPoint(x: cx, y: cy),
                    radius: r,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + Double(metricRatio) * 360),
                    clockwise: false
                )
                context.stroke(
                    arc,
                    with: .color(PostureVisualStyle.metricColor(ratio: metricRatio)),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Countdown Bar (Thermometer)

    private func countdownBar(size: CGSize) -> some View {
        Group {
            if let seconds = observer.data.nudgeCountdownSeconds {
                thermometerBar(seconds: seconds, width: size.width)
            }
        }
    }

    private func thermometerBar(seconds: TimeInterval, width: CGFloat) -> some View {
        let maxSeconds: Double = 30
        let fraction = min(seconds / maxSeconds, 1.0)

        return VStack {
            Spacer()
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: width * 0.5, height: 8)

                Capsule()
                    .fill(Color(hue: 0.0, saturation: 0.8, brightness: 0.8))
                    .frame(width: width * 0.5 * fraction, height: 8)
            }

            Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant52View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant52View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant52View()
        .environmentObject(observer)
}
