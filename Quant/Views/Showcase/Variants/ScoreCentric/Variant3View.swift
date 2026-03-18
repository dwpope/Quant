import SwiftUI
import PostureLogic

struct Variant3View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var isDraining = false
    @State private var drainOffset: CGFloat = 0
    @State private var isCriticalPulsing = false
    @State private var fireFlash = false
    @State private var worstZoneDrain: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        if isLandscape {
                            landscapeLayout(size: geo.size)
                        } else {
                            portraitLayout(size: geo.size)
                        }
                    }
                } else {
                    if isLandscape {
                        landscapeLayout(size: geo.size)
                    } else {
                        portraitLayout(size: geo.size)
                    }
                }

                // Settings gear top-left
                VStack {
                    HStack {
                        SettingsGearButton { showingSettings = true }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }
            .opacity(fireFlash ? 0.8 : 1.0)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
        }
        .sensoryFeedback(.impact, trigger: observer.data.postureState.isBad)
        .animation(PostureAnimations.alertOnset, value: observer.data.isAlertMode)
        .onChange(of: observer.data.nudgeDecision.isFire) { _, isFire in
            if isFire {
                withAnimation(.easeOut(duration: 0.15)) { fireFlash = true }
                withAnimation(.easeIn(duration: 0.3).delay(0.15)) { fireFlash = false }
            }
        }
    }

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    // MARK: - Portrait Layout

    private func portraitLayout(size: CGSize) -> some View {
        VStack(spacing: 20) {
            Spacer()

            batteryView(
                width: size.width * 0.55,
                height: size.width * 0.55 * 0.45,
                isVertical: false
            )

            percentageLabel

            if observer.data.isAlertMode {
                countdownLabel
            }

            metricIconsRow

            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Landscape Layout

    private func landscapeLayout(size: CGSize) -> some View {
        HStack(spacing: 24) {
            ZStack(alignment: .bottom) {
                batteryView(
                    width: size.width * 0.35 * 0.45,
                    height: size.height * 0.7,
                    isVertical: true
                )

                percentageLabelInside
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: size.width * 0.4)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(observer.data.metrics, id: \.key) { metric in
                    landscapeMetricRow(metric: metric)
                }

                if observer.data.isAlertMode {
                    countdownLabel
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: size.width * 0.55)
        }
        .padding()
    }

    private func landscapeMetricRow(metric: MetricInfo) -> some View {
        let isWorst = metric.isWorstOffender && observer.data.isAlertMode
        return HStack(spacing: 10) {
            Image(systemName: metricSymbol(for: metric.key))
                .font(.body)
                .foregroundStyle(PostureVisualStyle.metricColor(ratio: metric.ratio))

            Text(metric.key.displayName)
                .font(.subheadline)
                .foregroundStyle(isWorst ? .primary : .secondary)

            Spacer()

            Text(String(format: "%.0f%%", metric.clampedRatio * 100))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(isWorst ? .primary : .secondary)
        }
        .opacity(observer.data.isAlertMode && !metric.isWorstOffender ? 0.5 : 1.0)
    }

    // MARK: - Battery View

    private func batteryView(width: CGFloat, height: CGFloat, isVertical: Bool) -> some View {
        let data = observer.data
        let score = CGFloat(data.aggregateScore)
        let effectiveScore = max(0, min(1, score - drainOffset))
        let nubSize: CGFloat = isVertical ? width * 0.3 : height * 0.3
        let nubLength: CGFloat = isVertical ? height * 0.04 : width * 0.04

        return ZStack {
            // Battery outline
            BatteryShape(isVertical: isVertical, nubSize: nubSize, nubLength: nubLength)
                .stroke(.primary.opacity(0.6), lineWidth: 3)
                .frame(width: width, height: height)
                .shadow(
                    color: data.postureState.isBad && isCriticalPulsing ? .red.opacity(0.6) : .clear,
                    radius: 12
                )

            // Fill
            batteryFill(
                width: width, height: height,
                isVertical: isVertical,
                fillLevel: effectiveScore,
                nubSize: nubSize, nubLength: nubLength
            )

            // Lightning bolt
            if data.isAlertMode {
                Image(systemName: "bolt.fill")
                    .font(.system(size: min(width, height) * 0.25))
                    .foregroundStyle(data.postureState.isBad ? .red : .yellow)
                    .symbolEffect(.pulse)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(PostureAnimations.metricUpdate, value: effectiveScore)
        .onAppear {
            startDrainIfNeeded()
            if observer.data.postureState.isBad {
                isCriticalPulsing = true
            }
            if observer.data.isAlertMode {
                worstZoneDrain = 0
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: true)) {
                    worstZoneDrain = 0.4
                }
            }
        }
        .onChange(of: data.postureState.isDrifting) { _, drifting in
            if drifting { startDrain() } else { stopDrain() }
        }
        .onChange(of: data.postureState.isBad) { _, bad in
            isCriticalPulsing = bad
        }
        .animation(
            data.postureState.isBad
                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                : .default,
            value: isCriticalPulsing
        )
        .onChange(of: data.isAlertMode) { _, isAlert in
            if isAlert {
                worstZoneDrain = 0
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: true)) {
                    worstZoneDrain = 0.4
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    worstZoneDrain = 0
                }
            }
        }
    }

    private func batteryFill(
        width: CGFloat, height: CGFloat,
        isVertical: Bool, fillLevel: CGFloat,
        nubSize: CGFloat, nubLength: CGFloat
    ) -> some View {
        let cornerRadius: CGFloat = min(width, height) * 0.1
        let inset: CGFloat = 4
        let metrics = observer.data.metrics
        let fillColor = batteryFillColor(score: fillLevel)

        return Canvas { context, size in
            let bodyW = isVertical ? size.width : size.width - nubLength
            let bodyH = isVertical ? size.height - nubLength : size.height
            let bodyX: CGFloat = 0
            let bodyY: CGFloat = isVertical ? nubLength : 0

            let innerX = bodyX + inset
            let innerY = bodyY + inset
            let innerW = bodyW - inset * 2
            let innerH = bodyH - inset * 2

            // Build the undulating fill path
            var path = Path()

            if isVertical {
                // Fill from bottom up
                let fillH = innerH * fillLevel
                let baseY = innerY + innerH - fillH

                // 5 control points across the width
                let segmentW = innerW / 4
                var points: [CGPoint] = []
                for (i, metric) in metrics.prefix(5).enumerated() {
                    let x = innerX + segmentW * CGFloat(i)
                    let metricOffset = (CGFloat(metric.clampedRatio) - CGFloat(observer.data.aggregateScore)) * innerH * 0.08
                    let y = baseY + metricOffset
                    points.append(CGPoint(x: x, y: y))
                }

                if points.count >= 2 {
                    path.move(to: CGPoint(x: innerX, y: innerY + innerH))
                    path.addLine(to: CGPoint(x: innerX, y: points[0].y))

                    for i in 0..<(points.count - 1) {
                        let cp1 = CGPoint(
                            x: (points[i].x + points[i + 1].x) / 2,
                            y: points[i].y
                        )
                        let cp2 = CGPoint(
                            x: (points[i].x + points[i + 1].x) / 2,
                            y: points[i + 1].y
                        )
                        path.addCurve(to: points[i + 1], control1: cp1, control2: cp2)
                    }

                    path.addLine(to: CGPoint(x: innerX + innerW, y: innerY + innerH))
                    path.closeSubpath()
                }
            } else {
                // Fill from left to right
                let fillW = innerW * fillLevel
                let segmentH = innerH / 4
                var points: [CGPoint] = []

                for (i, metric) in metrics.prefix(5).enumerated() {
                    let y = innerY + segmentH * CGFloat(i)
                    let metricOffset = (CGFloat(metric.clampedRatio) - CGFloat(observer.data.aggregateScore)) * innerW * 0.08
                    let x = innerX + fillW - metricOffset
                    points.append(CGPoint(x: x, y: y))
                }

                if points.count >= 2 {
                    path.move(to: CGPoint(x: innerX, y: innerY))

                    // Top edge to first control point
                    path.addLine(to: CGPoint(x: points[0].x, y: innerY))

                    // Bezier curve down through control points (right edge = fill edge)
                    for i in 0..<(points.count - 1) {
                        let cp1 = CGPoint(
                            x: points[i].x,
                            y: (points[i].y + points[i + 1].y) / 2
                        )
                        let cp2 = CGPoint(
                            x: points[i + 1].x,
                            y: (points[i].y + points[i + 1].y) / 2
                        )
                        path.addCurve(to: points[i + 1], control1: cp1, control2: cp2)
                    }

                    path.addLine(to: CGPoint(x: innerX, y: innerY + innerH))
                    path.closeSubpath()
                }
            }

            // Clip to battery body inset with rounded corners
            let clipRect = CGRect(x: innerX, y: innerY, width: innerW, height: innerH)
            let clipPath = Path(roundedRect: clipRect, cornerRadius: max(0, cornerRadius - inset))

            context.clip(to: clipPath)
            context.fill(path, with: .color(fillColor))

            // Draw zone divider lines (4 lines between 5 zones)
            let zoneCount = CGFloat(min(metrics.count, 5))
            if zoneCount > 1 {
                for i in 1..<Int(zoneCount) {
                    var divider = Path()
                    if isVertical {
                        let zoneH = innerH / zoneCount
                        let y = innerY + zoneH * CGFloat(i)
                        divider.move(to: CGPoint(x: innerX, y: y))
                        divider.addLine(to: CGPoint(x: innerX + innerW, y: y))
                    } else {
                        let zoneW = innerW / zoneCount
                        let x = innerX + zoneW * CGFloat(i)
                        divider.move(to: CGPoint(x: x, y: innerY))
                        divider.addLine(to: CGPoint(x: x, y: innerY + innerH))
                    }
                    context.stroke(divider, with: .color(.white.opacity(0.15)), lineWidth: 1)
                }
            }

            // Highlight worst offender zone with downward-draining animation
            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                let worstIndex = metrics.firstIndex(where: { $0.key == worst.key }) ?? 0

                if isVertical {
                    let zoneH = innerH / max(zoneCount, 1)
                    let zoneY = innerY + zoneH * CGFloat(worstIndex)
                    let drainOff = zoneH * worstZoneDrain
                    let zoneRect = CGRect(x: innerX, y: zoneY + drainOff, width: innerW, height: zoneH - drainOff)
                    context.fill(Path(zoneRect), with: .color(.white.opacity(0.25)))
                } else {
                    let zoneW = innerW / max(zoneCount, 1)
                    let zoneX = innerX + zoneW * CGFloat(worstIndex)
                    let drainOff = innerH * worstZoneDrain
                    let zoneRect = CGRect(x: zoneX, y: innerY + drainOff, width: zoneW, height: innerH - drainOff)
                    context.fill(Path(zoneRect), with: .color(.white.opacity(0.25)))
                }
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    // MARK: - Battery Shape

    private struct BatteryShape: Shape {
        let isVertical: Bool
        let nubSize: CGFloat
        let nubLength: CGFloat

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let cornerRadius = min(rect.width, rect.height) * 0.1

            if isVertical {
                // Main body below nub
                let bodyRect = CGRect(
                    x: rect.minX,
                    y: rect.minY + nubLength,
                    width: rect.width,
                    height: rect.height - nubLength
                )
                path.addRoundedRect(in: bodyRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

                // Nub on top center
                let nubX = rect.midX - nubSize / 2
                let nubRect = CGRect(x: nubX, y: rect.minY, width: nubSize, height: nubLength + 2)
                path.addRoundedRect(in: nubRect, cornerSize: CGSize(width: 3, height: 3))
            } else {
                // Main body on left
                let bodyRect = CGRect(
                    x: rect.minX,
                    y: rect.minY,
                    width: rect.width - nubLength,
                    height: rect.height
                )
                path.addRoundedRect(in: bodyRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

                // Nub on right center
                let nubY = rect.midY - nubSize / 2
                let nubRect = CGRect(
                    x: rect.width - nubLength,
                    y: nubY,
                    width: nubLength + 2,
                    height: nubSize
                )
                path.addRoundedRect(in: nubRect, cornerSize: CGSize(width: 3, height: 3))
            }

            return path
        }
    }

    // MARK: - Labels

    private var percentageLabel: some View {
        let data = observer.data
        let score = data.aggregateScore
        let effectiveScore = max(0, min(1, score - Float(drainOffset)))

        return Group {
            if data.postureState.isBad {
                Text("CRITICAL")
                    .font(.system(size: 36, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.red)
            } else {
                Text("\(Int(effectiveScore * 100))%")
                    .font(.system(size: 36, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: Int(effectiveScore * 100))
            }
        }
    }

    private var percentageLabelInside: some View {
        let data = observer.data
        let score = data.aggregateScore
        let effectiveScore = max(0, min(1, score - Float(drainOffset)))

        return Group {
            if data.postureState.isBad {
                Text("CRITICAL")
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.red)
            } else {
                Text("\(Int(effectiveScore * 100))%")
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: Int(effectiveScore * 100))
            }
        }
    }

    private var countdownLabel: some View {
        Group {
            if let seconds = observer.data.nudgeCountdownSeconds {
                Text("Low posture warning in \(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Metric Icons Row

    private var metricIconsRow: some View {
        HStack(spacing: 20) {
            ForEach(observer.data.metrics, id: \.key) { metric in
                Image(systemName: metricSymbol(for: metric.key))
                    .font(.title3)
                    .foregroundStyle(PostureVisualStyle.metricColor(ratio: metric.ratio))
            }
        }
    }

    // MARK: - Helpers

    private func batteryFillColor(score: CGFloat) -> Color {
        if observer.data.postureState.isBad {
            return Color(hue: 0.02, saturation: 0.8, brightness: 0.75) // red — forced in bad state
        }
        if score > 0.6 {
            return Color(hue: 0.38, saturation: 0.6, brightness: 0.7) // green
        } else if score > 0.3 {
            return Color(hue: 0.12, saturation: 0.7, brightness: 0.8) // yellow
        } else {
            return Color(hue: 0.02, saturation: 0.8, brightness: 0.75) // red
        }
    }

    private func metricSymbol(for key: MetricKey) -> String {
        switch key {
        case .forwardCreep:     return "arrow.up.forward"
        case .headDrop:         return "arrow.down"
        case .shoulderRounding: return "arrow.turn.right.down"
        case .lateralLean:      return "arrow.left.arrow.right"
        case .twist:            return "arrow.triangle.2.circlepath"
        }
    }

    // MARK: - Drain Animation

    private func startDrainIfNeeded() {
        if case .drifting = observer.data.postureState {
            startDrain()
        }
    }

    private func startDrain() {
        isDraining = true
        drainOffset = 0
        withAnimation(.linear(duration: 10).repeatForever(autoreverses: true)) {
            drainOffset = 0.08
        }
    }

    private func stopDrain() {
        isDraining = false
        withAnimation(.easeOut(duration: 0.5)) {
            drainOffset = 0
        }
    }
}

// MARK: - NudgeDecision Helpers

private extension NudgeDecision {
    var isFire: Bool {
        if case .fire = self { return true }
        return false
    }

    var isDrifting: Bool {
        if case .pending = self { return true }
        return false
    }
}

private extension PostureState {
    var isDrifting: Bool {
        if case .drifting = self { return true }
        return false
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant3View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant3View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant3View()
        .environmentObject(observer)
}
