import SwiftUI
import PostureLogic

/// Variant 35: Attitude Indicator — Aviation artificial horizon instrument. Upper half
/// sky blue, lower half earth brown. A center aircraft symbol stays fixed while the
/// horizon tilts for roll, shifts for pitch, and compass ring rotates for yaw.
struct Variant35View: View {
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
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        attitudeCanvas(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    attitudeCanvas(size: geo.size, isLandscape: isLandscape)
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

    private func attitudeCanvas(size: CGSize, isLandscape: Bool) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio

        return ZStack {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height * 0.45
                let diameter = min(canvasSize.width, canvasSize.height) * 0.7
                let radius = diameter / 2

                let pitchOffset = CGFloat(fc) * 25 // degrees — horizon drops
                let rollAngle = CGFloat(ll) * 30 // degrees — horizon tilts
                let yawAngle = CGFloat(tw) * 20 // degrees — compass ring rotates
                let headDotDrop = CGFloat(hd) * 15
                let wingDroop = CGFloat(sr) * 8

                // Clip to instrument face circle
                let clipRect = CGRect(x: cx - radius, y: cy - radius, width: diameter, height: diameter)
                let clipPath = Path(ellipseIn: clipRect)

                context.drawLayer { ctx in
                    ctx.clip(to: clipPath)

                    // Rotate sky/ground assembly for roll
                    ctx.translateBy(x: cx, y: cy)
                    ctx.rotate(by: .degrees(Double(-rollAngle)))
                    ctx.translateBy(x: -cx, y: -cy)

                    // Shift for pitch
                    let pitchPixels = pitchOffset * radius / 45

                    // Sky (upper half)
                    let skyGradient = Gradient(colors: [
                        Color.blue,
                        Color.cyan.opacity(0.8)
                    ])
                    let skyRect = CGRect(x: cx - radius * 2, y: cy - radius * 3 + pitchPixels, width: radius * 4, height: radius * 3)
                    ctx.fill(Path(skyRect), with: .linearGradient(skyGradient, startPoint: CGPoint(x: cx, y: cy - radius * 3 + pitchPixels), endPoint: CGPoint(x: cx, y: cy + pitchPixels)))

                    // Ground (lower half)
                    let groundGradient = Gradient(colors: [
                        Color(red: 0.6, green: 0.4, blue: 0.2),
                        Color.brown
                    ])
                    let groundRect = CGRect(x: cx - radius * 2, y: cy + pitchPixels, width: radius * 4, height: radius * 3)
                    ctx.fill(Path(groundRect), with: .linearGradient(groundGradient, startPoint: CGPoint(x: cx, y: cy + pitchPixels), endPoint: CGPoint(x: cx, y: cy + radius * 3 + pitchPixels)))

                    // Horizon line
                    var horizonLine = Path()
                    horizonLine.move(to: CGPoint(x: cx - radius * 2, y: cy + pitchPixels))
                    horizonLine.addLine(to: CGPoint(x: cx + radius * 2, y: cy + pitchPixels))
                    ctx.stroke(horizonLine, with: .color(.white), style: StrokeStyle(lineWidth: 2))

                    // Pitch lines
                    for deg in stride(from: -20.0, through: 20.0, by: 5.0) where deg != 0 {
                        let lineY = cy + pitchPixels - deg * radius / 45
                        let lineHalf: CGFloat = (Int(deg) % 10 == 0) ? radius * 0.2 : radius * 0.1
                        var pitchLine = Path()
                        pitchLine.move(to: CGPoint(x: cx - lineHalf, y: lineY))
                        pitchLine.addLine(to: CGPoint(x: cx + lineHalf, y: lineY))
                        ctx.stroke(pitchLine, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1))
                    }
                }

                // Bank angle indicator arc at top
                let bankArcRadius = radius * 0.92
                for deg in [10.0, 20.0, 30.0, 45.0, -10.0, -20.0, -30.0, -45.0] {
                    let angle = Angle(degrees: -90 + deg)
                    let cosA = CGFloat(cos(angle.radians))
                    let sinA = CGFloat(sin(angle.radians))
                    let tickStart = CGPoint(
                        x: cx + bankArcRadius * cosA,
                        y: cy + bankArcRadius * sinA
                    )
                    let tickEnd = CGPoint(
                        x: cx + (bankArcRadius - 8) * cosA,
                        y: cy + (bankArcRadius - 8) * sinA
                    )
                    var tick = Path()
                    tick.move(to: tickStart)
                    tick.addLine(to: tickEnd)
                    context.stroke(tick, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1))
                }

                // Bank angle triangle pointer
                let bankPointerAngle = Angle(degrees: -90 - Double(rollAngle))
                let bankPointerTip = CGPoint(
                    x: cx + (bankArcRadius - 12) * CGFloat(cos(bankPointerAngle.radians)),
                    y: cy + (bankArcRadius - 12) * CGFloat(sin(bankPointerAngle.radians))
                )
                let bankPointerR: CGFloat = 4
                let pRect = CGRect(x: bankPointerTip.x - bankPointerR, y: bankPointerTip.y - bankPointerR, width: bankPointerR * 2, height: bankPointerR * 2)
                context.fill(Path(ellipseIn: pRect), with: .color(.white))

                // Center aircraft symbol (fixed)
                var wingPath = Path()
                wingPath.move(to: CGPoint(x: cx - radius * 0.3, y: cy + wingDroop))
                wingPath.addQuadCurve(to: CGPoint(x: cx + radius * 0.3, y: cy + wingDroop),
                                      control: CGPoint(x: cx, y: cy - wingDroop * 0.5))
                context.stroke(wingPath, with: .color(.orange), style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // Center dot
                let centerDot = CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: centerDot), with: .color(.orange))

                // Head dot (drops with head drop)
                let headDotY = cy - 15 + headDotDrop
                let headDot = CGRect(x: cx - 2.5, y: headDotY - 2.5, width: 5, height: 5)
                context.fill(Path(ellipseIn: headDot), with: .color(.white))

                // Compass ring
                let compassRadius = radius * 1.02
                context.drawLayer { ctx in
                    ctx.translateBy(x: cx, y: cy)
                    ctx.rotate(by: .degrees(Double(-yawAngle)))
                    ctx.translateBy(x: -cx, y: -cy)

                    let cardinals = ["N", "E", "S", "W"]
                    for (i, label) in cardinals.enumerated() {
                        let angle = Angle(degrees: Double(i) * 90 - 90)
                        let labelPt = CGPoint(
                            x: cx + (compassRadius + 12) * CGFloat(cos(angle.radians)),
                            y: cy + (compassRadius + 12) * CGFloat(sin(angle.radians))
                        )
                        ctx.draw(
                            Text(label).font(.system(size: 10, weight: .bold, design: .serif)).foregroundColor(.secondary),
                            at: labelPt
                        )
                    }

                    // Degree ticks
                    for deg in stride(from: 0, to: 360, by: 10) {
                        let angle = Angle(degrees: Double(deg) - 90)
                        let cosA = CGFloat(cos(angle.radians))
                        let sinA = CGFloat(sin(angle.radians))
                        let outerPt = CGPoint(x: cx + compassRadius * cosA, y: cy + compassRadius * sinA)
                        let innerPt = CGPoint(x: cx + (compassRadius - 5) * cosA, y: cy + (compassRadius - 5) * sinA)
                        var tick = Path()
                        tick.move(to: outerPt)
                        tick.addLine(to: innerPt)
                        ctx.stroke(tick, with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 0.8))
                    }
                }

                // Bezel
                context.stroke(clipPath, with: .color(observer.data.isAlertMode ? .red.opacity(0.6) : .gray),
                               style: StrokeStyle(lineWidth: 4))

                // Mounting screws
                let screwPositions: [(CGFloat, CGFloat)] = [(0, -1), (1, 0), (0, 1), (-1, 0)]
                for (dx, dy) in screwPositions {
                    let screwCenter = CGPoint(x: cx + dx * (radius + 6), y: cy + dy * (radius + 6))
                    let screwRect = CGRect(x: screwCenter.x - 3, y: screwCenter.y - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: screwRect), with: .color(.gray.opacity(0.5)))
                }

                // Alert warning flag
                if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                    let flagRect = CGRect(x: cx + radius * 0.25, y: cy - radius * 0.6, width: 50, height: 18)
                    context.fill(Path(flagRect), with: .color(.red))
                    context.draw(
                        Text(worst.key.displayName).font(.system(size: 8, weight: .bold)).foregroundColor(.white),
                        at: CGPoint(x: flagRect.midX, y: flagRect.midY)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Countdown via compass arc
            if observer.data.isAlertMode, let seconds = observer.data.nudgeCountdownSeconds {
                VStack {
                    Spacer()
                    Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 20)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant35View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant35View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant35View()
        .environmentObject(observer)
}
