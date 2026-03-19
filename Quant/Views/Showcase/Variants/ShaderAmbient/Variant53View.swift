import SwiftUI
import PostureLogic

/// Variant 53: Heartbeat Pulse — Dark background with a central pulsing ring and
/// ECG waveform trace. Pulse rate scales from 60 BPM (calm) to 180 BPM (severe).
/// Metric distortions affect QRS amplitude, baseline drift, PVCs, tilt, and noise.
struct Variant53View: View {
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

    /// BPM: 60 at calm, up to 180 at maximum stress.
    private var bpm: Double {
        60 + Double(avgStress) * 120
    }

    /// Pulse period in seconds.
    private var pulsePeriod: Double {
        60.0 / bpm
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isAbsent {
                    AbsenceOverlay {
                        heartbeatContent(size: geo.size)
                    }
                } else {
                    heartbeatContent(size: geo.size)
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

    // MARK: - Heartbeat Content

    private func heartbeatContent(size: CGSize) -> some View {
        ZStack {
            Color(hue: 0.0, saturation: 0.0, brightness: 0.05)
                .ignoresSafeArea()

            ecgCanvas(size: size)
            pulsingRing(size: size)
            metricsInRing(size: size)
            bpmDisplay
            chargeBar(size: size)
        }
    }

    // MARK: - Pulsing Ring

    private func pulsingRing(size: CGSize) -> some View {
        let ringDiameter: CGFloat = min(size.width, size.height) * 0.5
        let period = pulsePeriod

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isAbsent)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let phase = now.truncatingRemainder(dividingBy: period) / period
            let pulse: CGFloat = pulseScale(phase: phase)
            let ringColor = PostureVisualStyle.stateColor(for: observer.data.postureState)
            let diameter: CGFloat = ringDiameter * pulse
            let opacity: Double = 0.6 + Double(pulse - 1.0) * 2

            Circle()
                .stroke(ringColor, lineWidth: 3)
                .frame(width: diameter, height: diameter)
                .opacity(opacity)
        }
    }

    private func pulseScale(phase: Double) -> CGFloat {
        // Quick expansion at heartbeat, then settle
        if phase < 0.1 {
            return 1.0 + CGFloat(phase / 0.1) * 0.08
        } else if phase < 0.3 {
            return 1.08 - CGFloat((phase - 0.1) / 0.2) * 0.08
        }
        return 1.0
    }

    // MARK: - ECG Canvas

    private func ecgCanvas(size: CGSize) -> some View {
        let fc = ratio(for: .forwardCreep)
        let hd = ratio(for: .headDrop)
        let sr = ratio(for: .shoulderRounding)
        let ll = ratio(for: .lateralLean)
        let tw = ratio(for: .twist)
        let period = pulsePeriod

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isAbsent)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, canvasSize in
                drawWaveform(
                    context: &context,
                    canvasSize: canvasSize,
                    time: now,
                    period: period,
                    fc: fc, hd: hd, sr: sr, ll: ll, tw: tw
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }

    private func drawWaveform(
        context: inout GraphicsContext,
        canvasSize: CGSize,
        time: TimeInterval,
        period: Double,
        fc: Float, hd: Float, sr: Float, ll: Float, tw: Float
    ) {
        let midY = canvasSize.height * 0.5
        let amplitude = canvasSize.height * 0.12
        // Lateral lean tilts baseline
        let tiltSlope = CGFloat(ll) * 0.15

        var path = Path()
        let sampleCount = Int(canvasSize.width)

        for i in 0..<sampleCount {
            let x = CGFloat(i)
            let scrollOffset = time * 80
            let sampleX = (Double(i) + scrollOffset).truncatingRemainder(dividingBy: canvasSize.width)
            let normalized = sampleX / canvasSize.width
            let tInPeriod = normalized.truncatingRemainder(dividingBy: 1.0)

            let ecg = ecgSample(
                t: tInPeriod,
                qrsAmplitude: 1.0 + Double(fc) * 1.5,
                baselineDrift: Double(hd) * 0.3,
                hasPVC: sr > 0.5 && tInPeriod > 0.7 && tInPeriod < 0.85,
                fibrillation: Double(tw) * 0.4
            )

            let tiltOffset = (x / canvasSize.width - 0.5) * tiltSlope * amplitude
            let y = midY - ecg * amplitude + tiltOffset

            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }

        context.stroke(
            path,
            with: .color(.green.opacity(0.7)),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        )
    }

    /// Generate a single ECG P-QRS-T sample at normalized time t (0-1).
    private func ecgSample(
        t: Double,
        qrsAmplitude: Double,
        baselineDrift: Double,
        hasPVC: Bool,
        fibrillation: Double
    ) -> CGFloat {
        var value: Double = 0

        // P wave (t: 0.0 - 0.15)
        if t < 0.15 {
            let p = t / 0.15
            value = 0.15 * sin(p * .pi)
        }
        // QRS complex (t: 0.2 - 0.35)
        else if t >= 0.2 && t < 0.25 {
            let q = (t - 0.2) / 0.05
            value = -0.2 * q * qrsAmplitude
        } else if t >= 0.25 && t < 0.30 {
            let r = (t - 0.25) / 0.05
            value = (-0.2 + 1.4 * r) * qrsAmplitude
        } else if t >= 0.30 && t < 0.35 {
            let s = (t - 0.30) / 0.05
            value = (1.2 - 1.5 * s) * qrsAmplitude
        }
        // T wave (t: 0.45 - 0.65)
        else if t >= 0.45 && t < 0.65 {
            let tw = (t - 0.45) / 0.20
            value = 0.25 * sin(tw * .pi)
        }

        // PVC: extra beat
        if hasPVC {
            let pvcT = (t - 0.7) / 0.15
            if pvcT >= 0 && pvcT <= 1 {
                value += 0.6 * sin(pvcT * .pi) * qrsAmplitude * 0.5
            }
        }

        // Baseline drift
        value += baselineDrift * sin(t * .pi * 2)

        // Fibrillation noise
        if fibrillation > 0 {
            let noise = sin(t * 47) * cos(t * 31) * fibrillation
            value += noise
        }

        return CGFloat(value)
    }

    // MARK: - Metrics Inside Ring

    private struct RingMetric {
        let label: String
        let ratio: Float
        let angle: Double
    }

    private var ringMetrics: [RingMetric] {
        let keys = MetricKey.allCases
        let count = Double(keys.count)
        return keys.enumerated().map { index, key in
            let angle = -(.pi / 2) + Double(index) * (2 * .pi / count)
            return RingMetric(
                label: String(key.displayName.prefix(3)).uppercased(),
                ratio: ratio(for: key),
                angle: angle
            )
        }
    }

    private func metricsInRing(size: CGSize) -> some View {
        let cx = size.width / 2
        let cy = size.height / 2
        let innerRadius = min(size.width, size.height) * 0.15
        let metrics = ringMetrics

        return Canvas { context, canvasSize in
            for metric in metrics {
                let px: CGFloat = cx + innerRadius * cos(metric.angle)
                let py: CGFloat = cy + innerRadius * sin(metric.angle)
                let color = PostureVisualStyle.metricColor(ratio: metric.ratio)

                let dotRect = CGRect(x: px - 4, y: py - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: dotRect), with: .color(color))

                let text = Text(metric.label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                context.draw(text, at: CGPoint(x: px, y: py + 10))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - BPM Display

    private var bpmDisplay: some View {
        VStack {
            Spacer()
            Text("\(Int(bpm))")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(.green.opacity(0.8))
            Text("BPM")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.green.opacity(0.5))
        }
        .padding(.bottom, 80)
    }

    // MARK: - Charge Bar (Defibrillator Countdown)

    private func chargeBar(size: CGSize) -> some View {
        Group {
            if let seconds = observer.data.nudgeCountdownSeconds {
                defibrillatorBar(seconds: seconds, width: size.width)
            }
        }
    }

    private func defibrillatorBar(seconds: TimeInterval, width: CGFloat) -> some View {
        let maxSeconds: Double = 30
        let fraction = min(seconds / maxSeconds, 1.0)

        return VStack(spacing: 4) {
            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text("CHARGE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.yellow.opacity(0.7))
            }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: width * 0.6, height: 10)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.yellow, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 0.6 * fraction, height: 10)
            }

            Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant53View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant53View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant53View()
        .environmentObject(observer)
}
