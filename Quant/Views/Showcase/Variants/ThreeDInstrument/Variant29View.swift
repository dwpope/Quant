import SwiftUI
import PostureLogic

/// Variant 29: SceneKit Mannequin — A programmatic 3D-style stick-figure mannequin
/// built from simple shapes. Joints are spheres, bones are cylinders/lines.
/// Deforms pose in real time based on posture metrics with a ghost reference pose.
struct Variant29View: View {
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
                        mannequinCanvas(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    mannequinCanvas(size: geo.size, isLandscape: isLandscape)
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

    private func mannequinCanvas(size: CGSize, isLandscape: Bool) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio

        return ZStack {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height * 0.45
                let scale: CGFloat = min(canvasSize.width, canvasSize.height) * 0.003

                let joints = MannequinJoints.compute(
                    center: CGPoint(x: cx, y: cy),
                    scale: scale,
                    fc: CGFloat(fc), hd: CGFloat(hd), sr: CGFloat(sr),
                    ll: CGFloat(ll), tw: CGFloat(tw),
                    isLandscape: isLandscape
                )

                // Draw ghost (ideal pose) at 8% opacity
                let ghostJoints = MannequinJoints.compute(
                    center: CGPoint(x: cx, y: cy),
                    scale: scale,
                    fc: 0, hd: 0, sr: 0, ll: 0, tw: 0,
                    isLandscape: isLandscape
                )
                drawMannequin(context: context, joints: ghostJoints, color: .secondary, opacity: 0.08, jointRadius: 4 * scale, boneWidth: 2 * scale)

                // Draw active mannequin
                let score = observer.data.aggregateScore
                let tint: Color = score > 0.7 ? .blue : (score > 0.4 ? .orange : .red)
                drawMannequin(context: context, joints: joints, color: tint, opacity: 1.0, jointRadius: 5 * scale, boneWidth: 2.5 * scale)

                // Alert glow
                if observer.data.isAlertMode {
                    context.addFilter(.shadow(color: .red.opacity(0.3), radius: 8))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Metric labels at bottom
            if !isAbsent {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        ForEach(MetricKey.allCases) { key in
                            let info = observer.data.metric(for: key)
                            VStack(spacing: 2) {
                                Image(systemName: key.symbolName)
                                    .font(.caption2)
                                Text(String(format: "%.0f%%", info.clampedRatio * 100))
                                    .font(.caption2.monospacedDigit())
                            }
                            .foregroundStyle(PostureVisualStyle.metricColor(ratio: info.clampedRatio))
                        }
                    }
                    .padding(.bottom, 16)
                }
            }

            // Countdown
            if observer.data.isAlertMode, let seconds = observer.data.nudgeCountdownSeconds {
                VStack {
                    Spacer()
                    Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 40)
                }
            }

            // Worst offender label
            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                VStack {
                    Text(worst.key.displayName)
                        .font(.headline.bold())
                        .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                    Spacer()
                }
                .padding(.top, 40)
            }
        }
    }

    private func drawMannequin(context: GraphicsContext, joints: MannequinJoints, color: Color, opacity: Double, jointRadius: CGFloat, boneWidth: CGFloat) {
        let boneColor = color.opacity(opacity)
        let jointColor = color.opacity(opacity * 0.8)

        // Bones
        let bones: [(CGPoint, CGPoint)] = [
            (joints.hip, joints.chest),
            (joints.chest, joints.neck),
            (joints.neck, joints.head),
            (joints.chest, joints.leftShoulder),
            (joints.chest, joints.rightShoulder),
            (joints.leftShoulder, joints.leftElbow),
            (joints.rightShoulder, joints.rightElbow),
            (joints.hip, joints.leftKnee),
            (joints.hip, joints.rightKnee),
        ]

        for (from, to) in bones {
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(boneColor), style: StrokeStyle(lineWidth: boneWidth, lineCap: .round))
        }

        // Joints
        let allJoints = [joints.hip, joints.chest, joints.neck, joints.head,
                         joints.leftShoulder, joints.rightShoulder,
                         joints.leftElbow, joints.rightElbow,
                         joints.leftKnee, joints.rightKnee]
        for pt in allJoints {
            let r = pt == joints.head ? jointRadius * 2.5 : jointRadius
            let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(jointColor))
        }
    }
}

// MARK: - Joint Computation

struct MannequinJoints {
    var hip: CGPoint
    var chest: CGPoint
    var neck: CGPoint
    var head: CGPoint
    var leftShoulder: CGPoint
    var rightShoulder: CGPoint
    var leftElbow: CGPoint
    var rightElbow: CGPoint
    var leftKnee: CGPoint
    var rightKnee: CGPoint

    static func compute(
        center: CGPoint,
        scale: CGFloat,
        fc: CGFloat, hd: CGFloat, sr: CGFloat, ll: CGFloat, tw: CGFloat,
        isLandscape: Bool
    ) -> MannequinJoints {
        let spineForward = fc * 30 * scale
        let headDropOffset = hd * 25 * scale
        let shoulderInward = sr * 15 * scale
        let leanOffset = ll * 25 * scale
        let twistOffset = tw * 20 * scale

        let hipY = center.y + 80 * scale
        let chestY = center.y
        let neckY = center.y - 30 * scale
        let headY = center.y - 55 * scale + headDropOffset

        let hip = CGPoint(x: center.x, y: hipY)
        let chest = CGPoint(x: center.x + spineForward * 0.5 + leanOffset * 0.3, y: chestY)
        let neck = CGPoint(x: center.x + spineForward * 0.8 + leanOffset * 0.6, y: neckY)
        let head = CGPoint(x: center.x + spineForward + leanOffset * 0.8, y: headY)

        let shoulderWidth: CGFloat = 40 * scale - shoulderInward
        let leftShoulder = CGPoint(
            x: chest.x - shoulderWidth - twistOffset * 0.5,
            y: chestY - 5 * scale
        )
        let rightShoulder = CGPoint(
            x: chest.x + shoulderWidth + twistOffset * 0.5,
            y: chestY - 5 * scale
        )

        let leftElbow = CGPoint(x: leftShoulder.x - 5 * scale, y: leftShoulder.y + 40 * scale)
        let rightElbow = CGPoint(x: rightShoulder.x + 5 * scale, y: rightShoulder.y + 40 * scale)

        let leftKnee = CGPoint(x: hip.x - 20 * scale, y: hipY + 60 * scale)
        let rightKnee = CGPoint(x: hip.x + 20 * scale, y: hipY + 60 * scale)

        return MannequinJoints(
            hip: hip, chest: chest, neck: neck, head: head,
            leftShoulder: leftShoulder, rightShoulder: rightShoulder,
            leftElbow: leftElbow, rightElbow: rightElbow,
            leftKnee: leftKnee, rightKnee: rightKnee
        )
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant29View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.9
    )
    let observer = PostureDisplayObserver(source: source)
    Variant29View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant29View()
        .environmentObject(observer)
}
