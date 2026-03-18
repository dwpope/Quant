import SwiftUI
import PostureLogic

/// Variant 38: Compass Rose — A nautical/orienteering compass with ornate rose at center.
/// The needle points north when posture is perfect. As posture degrades, the needle
/// deflects using atan2(lateralLean, forwardCreep) for true 2D directional encoding.
struct Variant38View: View {
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
                        compassCanvas(size: geo.size)
                    }
                } else {
                    compassCanvas(size: geo.size)
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

    private func compassCanvas(size: CGSize) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio

        return ZStack {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height * 0.45
                let diameter = min(canvasSize.width, canvasSize.height) * 0.75
                let radius = diameter / 2

                // Severity zones
                let zoneRadii: [(CGFloat, Color)] = [
                    (radius, Color.red.opacity(0.08)),
                    (radius * 0.67, Color.yellow.opacity(0.1)),
                    (radius * 0.33, Color.green.opacity(0.12)),
                ]
                for (r, color) in zoneRadii {
                    let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }

                // Compass rose (8-point star)
                drawCompassRose(context: context, cx: cx, cy: cy, radius: radius * 0.25)

                // Degree ring (rotates with twist)
                context.drawLayer { ctx in
                    ctx.translateBy(x: cx, y: cy)
                    ctx.rotate(by: .degrees(Double(-tw) * 20))
                    ctx.translateBy(x: -cx, y: -cy)

                    for deg in stride(from: 0, to: 360, by: 5) {
                        let angle = Angle(degrees: Double(deg) - 90)
                        let cosA = CGFloat(cos(angle.radians))
                        let sinA = CGFloat(sin(angle.radians))
                        let outerR = radius * 0.95
                        let innerR = (deg % 30 == 0) ? radius * 0.88 : radius * 0.91
                        let outerPt = CGPoint(x: cx + outerR * cosA, y: cy + outerR * sinA)
                        let innerPt = CGPoint(x: cx + innerR * cosA, y: cy + innerR * sinA)
                        var tick = Path()
                        tick.move(to: outerPt)
                        tick.addLine(to: innerPt)
                        ctx.stroke(tick, with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: deg % 30 == 0 ? 1.5 : 0.5))

                        if deg % 30 == 0 {
                            let labelR = radius * 0.82
                            let labelPt = CGPoint(x: cx + labelR * cosA, y: cy + labelR * sinA)
                            ctx.draw(
                                Text("\(deg)").font(.system(size: 8, weight: .light, design: .monospaced)).foregroundColor(.secondary.opacity(0.5)),
                                at: labelPt
                            )
                        }
                    }
                }

                // Cardinal labels (fixed, don't rotate)
                let cardinals: [(String, Double)] = [("N", -90), ("E", 0), ("S", 90), ("W", 180)]
                for (label, deg) in cardinals {
                    let angle = Angle(degrees: deg)
                    let labelR = radius * 1.08
                    let pt = CGPoint(x: cx + labelR * CGFloat(cos(angle.radians)), y: cy + labelR * CGFloat(sin(angle.radians)))
                    context.draw(
                        Text(label).font(.system(size: 14, weight: .bold, design: .serif)).foregroundColor(.primary),
                        at: pt
                    )
                }

                // Compass needle
                let needleAngle = atan2(CGFloat(ll), CGFloat(fc)) // direction of deviation
                let needleDeviation = hypot(CGFloat(fc), CGFloat(ll)) // magnitude
                let needleLength = radius * 0.7

                // Needle shaft thickness increases with shoulder rounding
                let needleWidth: CGFloat = 3 + CGFloat(sr) * 3

                // Needle bow from shoulder rounding
                let bowOffset = CGFloat(sr) * 8

                // North half (red) and south half (white)
                context.drawLayer { ctx in
                    ctx.translateBy(x: cx, y: cy)
                    ctx.rotate(by: .radians(Double(needleAngle)))
                    ctx.translateBy(x: -cx, y: -cy)

                    // North half (red) — points in deviation direction
                    var northPath = Path()
                    northPath.move(to: CGPoint(x: cx, y: cy))
                    northPath.addQuadCurve(
                        to: CGPoint(x: cx, y: cy - needleLength * min(needleDeviation + 0.2, 1.0)),
                        control: CGPoint(x: cx + bowOffset, y: cy - needleLength * 0.5)
                    )
                    ctx.stroke(northPath, with: .color(.red), style: StrokeStyle(lineWidth: needleWidth, lineCap: .round))

                    // Arrowhead
                    var arrowhead = Path()
                    let tipY = cy - needleLength * min(needleDeviation + 0.2, 1.0)
                    arrowhead.move(to: CGPoint(x: cx, y: tipY))
                    arrowhead.addLine(to: CGPoint(x: cx - 5, y: tipY + 10))
                    arrowhead.addLine(to: CGPoint(x: cx + 5, y: tipY + 10))
                    arrowhead.closeSubpath()
                    ctx.fill(arrowhead, with: .color(.red))

                    // South half (silver)
                    var southPath = Path()
                    southPath.move(to: CGPoint(x: cx, y: cy))
                    southPath.addLine(to: CGPoint(x: cx, y: cy + needleLength * 0.4))
                    ctx.stroke(southPath, with: .color(.gray), style: StrokeStyle(lineWidth: needleWidth * 0.7, lineCap: .round))
                }

                // Center pin
                let pinRect = CGRect(x: cx - 4, y: cy - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: pinRect), with: .color(.primary))

                // Head drop bead on needle
                if hd > 0.05 {
                    let beadDist = CGFloat(hd) * needleLength * 0.3
                    let beadAngle = Double(needleAngle) + .pi
                    let beadX = cx + beadDist * cos(beadAngle)
                    let beadY = cy + beadDist * sin(beadAngle)
                    let beadRect = CGRect(x: beadX - 3, y: beadY - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: beadRect), with: .color(.orange))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Alert info
            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                VStack {
                    Spacer()
                    Text(worst.key.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                        .padding(.bottom, 8)
                    if let seconds = observer.data.nudgeCountdownSeconds {
                        Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    private func drawCompassRose(context: GraphicsContext, cx: CGFloat, cy: CGFloat, radius: CGFloat) {
        var path = Path()
        for i in 0..<8 {
            let angle = Angle(degrees: Double(i) * 45 - 90)
            let r = (i % 2 == 0) ? radius : radius * 0.5
            let pt = CGPoint(x: cx + r * CGFloat(cos(angle.radians)), y: cy + r * CGFloat(sin(angle.radians)))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        context.fill(path, with: .color(.secondary.opacity(0.15)))
        context.stroke(path, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 1))
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant38View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant38View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant38View()
        .environmentObject(observer)
}
