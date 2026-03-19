import SwiftUI
import PostureLogic

/// Variant 42: Tree of Life — A stylized tree with woodcut aesthetic whose anatomy maps to body anatomy.
/// Trunk is the spine, branches are the shoulders, canopy is the head, roots are the base.
/// Uses stroke-only rendering (no fills) with grain lines for a printmaking quality.
struct Variant42View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var fallingLeaves: [FallingLeaf] = []

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
                        treeCanvas(size: geo.size)
                    }
                } else {
                    treeCanvas(size: geo.size)
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

    private func treeCanvas(size: CGSize) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio
        let isBad = observer.data.postureState.isBad

        return ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isAbsent || !isBad)) { timeline in
                Canvas { context, canvasSize in
                    let cx = canvasSize.width / 2
                    let s = min(canvasSize.width, canvasSize.height) * 0.003
                    let groundY = canvasSize.height * 0.75
                    let trunkBase = groundY
                    let trunkTop = canvasSize.height * 0.30
                    let trunkHeight = trunkBase - trunkTop
                    let strokeStyle = StrokeStyle(lineWidth: 3, lineCap: .round)
                    let treeColor: Color = .primary.opacity(0.8)

                    // Lean: trunk tilts
                    let leanShift = CGFloat(ll) * 25 * s

                    // --- Ground line ---
                    var groundLine = Path()
                    groundLine.move(to: CGPoint(x: 0, y: groundY))
                    groundLine.addLine(to: CGPoint(x: canvasSize.width, y: groundY))
                    context.stroke(groundLine, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 1.5))

                    // --- Trunk (two parallel wavy lines) ---
                    let trunkWidth: CGFloat = 12 * s
                    let forwardBend = CGFloat(fc) * 30 * s

                    func trunkX(at frac: CGFloat, side: CGFloat) -> CGFloat {
                        let baseX = cx + leanShift * frac
                        let taper = trunkWidth * (1.0 - frac * 0.3) / 2 * side
                        let bend = forwardBend * frac * frac
                        let noise = sin(frac * 7.3 + side * 2) * 1.5 * s
                        return baseX + taper + bend + noise
                    }

                    for side: CGFloat in [-1, 1] {
                        var trunkPath = Path()
                        trunkPath.move(to: CGPoint(x: trunkX(at: 0, side: side), y: trunkBase))
                        for step in stride(from: 0.05, through: 1.0, by: 0.05) {
                            let frac = CGFloat(step)
                            trunkPath.addLine(to: CGPoint(x: trunkX(at: frac, side: side), y: trunkBase - frac * trunkHeight))
                        }
                        context.stroke(trunkPath, with: .color(treeColor), style: strokeStyle)
                    }

                    // --- Grain lines (parallel thin lines along trunk) ---
                    for i in 0..<5 {
                        let grainSide = CGFloat(i - 2) / 3 * 0.5
                        var grainPath = Path()
                        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
                            let frac = CGFloat(step)
                            let x = trunkX(at: frac, side: grainSide)
                            let noiseOff = sin(frac * 13.1 + CGFloat(i) * 3.7) * s
                            let pt = CGPoint(x: x + noiseOff, y: trunkBase - frac * trunkHeight)
                            if step < 0.01 { grainPath.move(to: pt) } else { grainPath.addLine(to: pt) }
                        }

                        // Twist: make grain lines spiral
                        if tw > 0.1 {
                            let spiralStyle = StrokeStyle(lineWidth: 0.3, dash: [3, 2])
                            context.stroke(grainPath, with: .color(treeColor.opacity(0.3)), style: spiralStyle)
                        } else {
                            context.stroke(grainPath, with: .color(treeColor.opacity(0.2)), style: StrokeStyle(lineWidth: 0.3))
                        }
                    }

                    // --- Main branches (two, from top of trunk) ---
                    let branchAttachY = trunkTop + trunkHeight * 0.1
                    let branchAttachX = cx + leanShift
                    let branchDroop = CGFloat(sr) * 40 * s // Shoulder rounding droops branches
                    let branchLen: CGFloat = 50 * s
                    let twistLen = CGFloat(tw) * 15 * s

                    for side: CGFloat in [-1, 1] {
                        let baseAngle: CGFloat = side > 0 ? -0.52 : (.pi + 0.52) // ~30 deg from horizontal
                        let droopAngle = baseAngle + side * branchDroop / branchLen
                        let endX = branchAttachX + (branchLen + side * twistLen) * cos(droopAngle)
                        let endY = branchAttachY + (branchLen + side * twistLen) * sin(droopAngle)

                        var branchPath = Path()
                        branchPath.move(to: CGPoint(x: branchAttachX, y: branchAttachY))
                        let cp = CGPoint(x: (branchAttachX + endX) / 2, y: branchAttachY - 5 * s + branchDroop * 0.5)
                        branchPath.addQuadCurve(to: CGPoint(x: endX, y: endY), control: cp)
                        context.stroke(branchPath, with: .color(treeColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                        // Sub-branches
                        for subIdx in 0..<2 {
                            let subFrac = CGFloat(subIdx + 1) / 3
                            let subStartX = branchAttachX + (endX - branchAttachX) * subFrac
                            let subStartY = branchAttachY + (endY - branchAttachY) * subFrac
                            let subLen: CGFloat = 15 * s
                            let subAngle = droopAngle + side * 0.4
                            var subPath = Path()
                            subPath.move(to: CGPoint(x: subStartX, y: subStartY))
                            subPath.addLine(to: CGPoint(x: subStartX + subLen * cos(subAngle),
                                                         y: subStartY + subLen * sin(subAngle)))
                            context.stroke(subPath, with: .color(treeColor.opacity(0.6)),
                                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        }

                        // Stress marks at junction when shoulder rounding
                        if sr > 0.3 {
                            for j in 0..<3 {
                                let markLen: CGFloat = 4 * s
                                let markAngle = droopAngle + .pi / 2
                                let offset = CGFloat(j - 1) * 3 * s
                                var mark = Path()
                                mark.move(to: CGPoint(x: branchAttachX + offset, y: branchAttachY - markLen / 2))
                                mark.addLine(to: CGPoint(x: branchAttachX + offset, y: branchAttachY + markLen / 2))
                                context.stroke(mark, with: .color(treeColor.opacity(Double(sr) * 0.5)),
                                               style: StrokeStyle(lineWidth: 0.8))
                            }
                        }
                    }

                    // --- Canopy (12-point polygon) ---
                    let canopyRadius: CGFloat = 40 * s * (1.0 - CGFloat(hd) * 0.4)
                    let canopyCenterX = cx + leanShift + forwardBend * 0.8
                    let canopyCenterY = trunkTop - 5 * s + CGFloat(hd) * 20 * s

                    var canopyPath = Path()
                    for i in 0..<12 {
                        let angle = CGFloat(i) * .pi * 2 / 12
                        let radiusVar = canopyRadius * (1.0 + sin(CGFloat(i) * 3.7) * 0.15)
                        let pt = CGPoint(x: canopyCenterX + radiusVar * cos(angle),
                                         y: canopyCenterY + radiusVar * sin(angle) * 0.8)
                        if i == 0 { canopyPath.move(to: pt) } else { canopyPath.addLine(to: pt) }
                    }
                    canopyPath.closeSubpath()
                    context.stroke(canopyPath, with: .color(treeColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                    // --- Roots (mirror branches below ground) ---
                    for side: CGFloat in [-1, 1] {
                        let rootAngle: CGFloat = side > 0 ? 0.4 : (.pi - 0.4)
                        let rootLen: CGFloat = 30 * s
                        var rootPath = Path()
                        rootPath.move(to: CGPoint(x: cx, y: trunkBase))
                        let endPt = CGPoint(x: cx + rootLen * cos(rootAngle),
                                            y: trunkBase + rootLen * sin(rootAngle))
                        let ctrl = CGPoint(x: (cx + endPt.x) / 2, y: trunkBase + 5 * s)
                        rootPath.addQuadCurve(to: endPt, control: ctrl)
                        context.stroke(rootPath, with: .color(treeColor.opacity(0.5)),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }

                    // --- Fruit indicators in canopy (5 rings) ---
                    let metrics: [(MetricKey, Float)] = [
                        (.forwardCreep, fc), (.headDrop, hd), (.shoulderRounding, sr),
                        (.lateralLean, ll), (.twist, tw)
                    ]
                    for (idx, (_, ratio)) in metrics.enumerated() {
                        let angle = CGFloat(idx) * .pi * 2 / 5 - .pi / 2
                        let fruitR: CGFloat = canopyRadius * 0.55
                        let fruitX = canopyCenterX + fruitR * cos(angle)
                        let fruitY = canopyCenterY + fruitR * sin(angle) * 0.8
                        let ringSize: CGFloat = 6 * s

                        // Ring outline
                        context.stroke(Path(ellipseIn: CGRect(x: fruitX - ringSize, y: fruitY - ringSize,
                                                                width: ringSize * 2, height: ringSize * 2)),
                                       with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 1))

                        // Ring fill
                        let fillAngle = CGFloat(min(ratio, 1.0)) * .pi * 2
                        if fillAngle > 0.01 {
                            var fillArc = Path()
                            fillArc.addArc(center: CGPoint(x: fruitX, y: fruitY), radius: ringSize,
                                           startAngle: .degrees(-90), endAngle: .degrees(-90 + Double(fillAngle) * 180 / .pi),
                                           clockwise: false)
                            context.stroke(fillArc, with: .color(PostureVisualStyle.metricColor(ratio: ratio)),
                                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        }
                    }

                    // --- Falling leaves (bad state) ---
                    if isBad {
                        let now = timeline.date.timeIntervalSinceReferenceDate
                        for leaf in fallingLeaves {
                            let elapsed = now - leaf.startTime
                            let leafY = leaf.startY + CGFloat(elapsed) * leaf.speed
                            let leafX = leaf.startX + sin(CGFloat(elapsed) * 2 + leaf.phase) * 10 * s
                            let wrappedY = leafY.truncatingRemainder(dividingBy: canvasSize.height)

                            var leafPath = Path()
                            leafPath.move(to: CGPoint(x: leafX, y: wrappedY))
                            leafPath.addLine(to: CGPoint(x: leafX - 4 * s, y: wrappedY + 6 * s))
                            leafPath.addLine(to: CGPoint(x: leafX + 4 * s, y: wrappedY + 6 * s))
                            leafPath.closeSubpath()
                            context.fill(leafPath, with: .color(treeColor.opacity(0.4)))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Alert overlay
            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                VStack {
                    Spacer()
                    Text(worst.key.displayName)
                        .font(.system(.caption, design: .serif).bold())
                        .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                        .opacity(0.7)

                    if let seconds = observer.data.nudgeCountdownSeconds {
                        Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear { initFallingLeaves() }
    }

    private func initFallingLeaves() {
        fallingLeaves = (0..<8).map { i in
            FallingLeaf(
                startX: CGFloat.random(in: 50...300),
                startY: CGFloat.random(in: -100...0),
                speed: CGFloat.random(in: 20...40),
                phase: CGFloat.random(in: 0...(.pi * 2)),
                startTime: Date.timeIntervalSinceReferenceDate - Double.random(in: 0...5)
            )
        }
    }
}

struct FallingLeaf {
    let startX: CGFloat
    let startY: CGFloat
    let speed: CGFloat
    let phase: CGFloat
    let startTime: TimeInterval
}

private extension PostureState {
    var isBad: Bool {
        switch self {
        case .bad: return true
        default: return false
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant42View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .shoulderRounding,
        worstRatio: 0.8
    )
    let observer = PostureDisplayObserver(source: source)
    Variant42View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant42View()
        .environmentObject(observer)
}
