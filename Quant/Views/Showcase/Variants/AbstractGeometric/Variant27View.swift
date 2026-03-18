import SwiftUI
import PostureLogic

/// Variant 27: Bauhaus Figure — Inspired by Oskar Schlemmer's geometric figure studies.
/// A frontal figure of pure outlines: circle (head), triangle (torso), lines (axes),
/// circles (joints). Monoline aesthetic with reference grid. Forward creep fills the torso.
struct Variant27View: View {
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
                        bauhausContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    bauhausContent(size: geo.size, isLandscape: isLandscape)
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

    private func bauhausContent(size: CGSize, isLandscape: Bool) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio

        let strokeWidth: CGFloat = 2
        let isAlert = observer.data.isAlertMode

        return ZStack {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height / 2
                let s = min(canvasSize.width, canvasSize.height) / 350

                // Reference grid (fades in alert)
                let gridOpacity = isAlert ? 0.0 : 0.08
                if gridOpacity > 0 {
                    for offset in stride(from: -150 * s, through: 150 * s, by: 30 * s) {
                        var hLine = Path()
                        hLine.move(to: CGPoint(x: cx - 150 * s, y: cy + offset))
                        hLine.addLine(to: CGPoint(x: cx + 150 * s, y: cy + offset))
                        context.stroke(hLine, with: .color(.secondary.opacity(gridOpacity)), style: StrokeStyle(lineWidth: 0.5))

                        var vLine = Path()
                        vLine.move(to: CGPoint(x: cx + offset, y: cy - 150 * s))
                        vLine.addLine(to: CGPoint(x: cx + offset, y: cy + 150 * s))
                        context.stroke(vLine, with: .color(.secondary.opacity(gridOpacity)), style: StrokeStyle(lineWidth: 0.5))
                    }
                }

                // Lean tilt transform
                let tiltAngle = CGFloat(ll) * 12
                let tiltTransform = CGAffineTransform(translationX: cx, y: cy)
                    .rotated(by: Angle(degrees: Double(tiltAngle)).radians)
                    .translatedBy(x: -cx, y: -cy)

                // Torso triangle
                let shoulderHalfWidth = (60 - CGFloat(sr) * 30) * s
                let torsoTop = CGPoint(x: cx, y: cy - 40 * s)
                let triangleTopLeft = CGPoint(x: cx - shoulderHalfWidth, y: cy - 40 * s)
                let triangleTopRight = CGPoint(x: cx + shoulderHalfWidth, y: cy - 40 * s)
                let triangleBottom = CGPoint(x: cx, y: cy + 70 * s)

                // Filled torso (opacity = forward creep ratio)
                var filledTriangle = Path()
                filledTriangle.move(to: triangleTopLeft.applying(tiltTransform))
                filledTriangle.addLine(to: triangleTopRight.applying(tiltTransform))
                filledTriangle.addLine(to: triangleBottom.applying(tiltTransform))
                filledTriangle.closeSubpath()
                context.fill(filledTriangle, with: .color(.primary.opacity(Double(fc) * 0.8)))

                // Torso outline
                let worstKey = observer.data.worstOffender?.key
                let torsoStrokeColor: Color = (isAlert && worstKey == .forwardCreep) ? .red : .primary
                let torsoStrokeWidth: CGFloat = (isAlert && worstKey == .forwardCreep) ? 3 : strokeWidth
                context.stroke(filledTriangle, with: .color(torsoStrokeColor), style: StrokeStyle(lineWidth: torsoStrokeWidth))

                // Head circle
                let headRadius = (20 - CGFloat(hd) * 3) * s
                let headCenterY = cy - 70 * s + CGFloat(hd) * 30 * s
                let headCenter = CGPoint(x: cx, y: headCenterY).applying(tiltTransform)
                let headPath = Path(ellipseIn: CGRect(
                    x: headCenter.x - headRadius, y: headCenter.y - headRadius,
                    width: headRadius * 2, height: headRadius * 2
                ))
                let headColor: Color = (isAlert && worstKey == .headDrop) ? .red : .primary
                let headStrokeWidth: CGFloat = (isAlert && worstKey == .headDrop) ? 3 : strokeWidth
                context.stroke(headPath, with: .color(headColor), style: StrokeStyle(lineWidth: headStrokeWidth))

                // Shoulder line
                let shoulderLineColor: Color = (isAlert && worstKey == .shoulderRounding) ? .red : .primary
                var shoulderLine = Path()
                shoulderLine.move(to: triangleTopLeft.applying(tiltTransform))
                shoulderLine.addLine(to: triangleTopRight.applying(tiltTransform))
                context.stroke(shoulderLine, with: .color(shoulderLineColor), style: StrokeStyle(lineWidth: strokeWidth))

                // Shoulder joint circles (asymmetric size from twist)
                let leftJointR = (6 + CGFloat(tw) * 4) * s
                let rightJointR = (6 - CGFloat(tw) * 3) * s
                let leftJoint = triangleTopLeft.applying(tiltTransform)
                let rightJoint = triangleTopRight.applying(tiltTransform)

                let jointColor: Color = (isAlert && worstKey == .twist) ? .red : .primary
                context.stroke(
                    Path(ellipseIn: CGRect(x: leftJoint.x - leftJointR, y: leftJoint.y - leftJointR, width: leftJointR * 2, height: leftJointR * 2)),
                    with: .color(jointColor),
                    style: StrokeStyle(lineWidth: strokeWidth)
                )
                context.stroke(
                    Path(ellipseIn: CGRect(x: rightJoint.x - rightJointR, y: rightJoint.y - rightJointR, width: rightJointR * 2, height: rightJointR * 2)),
                    with: .color(jointColor),
                    style: StrokeStyle(lineWidth: strokeWidth)
                )

                // Spine axis (vertical center line)
                let spineColor: Color = (isAlert && worstKey == .lateralLean) ? .red : .primary
                var spinePath = Path()
                spinePath.move(to: CGPoint(x: cx, y: headCenterY - headRadius).applying(tiltTransform))
                spinePath.addLine(to: triangleBottom.applying(tiltTransform))
                context.stroke(
                    spinePath,
                    with: .color(spineColor.opacity(0.5)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bauhaus-style labels
            if !isAbsent {
                bauhausLabels(size: size)
            }

            // Alert countdown
            if isAlert {
                VStack {
                    Spacer()
                    if let worst = observer.data.worstOffender {
                        Text(worst.key.displayName.uppercased())
                            .font(.system(.title2, design: .default).smallCaps())
                            .tracking(3)
                            .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                    }
                    if let seconds = observer.data.nudgeCountdownSeconds {
                        Text(String(format: "%.1f", seconds))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 30)
            }
        }
    }

    private func bauhausLabels(size: CGSize) -> some View {
        let labels: [(String, CGFloat, CGFloat)] = [
            ("CREEP", 0.82, 0.55),
            ("DROP", 0.50, 0.22),
            ("ROUND", 0.50, 0.35),
            ("LEAN", 0.20, 0.50),
            ("TWIST", 0.82, 0.35)
        ]

        return ZStack {
            ForEach(labels, id: \.0) { label, xFrac, yFrac in
                let isWorst = observer.data.isAlertMode && observer.data.worstOffender?.key.displayName.uppercased().hasPrefix(label) == true
                Text(label)
                    .font(.system(.caption2, design: .default).smallCaps())
                    .tracking(2)
                    .foregroundStyle(.primary.opacity(isWorst ? 0.8 : 0.15))
                    .position(x: size.width * xFrac, y: size.height * yFrac)
            }
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant27View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.9
    )
    let observer = PostureDisplayObserver(source: source)
    Variant27View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant27View()
        .environmentObject(observer)
}
