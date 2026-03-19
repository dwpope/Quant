import SwiftUI
import PostureLogic

/// Variant 59: Torii Gate — A Japanese torii gate rendered as a structural diagram.
/// The gate's architecture maps to body anatomy: pillars are body sides, kasagi is shoulders,
/// nuki is the core. Each metric deforms a specific structural element. Incense stick countdown.
struct Variant59View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private func ratio(for key: MetricKey) -> Float {
        isAbsent ? 0 : observer.data.metric(for: key).clampedRatio
    }

    private let vermillion = Color(red: 0.85, green: 0.15, blue: 0.08)

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                Color(hue: 0.62, saturation: 0.15, brightness: 0.08)
                    .ignoresSafeArea()

                if isAbsent {
                    AbsenceOverlay {
                        toriiContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    toriiContent(size: geo.size, isLandscape: isLandscape)
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

    // MARK: - Content

    private func toriiContent(size: CGSize, isLandscape: Bool) -> some View {
        ZStack {
            // Moon backdrop
            moonBackdrop(size: size)

            if isLandscape {
                HStack(spacing: 0) {
                    // Gate on left 45%
                    toriiCanvas(size: CGSize(width: size.width * 0.45, height: size.height))
                        .frame(width: size.width * 0.45)

                    // Structural report on right
                    structuralReport
                        .frame(width: size.width * 0.5)
                }
            } else {
                VStack {
                    Spacer()
                    toriiCanvas(size: CGSize(width: size.width * 0.85, height: size.height * 0.6))
                    Spacer()

                    // Metric labels
                    metricLabels
                        .padding(.bottom, 8)

                    // Incense countdown
                    if let seconds = observer.data.nudgeCountdownSeconds {
                        incenseCountdown(seconds: seconds, height: size.height * 0.12)
                            .padding(.bottom, 16)
                    }
                }
            }
        }
    }

    // MARK: - Moon Backdrop

    private func moonBackdrop(size: CGSize) -> some View {
        let ll = ratio(for: .lateralLean)
        let offset = CGFloat(ll) * size.width * 0.1

        return Circle()
            .fill(Color.white.opacity(0.04))
            .frame(width: min(size.width, size.height) * 0.7)
            .offset(x: -offset, y: -size.height * 0.05)
    }

    // MARK: - Torii Canvas

    private func toriiCanvas(size: CGSize) -> some View {
        let fc = ratio(for: .forwardCreep)
        let hd = ratio(for: .headDrop)
        let sr = ratio(for: .shoulderRounding)
        let ll = ratio(for: .lateralLean)
        let tw = ratio(for: .twist)

        return Canvas { context, canvasSize in
            let cx = canvasSize.width / 2
            let baseY = canvasSize.height * 0.85
            let topY = canvasSize.height * 0.15
            let pillarW: CGFloat = canvasSize.width * 0.06
            let pillarSpacing = canvasSize.width * 0.35

            // Forward creep: top of gate shifts horizontally
            let forwardShift = CGFloat(fc) * canvasSize.width * 0.15

            // Lateral lean: pillars have different heights
            let leanAdjust = CGFloat(ll) * canvasSize.height * 0.08

            // Twist: pillars rotate in opposite directions (width changes)
            let twistL = CGFloat(tw) * 0.4  // left pillar thins
            let twistR = CGFloat(tw) * 0.4  // right pillar thickens

            // Pillar base positions
            let leftBaseX = cx - pillarSpacing / 2
            let rightBaseX = cx + pillarSpacing / 2

            // Pillar top positions (with forward lean)
            let leftTopX = leftBaseX + forwardShift
            let rightTopX = rightBaseX + forwardShift
            let leftTopY = topY - leanAdjust
            let rightTopY = topY + leanAdjust

            // Shoulder rounding: nuki bows inward
            let nukiSag = CGFloat(sr) * canvasSize.height * 0.06

            // Head drop: kasagi sags at center
            let kasagiSag = CGFloat(hd) * canvasSize.height * 0.08

            // Stress color
            let stressAmount = max(CGFloat(fc), CGFloat(hd), CGFloat(sr), CGFloat(ll), CGFloat(tw))
            let baseColor = vermillion
            let stressedColor = Color(red: 0.6, green: 0.08, blue: 0.05)
            let lineWidth: CGFloat = 5

            // Draw pillars
            drawPillar(context: &context, baseX: leftBaseX, baseY: baseY,
                       topX: leftTopX, topY: leftTopY,
                       width: pillarW * (1.0 - twistL),
                       color: baseColor, stressColor: stressedColor, stress: stressAmount,
                       lineWidth: lineWidth)

            drawPillar(context: &context, baseX: rightBaseX, baseY: baseY,
                       topX: rightTopX, topY: rightTopY,
                       width: pillarW * (1.0 + twistR),
                       color: baseColor, stressColor: stressedColor, stress: stressAmount,
                       lineWidth: lineWidth)

            // Nuki beam (secondary horizontal)
            let nukiY = topY + (baseY - topY) * 0.3
            let nukiLeftY = nukiY - leanAdjust * 0.3
            let nukiRightY = nukiY + leanAdjust * 0.3
            let nukiMidY = (nukiLeftY + nukiRightY) / 2 + nukiSag

            var nukiPath = Path()
            nukiPath.move(to: CGPoint(x: leftTopX - pillarW * 0.3, y: nukiLeftY))
            nukiPath.addQuadCurve(
                to: CGPoint(x: rightTopX + pillarW * 0.3, y: nukiRightY),
                control: CGPoint(x: cx + forwardShift, y: nukiMidY)
            )
            context.stroke(nukiPath, with: .color(baseColor), style: StrokeStyle(lineWidth: lineWidth * 0.7, lineCap: .round))

            // Kasagi beam (top beam with upswept ends)
            let kasagiY = leftTopY - canvasSize.height * 0.02
            let kasagiRightY = rightTopY - canvasSize.height * 0.02
            let kasagiExtend = canvasSize.width * 0.08
            let upsweep = canvasSize.height * 0.03 * (1.0 - CGFloat(hd))  // Reduces with head drop

            var kasagiPath = Path()
            kasagiPath.move(to: CGPoint(x: leftTopX - kasagiExtend, y: kasagiY - upsweep))
            kasagiPath.addQuadCurve(
                to: CGPoint(x: rightTopX + kasagiExtend, y: kasagiRightY - upsweep),
                control: CGPoint(x: cx + forwardShift, y: min(kasagiY, kasagiRightY) + kasagiSag)
            )
            context.stroke(kasagiPath, with: .color(baseColor), style: StrokeStyle(lineWidth: lineWidth * 1.2, lineCap: .round))

            // Daiwa blocks at junctions
            let daiwaSize: CGFloat = pillarW * 0.8
            let leftDaiwa = CGRect(x: leftTopX - daiwaSize / 2, y: kasagiY - daiwaSize / 2 + 2,
                                   width: daiwaSize, height: daiwaSize * 0.6)
            let rightDaiwa = CGRect(x: rightTopX - daiwaSize / 2, y: kasagiRightY - daiwaSize / 2 + 2,
                                    width: daiwaSize, height: daiwaSize * 0.6)
            context.fill(Path(roundedRect: leftDaiwa, cornerRadius: 2), with: .color(baseColor))
            context.fill(Path(roundedRect: rightDaiwa, cornerRadius: 2), with: .color(baseColor))

            // Stress marks at pillar-nuki junctions when stressed
            if stressAmount > 0.5 {
                drawStressMarks(context: &context,
                                at: CGPoint(x: leftTopX, y: nukiLeftY),
                                intensity: stressAmount)
                drawStressMarks(context: &context,
                                at: CGPoint(x: rightTopX, y: nukiRightY),
                                intensity: stressAmount)
            }

            // Worst offender label
            if let worst = observer.data.worstOffender, observer.data.isAlertMode {
                let labelPoint = CGPoint(x: cx + forwardShift, y: (nukiMidY + kasagiY) / 2)
                let text = Text(worst.key.displayName.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .foregroundColor(.white.opacity(0.8))
                context.draw(text, at: labelPoint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func drawPillar(
        context: inout GraphicsContext,
        baseX: CGFloat, baseY: CGFloat,
        topX: CGFloat, topY: CGFloat,
        width: CGFloat,
        color: Color, stressColor: Color, stress: CGFloat,
        lineWidth: CGFloat
    ) {
        // Tapered pillar (narrower at top)
        let topWidth = width * 0.85
        var path = Path()
        path.move(to: CGPoint(x: baseX - width / 2, y: baseY))
        path.addLine(to: CGPoint(x: topX - topWidth / 2, y: topY))
        path.addLine(to: CGPoint(x: topX + topWidth / 2, y: topY))
        path.addLine(to: CGPoint(x: baseX + width / 2, y: baseY))
        path.closeSubpath()

        context.fill(path, with: .color(color))
        context.stroke(path, with: .color(color.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1))
    }

    private func drawStressMarks(context: inout GraphicsContext, at point: CGPoint, intensity: CGFloat) {
        let count = Int(intensity * 4)
        for i in 0..<count {
            let offset = CGFloat(i) * 4 - CGFloat(count) * 2
            var mark = Path()
            mark.move(to: CGPoint(x: point.x + offset - 3, y: point.y - 3))
            mark.addLine(to: CGPoint(x: point.x + offset + 3, y: point.y + 3))
            context.stroke(mark, with: .color(.white.opacity(0.4 * Double(intensity))),
                           style: StrokeStyle(lineWidth: 1))
        }
    }

    // MARK: - Metric Labels

    private var metricLabels: some View {
        HStack(spacing: 12) {
            ForEach(MetricKey.allCases) { key in
                let r = ratio(for: key)
                let stressed = r > 0.5
                VStack(spacing: 2) {
                    Text(String(key.displayName.prefix(3)).uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(stressed ? vermillion : .white.opacity(0.3))
                    Text(String(format: "%.0f%%", r * 100))
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }

    // MARK: - Structural Report (Landscape)

    private var structuralReport: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text("STRUCTURAL REPORT")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))

            ForEach(MetricKey.allCases) { key in
                let r = ratio(for: key)
                HStack(spacing: 8) {
                    Circle()
                        .fill(r > 0.8 ? .red : r > 0.5 ? .orange : .green)
                        .frame(width: 8, height: 8)
                    Text(key.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(String(format: "%.0f%%", r * 100))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()

            if let seconds = observer.data.nudgeCountdownSeconds {
                incenseCountdown(seconds: seconds, height: 60)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Incense Countdown

    private func incenseCountdown(seconds: TimeInterval, height: CGFloat) -> some View {
        let maxSeconds: Double = 30
        let fraction = min(seconds / maxSeconds, 1.0)

        return HStack(spacing: 12) {
            // Incense stick
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 3, height: height)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .yellow.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: height * fraction)

                // Glowing tip
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
                    .offset(y: -height * fraction + 3)
                    .opacity(fraction > 0.01 ? 1 : 0)
            }
            .frame(height: height)

            VStack(alignment: .leading, spacing: 2) {
                Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                Text("until nudge")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant59View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.8
    )
    let observer = PostureDisplayObserver(source: source)
    Variant59View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant59View()
        .environmentObject(observer)
}
