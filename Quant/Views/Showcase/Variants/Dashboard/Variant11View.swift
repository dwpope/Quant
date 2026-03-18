import SwiftUI
import PostureLogic

struct Variant11View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var cautionVisible = false
    @State private var pullUpFlash = false

    private var data: PostureDisplayData { observer.data }

    private let hudColor = Color.cyan.opacity(0.9)
    private let hudGreen = Color.green.opacity(0.8)

    private var isAbsent: Bool {
        switch data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private var isFire: Bool {
        if case .fire = data.nudgeDecision { return true }
        return false
    }

    private var alertBannerText: String? {
        switch data.postureState {
        case .drifting: return "CAUTION"
        case .bad: return "WARNING"
        default: return nil
        }
    }

    private var alertBannerColor: Color {
        data.postureState.isBad ? .red : .yellow
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                if isAbsent {
                    AbsenceOverlay {
                        cockpitContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    cockpitContent(size: geo.size, isLandscape: isLandscape)
                }

                // Settings gear (HUD style)
                VStack {
                    HStack {
                        Spacer()
                        Button { showingSettings = true } label: {
                            ZStack {
                                Circle()
                                    .stroke(hudColor.opacity(0.5), lineWidth: 1)
                                    .frame(width: 30, height: 30)
                                Image(systemName: "gearshape.fill")
                                    .font(.caption)
                                    .foregroundStyle(hudColor)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
        }
        .sensoryFeedback(.impact, trigger: data.postureState.isBad)
        .animation(PostureAnimations.alertOnset, value: data.isAlertMode)
        .onChange(of: data.isAlertMode) { _, isAlert in
            withAnimation(.easeInOut(duration: 0.3)) {
                cautionVisible = isAlert
            }
        }
        .onChange(of: isFire) { _, newValue in
            if newValue { startPullUpFlash() }
        }
        .onAppear {
            cautionVisible = data.isAlertMode
            if isFire { startPullUpFlash() }
        }
    }

    // MARK: - Cockpit Content

    private func cockpitContent(size: CGSize, isLandscape: Bool) -> some View {
        Group {
            if isLandscape {
                landscapeLayout(size: size)
            } else {
                portraitLayout(size: size)
            }
        }
    }

    // MARK: - Portrait Layout

    private func portraitLayout(size: CGSize) -> some View {
        let aiDiameter = min(size.width * 0.6, size.height * 0.35)

        return VStack(spacing: 12) {
            // Attitude indicator + flanking tapes
            HStack(spacing: 8) {
                altimeterTape(height: aiDiameter)
                    .frame(width: 40)
                attitudeIndicator(diameter: aiDiameter)
                headingTape(height: aiDiameter)
                    .frame(width: 40)
            }

            // Alert banner
            alertBanner(width: size.width * 0.8)

            // HUD advisory text
            if data.isAlertMode, let worst = data.worstOffender {
                advisoryCallout(worst: worst)
            }

            // Five metric gauges
            metricGaugeRow()
                .padding(.horizontal)
        }
        .padding(.top, 40)
    }

    // MARK: - Landscape Layout

    private func landscapeLayout(size: CGSize) -> some View {
        let aiDiameter = min(size.width * 0.35, size.height * 0.7)

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                altimeterTape(height: aiDiameter)
                    .frame(width: 44)
                attitudeIndicator(diameter: aiDiameter)
                headingTape(height: aiDiameter)
                    .frame(width: 44)
            }

            alertBanner(width: size.width * 0.5)

            if data.isAlertMode, let worst = data.worstOffender {
                advisoryCallout(worst: worst)
            }

            metricGaugeRow()
                .padding(.horizontal)
        }
    }

    // MARK: - Attitude Indicator

    private func attitudeIndicator(diameter: CGFloat) -> some View {
        let leanMetric = data.metrics.first(where: { $0.key == .lateralLean })
        let forwardMetric = data.metrics.first(where: { $0.key == .forwardCreep })
        let tiltAngle = Double(leanMetric?.clampedRatio ?? 0) * 30 * (data.isAlertMode ? 1.5 : 1.0)
        let pitchOffset = Double(forwardMetric?.clampedRatio ?? 0) * diameter * 0.2
        let skyColor: Color = data.postureState.isBad ? .red.opacity(0.6) : Color(hue: 0.55, saturation: 0.5, brightness: 0.7)

        return ZStack {
            // Sky / ground
            Canvas { context, canvasSize in
                let midY = canvasSize.height / 2 + pitchOffset
                // Sky
                let skyRect = CGRect(x: 0, y: 0, width: canvasSize.width, height: max(0, midY))
                context.fill(Path(skyRect), with: .color(skyColor))
                // Ground
                let groundRect = CGRect(x: 0, y: midY, width: canvasSize.width, height: canvasSize.height - midY)
                context.fill(Path(groundRect), with: .color(Color(hue: 0.08, saturation: 0.5, brightness: 0.4)))

                // Horizon line
                var horizon = Path()
                horizon.move(to: CGPoint(x: 0, y: midY))
                horizon.addLine(to: CGPoint(x: canvasSize.width, y: midY))
                context.stroke(horizon, with: .color(.white), lineWidth: 2)

                // Center reference marks
                let cx = canvasSize.width / 2
                var leftMark = Path()
                leftMark.move(to: CGPoint(x: cx - 40, y: canvasSize.height / 2))
                leftMark.addLine(to: CGPoint(x: cx - 15, y: canvasSize.height / 2))
                leftMark.addLine(to: CGPoint(x: cx - 15, y: canvasSize.height / 2 + 5))
                context.stroke(leftMark, with: .color(.white), lineWidth: 2)

                var rightMark = Path()
                rightMark.move(to: CGPoint(x: cx + 40, y: canvasSize.height / 2))
                rightMark.addLine(to: CGPoint(x: cx + 15, y: canvasSize.height / 2))
                rightMark.addLine(to: CGPoint(x: cx + 15, y: canvasSize.height / 2 + 5))
                context.stroke(rightMark, with: .color(.white), lineWidth: 2)
            }
            .rotationEffect(.degrees(tiltAngle))
            .clipShape(Circle())
            .animation(.spring(response: 0.5), value: tiltAngle)
            .animation(.spring(response: 0.5), value: pitchOffset)

            // Bezel
            Circle()
                .stroke(hudColor.opacity(0.4), lineWidth: 2)

            // Caution/Warning banner overlay
            if cautionVisible, let text = alertBannerText {
                VStack {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(alertBannerColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7))
                        .transition(.move(edge: .top))
                    Spacer()
                }
                .clipShape(Circle())
            }

            // PULL UP flash
            if pullUpFlash {
                Text("PULL UP")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.heavy)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.8))
            }
        }
        .frame(width: diameter, height: diameter)
    }

    // MARK: - Altimeter Tape

    private func altimeterTape(height: CGFloat) -> some View {
        let score = Int(data.aggregateScore * 100)

        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(hudColor.opacity(0.3), lineWidth: 1)
                )

            Canvas { context, canvasSize in
                let scorePosition = canvasSize.height * CGFloat(1.0 - data.aggregateScore)
                // Draw tape numbers
                for value in stride(from: 0, through: 100, by: 10) {
                    let y = canvasSize.height * CGFloat(1.0 - Double(value) / 100.0)
                    let text = Text("\(value)").font(.system(size: 8, design: .monospaced))
                    context.draw(text, at: CGPoint(x: canvasSize.width / 2, y: y))

                    var tick = Path()
                    tick.move(to: CGPoint(x: canvasSize.width - 6, y: y))
                    tick.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    context.stroke(tick, with: .color(hudColor.opacity(0.5)), lineWidth: 1)
                }

                // Pointer
                var pointer = Path()
                pointer.move(to: CGPoint(x: canvasSize.width, y: scorePosition))
                pointer.addLine(to: CGPoint(x: canvasSize.width - 8, y: scorePosition - 5))
                pointer.addLine(to: CGPoint(x: canvasSize.width - 8, y: scorePosition + 5))
                pointer.closeSubpath()
                context.fill(pointer, with: .color(hudColor))
            }
        }
        .frame(height: height)
    }

    // MARK: - Heading Tape (Time in State)

    private func headingTape(height: CGFloat) -> some View {
        let timeInState = Int(data.timeInCurrentState ?? 0)

        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(hudColor.opacity(0.3), lineWidth: 1)
                )

            VStack(spacing: 4) {
                Text("TIME")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(hudGreen)

                Text("\(timeInState)s")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(hudColor)
                    .monospacedDigit()
            }
        }
        .frame(height: height)
    }

    // MARK: - Alert Banner

    @ViewBuilder
    private func alertBanner(width: CGFloat) -> some View {
        if cautionVisible, let text = alertBannerText {
            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(alertBannerColor)
                .frame(width: width, height: 18)
                .background(alertBannerColor.opacity(0.15))
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Advisory Callout

    private func advisoryCallout(worst: MetricInfo) -> some View {
        HStack(spacing: 6) {
            Text("ADVISORY: \(worst.key.displayName.uppercased())")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(hudColor)

            if let seconds = data.nudgeCountdownSeconds {
                Text("T-\(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(alertBannerColor)
            }
        }
    }

    // MARK: - Metric Gauge Row

    private func metricGaugeRow() -> some View {
        HStack(spacing: 8) {
            ForEach(data.metrics, id: \.key) { metric in
                let isWorst = metric.isWorstOffender && data.isAlertMode

                VStack(spacing: 3) {
                    Text(abbreviation(for: metric.key))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(hudGreen)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(hudColor.opacity(0.15))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isWorst ? alertBannerColor : hudColor)
                                .frame(width: geo.size.width * CGFloat(metric.clampedRatio))
                        }
                    }
                    .frame(height: 6)
                    .overlay(
                        isWorst
                            ? RoundedRectangle(cornerRadius: 2)
                                .stroke(alertBannerColor, lineWidth: 1)
                                .opacity(0.7)
                            : nil
                    )

                    Text(String(format: "%03.0f", metric.clampedRatio * 100))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(hudColor)
                        .monospacedDigit()
                }
                .frame(maxWidth: isWorst ? .infinity : nil)
                .scaleEffect(x: isWorst ? 1.3 : 1.0, y: 1.0, anchor: .center)
                .animation(.spring(response: 0.4), value: isWorst)
            }
        }
    }

    // MARK: - Helpers

    private func abbreviation(for key: MetricKey) -> String {
        switch key {
        case .forwardCreep:     return "FWD"
        case .headDrop:         return "HDR"
        case .shoulderRounding: return "SHL"
        case .lateralLean:      return "LAT"
        case .twist:            return "TWS"
        }
    }

    private func startPullUpFlash() {
        Task { @MainActor in
            for _ in 0..<3 {
                withAnimation(.easeInOut(duration: 0.15)) { pullUpFlash = true }
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(.easeInOut(duration: 0.15)) { pullUpFlash = false }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant11View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant11View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant11View()
        .environmentObject(observer)
}
