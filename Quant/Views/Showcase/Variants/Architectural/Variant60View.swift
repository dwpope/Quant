import SwiftUI
import PostureLogic

/// Variant 60: Suspension Bridge — A side-view elevation drawing of a suspension bridge
/// whose structural integrity reflects posture quality. Blueprint aesthetic with cable tension,
/// deck sag, and tower lean driven by the five metrics.
struct Variant60View: View {
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

    // Blueprint colors
    private let blueprintBg = Color(red: 0.03, green: 0.1, blue: 0.25)
    private let blueprintLine = Color(red: 0.4, green: 0.6, blue: 0.9)
    private let stressColor = Color(red: 0.9, green: 0.4, blue: 0.2)

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                blueprintBg.ignoresSafeArea()

                if isAbsent {
                    AbsenceOverlay {
                        bridgeContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    bridgeContent(size: geo.size, isLandscape: isLandscape)
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

    private func bridgeContent(size: CGSize, isLandscape: Bool) -> some View {
        VStack(spacing: 0) {
            // Load test bar
            if let seconds = observer.data.nudgeCountdownSeconds {
                loadTestBar(seconds: seconds, width: size.width - 48)
                    .padding(.top, 40)
                    .padding(.horizontal, 24)
            }

            Spacer()

            // Bridge canvas
            bridgeCanvas(size: CGSize(
                width: size.width * 0.92,
                height: size.height * (isLandscape ? 0.65 : 0.5)
            ))

            Spacer()

            // Metric legend
            if isLandscape {
                metricLegend(width: size.width - 48)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            } else {
                compactLegend
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Bridge Canvas

    private func bridgeCanvas(size: CGSize) -> some View {
        let fc = ratio(for: .forwardCreep)
        let hd = ratio(for: .headDrop)
        let sr = ratio(for: .shoulderRounding)
        let ll = ratio(for: .lateralLean)
        let tw = ratio(for: .twist)

        return Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            // Grid background
            drawGrid(context: &context, size: canvasSize)

            let deckY = h * 0.7
            let towerHeight = h * 0.55

            // Tower positions
            let tower1X = w * 0.3
            let tower2X = w * 0.7

            // Tower lean from shoulder rounding (inward lean)
            let srLean = CGFloat(sr) * w * 0.03
            // Lateral lean: asymmetric tower heights
            let llAdjust = CGFloat(ll) * h * 0.06
            // Twist: towers lean in opposite directions
            let twistLean = CGFloat(tw) * w * 0.025

            let tower1TopX = tower1X + srLean + twistLean
            let tower2TopX = tower2X - srLean - twistLean
            let tower1TopY = deckY - towerHeight + llAdjust
            let tower2TopY = deckY - towerHeight - llAdjust

            // Deck line (with forward creep sag)
            let deckSag = CGFloat(fc) * h * 0.1
            drawDeck(context: &context, w: w, deckY: deckY, sag: deckSag, ll: ll)

            // Towers
            drawTower(context: &context, baseX: tower1X, baseY: deckY,
                      topX: tower1TopX, topY: tower1TopY, stress: max(sr, tw))
            drawTower(context: &context, baseX: tower2X, baseY: deckY,
                      topX: tower2TopX, topY: tower2TopY, stress: max(sr, tw))

            // Main cable (catenary)
            let cableDroop = CGFloat(hd) * h * 0.12
            drawMainCable(context: &context, w: w,
                          tower1Top: CGPoint(x: tower1TopX, y: tower1TopY),
                          tower2Top: CGPoint(x: tower2TopX, y: tower2TopY),
                          droop: cableDroop)

            // Suspender cables
            drawSuspenders(context: &context, w: w, deckY: deckY, deckSag: deckSag,
                           tower1Top: CGPoint(x: tower1TopX, y: tower1TopY),
                           tower2Top: CGPoint(x: tower2TopX, y: tower2TopY),
                           cableDroop: cableDroop, fc: fc, ll: ll)

            // Load arrows
            drawLoadArrows(context: &context, deckY: deckY, w: w)

            // Worst offender label
            if let worst = observer.data.worstOffender, observer.data.isAlertMode {
                let text = Text(worst.key.displayName)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                context.draw(text, at: CGPoint(x: w / 2, y: deckY + h * 0.12))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Grid

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 24
        let color = blueprintLine.opacity(0.08)

        var gridPath = Path()
        // Vertical lines
        var x: CGFloat = 0
        while x <= size.width {
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        // Horizontal lines
        var y: CGFloat = 0
        while y <= size.height {
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        context.stroke(gridPath, with: .color(color), style: StrokeStyle(lineWidth: 0.5))
    }

    // MARK: - Deck

    private func drawDeck(context: inout GraphicsContext, w: CGFloat, deckY: CGFloat, sag: CGFloat, ll: Float) {
        let tilt = CGFloat(ll) * 8
        var deckPath = Path()
        deckPath.move(to: CGPoint(x: 0, y: deckY + tilt))
        deckPath.addQuadCurve(
            to: CGPoint(x: w, y: deckY - tilt),
            control: CGPoint(x: w / 2, y: deckY + sag)
        )
        context.stroke(deckPath, with: .color(blueprintLine),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))

        // Truss cross-bracing below deck
        let trussH: CGFloat = 12
        let trussCount = 12
        let trussSpacing = w / CGFloat(trussCount)
        var trussPath = Path()
        for i in 0..<trussCount {
            let x1 = CGFloat(i) * trussSpacing
            let x2 = x1 + trussSpacing
            let y1 = deckY + 2
            trussPath.move(to: CGPoint(x: x1, y: y1))
            trussPath.addLine(to: CGPoint(x: x2, y: y1 + trussH))
            trussPath.move(to: CGPoint(x: x2, y: y1))
            trussPath.addLine(to: CGPoint(x: x1, y: y1 + trussH))
        }
        // Bottom chord
        trussPath.move(to: CGPoint(x: 0, y: deckY + 2 + trussH))
        trussPath.addLine(to: CGPoint(x: w, y: deckY + 2 + trussH))

        context.stroke(trussPath, with: .color(blueprintLine.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 0.8))
    }

    // MARK: - Towers

    private func drawTower(context: inout GraphicsContext,
                           baseX: CGFloat, baseY: CGFloat,
                           topX: CGFloat, topY: CGFloat,
                           stress: Float) {
        let halfW: CGFloat = 10
        let topHalfW: CGFloat = 6
        let color = stress > 0.7 ? stressColor : blueprintLine

        var tower = Path()
        tower.move(to: CGPoint(x: baseX - halfW, y: baseY))
        tower.addLine(to: CGPoint(x: topX - topHalfW, y: topY))
        tower.addLine(to: CGPoint(x: topX + topHalfW, y: topY))
        tower.addLine(to: CGPoint(x: baseX + halfW, y: baseY))
        tower.closeSubpath()

        context.stroke(tower, with: .color(color),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // Cross beam on tower
        let crossY = topY + (baseY - topY) * 0.3
        let crossHalfW = topHalfW + (halfW - topHalfW) * 0.3
        var cross = Path()
        let crossLeftX = baseX - crossHalfW + (topX - baseX) * 0.3
        let crossRightX = baseX + crossHalfW + (topX - baseX) * 0.3
        cross.move(to: CGPoint(x: crossLeftX, y: crossY))
        cross.addLine(to: CGPoint(x: crossRightX, y: crossY))
        context.stroke(cross, with: .color(color.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.5))
    }

    // MARK: - Main Cable

    private func drawMainCable(context: inout GraphicsContext, w: CGFloat,
                                tower1Top: CGPoint, tower2Top: CGPoint,
                                droop: CGFloat) {
        let anchorLeft = CGPoint(x: 0, y: tower1Top.y + 10)
        let anchorRight = CGPoint(x: w, y: tower2Top.y + 10)

        // Left span: anchor to tower1
        var leftSpan = Path()
        leftSpan.move(to: anchorLeft)
        leftSpan.addQuadCurve(to: tower1Top,
                               control: CGPoint(x: tower1Top.x / 2, y: tower1Top.y + droop * 0.5))
        context.stroke(leftSpan, with: .color(blueprintLine),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // Center span: tower1 to tower2
        let midY = max(tower1Top.y, tower2Top.y) + droop + 20
        var centerSpan = Path()
        centerSpan.move(to: tower1Top)
        centerSpan.addQuadCurve(to: tower2Top,
                                 control: CGPoint(x: (tower1Top.x + tower2Top.x) / 2, y: midY))
        context.stroke(centerSpan, with: .color(blueprintLine),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // Right span: tower2 to anchor
        var rightSpan = Path()
        rightSpan.move(to: tower2Top)
        rightSpan.addQuadCurve(to: anchorRight,
                                control: CGPoint(x: (tower2Top.x + w) / 2, y: tower2Top.y + droop * 0.5))
        context.stroke(rightSpan, with: .color(blueprintLine),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    // MARK: - Suspender Cables

    private func drawSuspenders(context: inout GraphicsContext, w: CGFloat, deckY: CGFloat,
                                 deckSag: CGFloat,
                                 tower1Top: CGPoint, tower2Top: CGPoint,
                                 cableDroop: CGFloat, fc: Float, ll: Float) {
        let count = 10
        let startX = tower1Top.x
        let endX = tower2Top.x
        let span = endX - startX

        for i in 0...count {
            let t = CGFloat(i) / CGFloat(count)
            let x = startX + t * span

            // Cable top point (on catenary)
            let midControlY = max(tower1Top.y, tower2Top.y) + cableDroop + 20
            let cableY = quadBezierY(t: t, p0y: tower1Top.y, p1y: midControlY, p2y: tower2Top.y)

            // Deck point (with sag)
            let deckLocalY = deckY + deckSag * 4 * t * (1 - t)  // Parabolic sag
            let deckTilt = CGFloat(ll) * 8 * (1 - 2 * (x / w))

            let bottomY = deckLocalY + deckTilt

            // Slack cable if cable is below deck
            let isSlack = cableY > bottomY - 5
            let tension = isSlack ? 0 : 1 - CGFloat(fc) * 0.5

            let cableColor: Color = isSlack ? blueprintLine.opacity(0.2) : (tension < 0.3 ? stressColor : blueprintLine.opacity(0.6))

            var suspender = Path()
            suspender.move(to: CGPoint(x: x, y: cableY))
            suspender.addLine(to: CGPoint(x: x, y: bottomY))
            context.stroke(suspender, with: .color(cableColor),
                           style: StrokeStyle(lineWidth: 1, dash: isSlack ? [3, 3] : []))
        }
    }

    private func quadBezierY(t: CGFloat, p0y: CGFloat, p1y: CGFloat, p2y: CGFloat) -> CGFloat {
        let mt = 1 - t
        return mt * mt * p0y + 2 * mt * t * p1y + t * t * p2y
    }

    // MARK: - Load Arrows

    private func drawLoadArrows(context: inout GraphicsContext, deckY: CGFloat, w: CGFloat) {
        let keys = MetricKey.allCases
        let spacing = w / CGFloat(keys.count + 1)

        for (i, key) in keys.enumerated() {
            let r = ratio(for: key)
            guard r > 0.05 else { continue }

            let x = spacing * CGFloat(i + 1)
            let arrowH = CGFloat(r) * 30

            var arrow = Path()
            arrow.move(to: CGPoint(x: x, y: deckY - arrowH - 20))
            arrow.addLine(to: CGPoint(x: x, y: deckY - 15))
            // Arrowhead
            arrow.move(to: CGPoint(x: x - 4, y: deckY - 22))
            arrow.addLine(to: CGPoint(x: x, y: deckY - 15))
            arrow.addLine(to: CGPoint(x: x + 4, y: deckY - 22))

            let color: Color = r > 0.8 ? .red : (r > 0.5 ? stressColor : blueprintLine.opacity(0.5))
            context.stroke(arrow, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: - Load Test Bar

    private func loadTestBar(seconds: TimeInterval, width: CGFloat) -> some View {
        let maxSeconds: Double = 30
        let elapsed = maxSeconds - min(seconds, maxSeconds)
        let percentage = min(elapsed / maxSeconds, 1.0) * 100

        return VStack(spacing: 4) {
            HStack {
                Text("LOAD TEST: \(Int(percentage))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(percentage > 80 ? .red : blueprintLine)
                Spacer()
                Text("Critical in \(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(blueprintLine.opacity(0.15))
                    .frame(width: width, height: 6)

                RoundedRectangle(cornerRadius: 2)
                    .fill(percentage > 80 ? .red : stressColor)
                    .frame(width: width * percentage / 100, height: 6)
            }
        }
    }

    // MARK: - Legends

    private func metricLegend(width: CGFloat) -> some View {
        HStack(spacing: 16) {
            ForEach(MetricKey.allCases) { key in
                let r = ratio(for: key)
                HStack(spacing: 4) {
                    Circle()
                        .fill(r > 0.8 ? .red : r > 0.5 ? stressColor : blueprintLine)
                        .frame(width: 6, height: 6)
                    Text(key.displayName)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(String(format: "%.0f%%", r * 100))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private var compactLegend: some View {
        HStack(spacing: 10) {
            ForEach(MetricKey.allCases) { key in
                let r = ratio(for: key)
                VStack(spacing: 2) {
                    Text(String(key.displayName.prefix(3)).uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(r > 0.8 ? .red : blueprintLine.opacity(0.7))
                    Text(String(format: "%.0f", r * 100))
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant60View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .shoulderRounding,
        worstRatio: 0.9
    )
    let observer = PostureDisplayObserver(source: source)
    Variant60View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant60View()
        .environmentObject(observer)
}
