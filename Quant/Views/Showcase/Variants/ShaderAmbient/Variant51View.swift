import SwiftUI
import PostureLogic

/// Variant 51: Glitch Matrix — CRT terminal aesthetic with scanlines, vignette, and
/// metric-driven glitch effects. Terminal text displays posture metrics as block-char
/// readouts. Shader-based glitch displacement on degraded posture.
struct Variant51View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    // MARK: - Metric Helpers

    private func metricRatio(for key: MetricKey) -> Float {
        isAbsent ? 0 : observer.data.metric(for: key).clampedRatio
    }

    private var avgStress: Float {
        MetricKey.allCases.map { metricRatio(for: $0) }.reduce(0, +) / 5
    }

    private var statusText: String {
        switch observer.data.postureState {
        case .absent, .calibrating: return "NOMINAL"
        case .good:                 return "NOMINAL"
        case .drifting:             return "WARNING"
        case .bad:                  return "CRITICAL"
        }
    }

    private var statusColor: Color {
        switch observer.data.postureState {
        case .absent, .calibrating, .good: return .green
        case .drifting:                     return .yellow
        case .bad:                          return .red
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isAbsent {
                    AbsenceOverlay {
                        terminalStack(size: geo.size)
                    }
                } else {
                    terminalStack(size: geo.size)
                }

                settingsOverlay
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
        }
        .animation(PostureAnimations.alertOnset, value: observer.data.isAlertMode)
        .preferredColorScheme(.dark)
    }

    // MARK: - Top-Level Layout

    private func terminalStack(size: CGSize) -> some View {
        ZStack {
            // Near-black green-tinted background
            Color(hue: 0.35, saturation: 0.4, brightness: 0.04)
                .ignoresSafeArea()

            scanlineOverlay(size: size)
            vignetteOverlay(size: size)
            terminalContent(size: size)
        }
    }

    private var settingsOverlay: some View {
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

    // MARK: - Scanlines & Vignette

    private func scanlineOverlay(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let lineSpacing: CGFloat = 3
            var y: CGFloat = 0
            while y < canvasSize.height {
                let rect = CGRect(x: 0, y: y, width: canvasSize.width, height: 1)
                context.fill(Path(rect), with: .color(.black.opacity(0.15)))
                y += lineSpacing
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func vignetteOverlay(size: CGSize) -> some View {
        RadialGradient(
            colors: [.clear, Color.black.opacity(0.7)],
            center: .center,
            startRadius: min(size.width, size.height) * 0.25,
            endRadius: max(size.width, size.height) * 0.65
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Terminal Content

    private func terminalContent(size: CGSize) -> some View {
        let fc = metricRatio(for: .forwardCreep)

        return VStack(alignment: .leading, spacing: 6) {
            headerBlock
            separatorLine
            metricReadouts(size: size)
            Spacer()
            nudgeWarningBlock
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .applyGlitchV51(intensity: fc)
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("POSTURE SYSTEM v2.1")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.green.opacity(0.8))

            HStack(spacing: 0) {
                Text("STATUS: ")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.green.opacity(0.6))
                Text(statusText)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var separatorLine: some View {
        Text(String(repeating: "\u{2500}", count: 36))
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(Color.green.opacity(0.3))
    }

    // MARK: - Metric Readouts

    private func metricReadouts(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(MetricKey.allCases) { key in
                metricLine(for: key)
            }
        }
    }

    private func metricLine(for key: MetricKey) -> some View {
        let ratio = metricRatio(for: key)
        let tw = metricRatio(for: .twist)
        let sr = metricRatio(for: .shoulderRounding)
        let ll = metricRatio(for: .lateralLean)
        let label = terminalLabel(for: key)
        let bar = blockBar(ratio: ratio, corrupted: tw > 0.4)
        let value = String(format: "%.2f", ratio)
        let charColor = characterColor(base: .green, ratio: sr)

        return HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(charColor.opacity(0.7))
            Text("  ")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
            Text(bar)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(charColor)
            Text(" ")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(charColor.opacity(0.9))
        }
        .transformEffect(shearTransform(lean: ll))
    }

    // MARK: - Terminal Helpers

    private func terminalLabel(for key: MetricKey) -> String {
        switch key {
        case .forwardCreep:     return "FWD_CREEP"
        case .headDrop:         return "HEAD_DROP"
        case .shoulderRounding: return "SHLDR_RND"
        case .lateralLean:      return "LAT_LEAN "
        case .twist:            return "TWIST    "
        }
    }

    private func blockBar(ratio: Float, corrupted: Bool) -> String {
        let filledCount = Int(ratio * 8)
        let emptyCount = 8 - filledCount
        let glitchChars: [Character] = ["\u{2591}", "\u{2592}", "\u{2593}", "\u{2588}",
                                         "\u{2584}", "\u{2580}", "\u{25A0}", "\u{25A1}",
                                         "\u{25C6}", "\u{25C7}"]

        var result = ""
        for i in 0..<filledCount {
            if corrupted {
                let idx = (i * 7 + filledCount) % glitchChars.count
                result.append(glitchChars[idx])
            } else {
                result.append("\u{2588}")
            }
        }
        for _ in 0..<emptyCount {
            result.append("\u{2591}")
        }
        return result
    }

    private func characterColor(base: Color, ratio: Float) -> Color {
        guard ratio > 0.3 else { return base }
        let shift = Double(ratio - 0.3) / 0.7
        let hue = shift > 0.5 ? 0.0 : 0.65
        return Color(hue: hue, saturation: 0.7, brightness: 0.8).opacity(1.0 - shift * 0.2)
    }

    private func shearTransform(lean: Float) -> CGAffineTransform {
        guard lean > 0.1 else { return .identity }
        let shear = CGFloat(lean - 0.1) * 0.15
        return CGAffineTransform(a: 1, b: 0, c: shear, d: 1, tx: 0, ty: 0)
    }

    // MARK: - Nudge Warning

    private var nudgeWarningBlock: some View {
        Group {
            if let seconds = observer.data.nudgeCountdownSeconds {
                let label = PostureVisualStyle.nudgeCountdownLabel(seconds: seconds)
                Text("!! WARNING: CORRECTION IN \(label) !!")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red)
                    .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Glitch Modifier

private extension View {
    @ViewBuilder
    func applyGlitchV51(intensity: Float) -> some View {
        if PostureShaderSupport.isAvailable, intensity > 0.1 {
            if #available(iOS 17, *) {
                self.postureGlitchEffect(
                    intensity: intensity,
                    time: Date().timeIntervalSinceReferenceDate
                )
            } else {
                self
            }
        } else {
            self
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant51View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant51View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant51View()
        .environmentObject(observer)
}
