import SwiftUI
import PostureLogic

/// Variant 25: Tensegrity — Rigid struts (bones) floating in a web of tension
/// cables (muscles/fascia). Good posture = balanced equilibrium with taut cables.
/// Bad posture = slack/overtight cables causing strut misalignment.
struct Variant25View: View {
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
                        tensegrityContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    tensegrityContent(size: geo.size, isLandscape: isLandscape)
                }

                // Settings gear
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

    private func tensegrityContent(size: CGSize, isLandscape: Bool) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio

        return ZStack {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height / 2

                let scale: CGFloat = min(canvasSize.width, canvasSize.height) / 400

                // Strut positions (parametric)
                let headDrop = CGFloat(hd) * 30 * scale
                let shoulderNarrow = CGFloat(sr) * 25 * scale
                let leanShift = CGFloat(ll) * 30 * scale
                let twistOffset = CGFloat(tw) * 15 * scale

                // Spine strut (vertical center)
                let spineTop = CGPoint(x: cx, y: cy - 80 * scale)
                let spineBottom = CGPoint(x: cx, y: cy + 80 * scale)

                // Head strut (short horizontal, above spine)
                let headY = cy - 110 * scale + headDrop
                let headLeft = CGPoint(x: cx - 20 * scale + leanShift, y: headY)
                let headRight = CGPoint(x: cx + 20 * scale + leanShift, y: headY)

                // Shoulder strut (horizontal, at upper spine)
                let shoulderY = cy - 50 * scale
                let shoulderLeft = CGPoint(x: cx - 55 * scale + shoulderNarrow + leanShift * 0.5 - twistOffset, y: shoulderY)
                let shoulderRight = CGPoint(x: cx + 55 * scale - shoulderNarrow + leanShift * 0.5 + twistOffset, y: shoulderY)

                // Pelvis strut (short horizontal, at spine bottom)
                let pelvisLeft = CGPoint(x: cx - 30 * scale, y: cy + 80 * scale)
                let pelvisRight = CGPoint(x: cx + 30 * scale, y: cy + 80 * scale)

                // Draw struts
                let strutStyle = StrokeStyle(lineWidth: 6 * scale, lineCap: .round)
                let strutColor: Color = .primary

                drawStrut(context: context, from: spineTop, to: spineBottom, color: strutColor, style: strutStyle)
                drawStrut(context: context, from: headLeft, to: headRight, color: strutColor, style: strutStyle)
                drawStrut(context: context, from: shoulderLeft, to: shoulderRight, color: strutColor, style: strutStyle)
                drawStrut(context: context, from: pelvisLeft, to: pelvisRight, color: strutColor, style: strutStyle)

                // Cables
                let forwardCreepTension = CGFloat(fc)
                let headDropTension = CGFloat(hd)
                let shoulderTension = CGFloat(sr)
                let leanTension = CGFloat(ll)
                let twistTension = CGFloat(tw)

                // Head-to-shoulder cables
                drawCable(context: context, from: headLeft, to: shoulderLeft, tension: 1.0 - headDropTension, scale: scale)
                drawCable(context: context, from: headRight, to: shoulderRight, tension: 1.0 - headDropTension, scale: scale)

                // Shoulder-to-spine cables (inner)
                drawCable(context: context, from: shoulderLeft, to: spineTop, tension: 1.0 - shoulderTension, scale: scale)
                drawCable(context: context, from: shoulderRight, to: spineTop, tension: 1.0 - shoulderTension, scale: scale)

                // Front cables (shoulder to pelvis)
                drawCable(context: context, from: shoulderLeft, to: pelvisLeft, tension: forwardCreepTension, scale: scale)
                drawCable(context: context, from: shoulderRight, to: pelvisRight, tension: forwardCreepTension, scale: scale)

                // Rear cables (shoulder to pelvis - crossed)
                drawCable(context: context, from: shoulderLeft, to: pelvisRight, tension: 1.0 - forwardCreepTension, scale: scale)
                drawCable(context: context, from: shoulderRight, to: pelvisLeft, tension: 1.0 - forwardCreepTension, scale: scale)

                // Lateral cables
                drawCable(context: context, from: headLeft, to: pelvisLeft, tension: leanTension > 0.5 ? leanTension : 1.0 - leanTension, scale: scale)
                drawCable(context: context, from: headRight, to: pelvisRight, tension: leanTension > 0.5 ? 1.0 - leanTension : leanTension, scale: scale)

                // Diagonal twist cables
                drawCable(context: context, from: shoulderLeft, to: spineBottom, tension: twistTension, scale: scale)
                drawCable(context: context, from: shoulderRight, to: spineBottom, tension: 1.0 - twistTension, scale: scale)

                // Alert glow on worst offender strut
                if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                    context.addFilter(.shadow(color: .red.opacity(0.5), radius: 8))
                    switch worst.key {
                    case .headDrop:
                        drawStrut(context: context, from: headLeft, to: headRight, color: .red, style: strutStyle)
                    case .shoulderRounding:
                        drawStrut(context: context, from: shoulderLeft, to: shoulderRight, color: .red, style: strutStyle)
                    case .forwardCreep:
                        drawStrut(context: context, from: spineTop, to: spineBottom, color: .red, style: strutStyle)
                    case .lateralLean, .twist:
                        drawStrut(context: context, from: pelvisLeft, to: pelvisRight, color: .red, style: strutStyle)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Label + countdown
            VStack {
                Spacer()
                if observer.data.isAlertMode {
                    if let worst = observer.data.worstOffender {
                        Text(worst.key.displayName)
                            .font(.caption.bold())
                            .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                    }
                    if let seconds = observer.data.nudgeCountdownSeconds {
                        countdownBar(seconds: seconds)
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func drawStrut(context: GraphicsContext, from: CGPoint, to: CGPoint, color: Color, style: StrokeStyle) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), style: style)
    }

    private func drawCable(context: GraphicsContext, from: CGPoint, to: CGPoint, tension: CGFloat, scale: CGFloat) {
        let clampedTension = max(0, min(1, tension))

        // Cable thickness: taut = thick, slack = thin
        let lineWidth = (0.5 + clampedTension * 2.5) * scale

        // Cable color: balanced = teal, overtight = red, slack = faded
        let color: Color
        if clampedTension > 0.7 {
            color = .red.opacity(0.7)
        } else if clampedTension > 0.3 {
            color = .teal
        } else {
            color = .secondary.opacity(0.2)
        }

        // Sag for slack cables (catenary approximation via quadratic bezier)
        let sagDepth = (1.0 - clampedTension) * 40 * scale
        let midX = (from.x + to.x) / 2
        let midY = (from.y + to.y) / 2 + sagDepth

        var cablePath = Path()
        cablePath.move(to: from)
        cablePath.addQuadCurve(to: to, control: CGPoint(x: midX, y: midY))

        context.stroke(cablePath, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }

    private func countdownBar(seconds: TimeInterval) -> some View {
        GeometryReader { geo in
            let fraction = CGFloat(min(seconds / 30.0, 1.0))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red)
                    .frame(width: geo.size.width * fraction, height: 4)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 40)
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant25View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant25View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant25View()
        .environmentObject(observer)
}
