import SwiftUI
import PostureLogic

/// Variant 34: Mirror Avatar — A friendly cartoon character that mirrors the user's
/// detected posture in real time. Round head with dot eyes that express concern as
/// posture degrades. Limbs deform to match posture metrics.
struct Variant34View: View {
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
                        avatarCanvas(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    avatarCanvas(size: geo.size, isLandscape: isLandscape)
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

    private func avatarCanvas(size: CGSize, isLandscape: Bool) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio
        let score = observer.data.aggregateScore

        return ZStack {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height * 0.45
                let s = min(canvasSize.width, canvasSize.height) * 0.003

                let bodyColor = Color.teal
                let headColor = Color(red: 0.95, green: 0.9, blue: 0.85)

                // Ground shadow
                let shadowX = cx + CGFloat(ll) * 15 * s
                let shadowY = cy + 110 * s
                let shadowW: CGFloat = 60 * s * (1.0 + CGFloat(fc) * 0.2)
                let shadowH: CGFloat = 10 * s
                let shadowRect = CGRect(x: shadowX - shadowW / 2, y: shadowY - shadowH / 2, width: shadowW, height: shadowH)
                context.fill(Path(ellipseIn: shadowRect), with: .color(.primary.opacity(0.08)))

                // Ground line
                var groundLine = Path()
                groundLine.move(to: CGPoint(x: cx - 80 * s, y: cy + 100 * s))
                groundLine.addLine(to: CGPoint(x: cx + 80 * s, y: cy + 100 * s))
                context.stroke(groundLine, with: .color(.secondary.opacity(0.2)), style: StrokeStyle(lineWidth: 1))

                // Body deformations
                let leanShift = CGFloat(ll) * 20 * s
                let forwardTilt = CGFloat(fc) * 15 * s
                let headDropY = CGFloat(hd) * 20 * s
                let shoulderNarrow = CGFloat(sr) * 10 * s
                let twistShift = CGFloat(tw) * 10 * s

                // Legs (planted, don't deform)
                for sign: CGFloat in [-1, 1] {
                    var leg = Path()
                    leg.move(to: CGPoint(x: cx + sign * 12 * s, y: cy + 50 * s))
                    leg.addLine(to: CGPoint(x: cx + sign * 14 * s, y: cy + 75 * s))
                    leg.addLine(to: CGPoint(x: cx + sign * 16 * s, y: cy + 100 * s))
                    context.stroke(leg, with: .color(bodyColor), style: StrokeStyle(lineWidth: 4 * s, lineCap: .round))
                    // Knee joint
                    let kneeR: CGFloat = 3 * s
                    let kneeRect = CGRect(x: cx + sign * 14 * s - kneeR, y: cy + 75 * s - kneeR, width: kneeR * 2, height: kneeR * 2)
                    context.fill(Path(ellipseIn: kneeRect), with: .color(bodyColor))
                }

                // Torso (deforms)
                let torsoX = cx + leanShift * 0.5 + forwardTilt * 0.3
                let torsoY = cy - 5 * s
                let torsoW: CGFloat = 50 * s - shoulderNarrow * 0.5
                let torsoH: CGFloat = 55 * s
                let torsoRect = CGRect(x: torsoX - torsoW / 2, y: torsoY - torsoH / 2, width: torsoW, height: torsoH)
                context.fill(Path(roundedRect: torsoRect, cornerRadius: 12 * s), with: .color(bodyColor))

                // Arms
                let shoulderY = torsoY - torsoH / 2 + 5 * s
                for sign: CGFloat in [-1, 1] {
                    let shoulderX = torsoX + sign * (torsoW / 2) + sign * twistShift * (sign > 0 ? 0.5 : -0.5)
                    let elbowX = shoulderX + sign * 10 * s
                    let elbowY = shoulderY + 30 * s
                    let handX = elbowX + sign * 5 * s
                    let handY = elbowY + 25 * s

                    var arm = Path()
                    arm.move(to: CGPoint(x: shoulderX, y: shoulderY))
                    arm.addLine(to: CGPoint(x: elbowX, y: elbowY))
                    arm.addLine(to: CGPoint(x: handX, y: handY))
                    context.stroke(arm, with: .color(bodyColor), style: StrokeStyle(lineWidth: 3.5 * s, lineCap: .round))

                    // Shoulder + elbow joints
                    for (jx, jy) in [(shoulderX, shoulderY), (elbowX, elbowY)] {
                        let r: CGFloat = 3 * s
                        context.fill(Path(ellipseIn: CGRect(x: jx - r, y: jy - r, width: r * 2, height: r * 2)), with: .color(bodyColor))
                    }
                }

                // Neck
                let neckX = torsoX + forwardTilt * 0.5 + leanShift * 0.3
                let neckTopY = torsoY - torsoH / 2 - 8 * s
                var neck = Path()
                neck.move(to: CGPoint(x: torsoX, y: torsoY - torsoH / 2))
                neck.addLine(to: CGPoint(x: neckX, y: neckTopY))
                context.stroke(neck, with: .color(headColor.opacity(0.8)), style: StrokeStyle(lineWidth: 4 * s, lineCap: .round))

                // Head
                let headX = neckX + forwardTilt * 0.5 + leanShift * 0.3
                let headY = neckTopY - 22 * s + headDropY
                let headR: CGFloat = 22 * s
                let headRect = CGRect(x: headX - headR, y: headY - headR, width: headR * 2, height: headR * 2)
                context.fill(Path(ellipseIn: headRect), with: .color(headColor))

                // Eyes
                let eyeY = headY - 3 * s + CGFloat(hd) * 4 * s
                let eyeSpacing: CGFloat = 8 * s
                let eyeR: CGFloat = score > 0.4 ? 3 * s : 3.5 * s
                for sign: CGFloat in [-1, 1] {
                    let eyeX = headX + sign * eyeSpacing
                    let eyeRect = CGRect(x: eyeX - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2)
                    context.fill(Path(ellipseIn: eyeRect), with: .color(.primary.opacity(0.8)))
                }

                // Eyebrows (express concern)
                let browY = eyeY - 5 * s
                let browAngle: CGFloat = score > 0.7 ? 0 : (score > 0.4 ? 5 : 12)
                for sign: CGFloat in [-1, 1] {
                    let browX = headX + sign * eyeSpacing
                    var brow = Path()
                    brow.move(to: CGPoint(x: browX - 4 * s, y: browY + (sign < 0 ? browAngle * 0.3 : -browAngle * 0.3)))
                    brow.addLine(to: CGPoint(x: browX + 4 * s, y: browY - (sign < 0 ? browAngle * 0.3 : -browAngle * 0.3)))
                    context.stroke(brow, with: .color(.primary.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Alert speech bubble
            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                VStack {
                    HStack {
                        Text(worst.key.displayName)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.ultraThinMaterial)
                            )
                        Spacer()
                    }
                    .padding(.leading, 30)
                    .padding(.top, 60)
                    Spacer()
                }

                if let seconds = observer.data.nudgeCountdownSeconds {
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
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant34View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .lateralLean,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant34View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant34View()
        .environmentObject(observer)
}
