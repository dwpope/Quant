import SwiftUI
import PostureLogic

/// Variant 30: Wire Skeleton — A wireframe body outline drawn with thin bright lines
/// tracing the edges of a simplified human form. TRON-style digital aesthetic with
/// visible vertices at joint locations. Deformations warp the wireframe.
struct Variant30View: View {
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
                // Dark background for wireframe aesthetic
                Color(red: 0.02, green: 0.04, blue: 0.08)
                    .ignoresSafeArea()

                if isAbsent {
                    AbsenceOverlay {
                        wireframeCanvas(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    wireframeCanvas(size: geo.size, isLandscape: isLandscape)
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

    private func wireframeCanvas(size: CGSize, isLandscape: Bool) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio

        return ZStack {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height * 0.45
                let s = min(canvasSize.width, canvasSize.height) * 0.003

                let wireColor = Color.teal
                let dimColor = Color.teal.opacity(0.15)

                // Grid floor
                let floorY = cy + 100 * s
                drawGridFloor(context: context, centerX: cx, floorY: floorY, width: canvasSize.width * 0.6, scale: s, color: dimColor)

                // Compute skeleton vertices
                let joints = MannequinJoints.compute(
                    center: CGPoint(x: cx, y: cy), scale: s,
                    fc: CGFloat(fc), hd: CGFloat(hd), sr: CGFloat(sr),
                    ll: CGFloat(ll), tw: CGFloat(tw), isLandscape: isLandscape
                )

                // Head octagon
                drawOctagon(context: context, center: joints.head, radius: 14 * s, color: wireColor)

                // Torso wireframe
                let torsoLines: [(CGPoint, CGPoint)] = [
                    (joints.leftShoulder, joints.rightShoulder),
                    (joints.leftShoulder, CGPoint(x: joints.hip.x - 15 * s, y: joints.hip.y)),
                    (joints.rightShoulder, CGPoint(x: joints.hip.x + 15 * s, y: joints.hip.y)),
                    (CGPoint(x: joints.hip.x - 15 * s, y: joints.hip.y), CGPoint(x: joints.hip.x + 15 * s, y: joints.hip.y)),
                    // Cross braces
                    (joints.leftShoulder, CGPoint(x: joints.hip.x + 15 * s, y: joints.hip.y)),
                    (joints.rightShoulder, CGPoint(x: joints.hip.x - 15 * s, y: joints.hip.y)),
                    // Spine
                    (joints.neck, joints.chest),
                    (joints.chest, joints.hip),
                ]
                for (from, to) in torsoLines {
                    drawWireLine(context: context, from: from, to: to, color: wireColor, width: 1.5)
                }

                // Limbs
                let limbLines: [(CGPoint, CGPoint)] = [
                    (joints.neck, joints.head),
                    (joints.leftShoulder, joints.leftElbow),
                    (joints.rightShoulder, joints.rightElbow),
                    (joints.hip, joints.leftKnee),
                    (joints.hip, joints.rightKnee),
                ]
                for (from, to) in limbLines {
                    drawWireLine(context: context, from: from, to: to, color: wireColor, width: 1.5)
                }

                // Joint dots
                let allJoints = [joints.hip, joints.chest, joints.neck,
                                 joints.leftShoulder, joints.rightShoulder,
                                 joints.leftElbow, joints.rightElbow,
                                 joints.leftKnee, joints.rightKnee]
                for pt in allJoints {
                    let r: CGFloat = 3 * s
                    let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(wireColor))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .shadow(color: .teal.opacity(0.3), radius: 4)

            // Countdown
            if observer.data.isAlertMode, let seconds = observer.data.nudgeCountdownSeconds {
                VStack {
                    Spacer()
                    Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.teal.opacity(0.8))
                        .padding(.bottom, 20)
                }
            }

            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                VStack {
                    Text(worst.key.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(.teal)
                    Spacer()
                }
                .padding(.top, 40)
            }
        }
    }

    private func drawWireLine(context: GraphicsContext, from: CGPoint, to: CGPoint, color: Color, width: CGFloat) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width))
    }

    private func drawOctagon(context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        var path = Path()
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 - .pi / 2
            let pt = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5))
    }

    private func drawGridFloor(context: GraphicsContext, centerX: CGFloat, floorY: CGFloat, width: CGFloat, scale: CGFloat, color: Color) {
        let gridLines = 10
        let spacing = width / CGFloat(gridLines)
        for i in 0...gridLines {
            let x = centerX - width / 2 + CGFloat(i) * spacing
            var path = Path()
            path.move(to: CGPoint(x: x, y: floorY))
            path.addLine(to: CGPoint(x: x, y: floorY + width * 0.3))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 0.5))
        }
        let depthLines = 4
        let depthSpacing = width * 0.3 / CGFloat(depthLines)
        for i in 0...depthLines {
            let y = floorY + CGFloat(i) * depthSpacing
            var path = Path()
            path.move(to: CGPoint(x: centerX - width / 2, y: y))
            path.addLine(to: CGPoint(x: centerX + width / 2, y: y))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 0.5))
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant30View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .shoulderRounding,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant30View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant30View()
        .environmentObject(observer)
}
