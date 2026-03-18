import SwiftUI
import PostureLogic

/// Variant 33: Spine Column — An isolated visualization of the spinal column as a
/// vertical chain of 7 vertebra-like rounded rectangles. The spine curves and twists
/// in real time based on posture metrics with color-coded stress per region.
struct Variant33View: View {
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
                        spineCanvas(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    spineCanvas(size: geo.size, isLandscape: isLandscape)
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

    private func spineCanvas(size: CGSize, isLandscape: Bool) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio

        return ZStack {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height * 0.5
                let s = min(canvasSize.width, canvasSize.height) * 0.003

                let vertebrae = computeVertebrae(
                    cx: cx, cy: cy, scale: s,
                    fc: CGFloat(fc), hd: CGFloat(hd), sr: CGFloat(sr),
                    ll: CGFloat(ll), tw: CGFloat(tw), isLandscape: isLandscape
                )

                // Spinal cord line
                if vertebrae.count >= 2 {
                    var cordPath = Path()
                    cordPath.move(to: vertebrae[0].position)
                    for v in vertebrae.dropFirst() {
                        cordPath.addLine(to: v.position)
                    }
                    context.stroke(cordPath, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 1))
                }

                // Vertebrae
                for v in vertebrae {
                    context.drawLayer { ctx in
                        ctx.translateBy(x: v.position.x, y: v.position.y)
                        ctx.rotate(by: v.rotation)
                        let rect = CGRect(x: -v.width / 2, y: -6 * s, width: v.width, height: 12 * s)
                        let roundedRect = Path(roundedRect: rect, cornerRadius: 4 * s)
                        ctx.fill(roundedRect, with: .color(v.color))
                        ctx.stroke(roundedRect, with: .color(v.color.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5))
                    }
                }

                // Head circle on top
                let headCenter: CGPoint
                if let top = vertebrae.first {
                    headCenter = CGPoint(x: top.position.x, y: top.position.y - 25 * s + CGFloat(hd) * 15 * s)
                } else {
                    headCenter = CGPoint(x: cx, y: cy - 120 * s)
                }
                let headR: CGFloat = 14 * s
                let headColor = stressColor(fc: CGFloat(hd), threshold: 0.5)
                let headRect = CGRect(x: headCenter.x - headR, y: headCenter.y - headR, width: headR * 2, height: headR * 2)
                context.fill(Path(ellipseIn: headRect), with: .color(headColor.opacity(0.3)))
                context.stroke(Path(ellipseIn: headRect), with: .color(headColor), style: StrokeStyle(lineWidth: 2))

                // Region labels
                let regions = ["C", "C", "T", "T", "T", "L", "L"]
                for (i, v) in vertebrae.enumerated() {
                    let label = regions[i]
                    let labelX = v.position.x - 40 * s
                    context.draw(
                        Text(label).font(.system(size: 9 * s, weight: .light, design: .monospaced)).foregroundColor(.secondary.opacity(0.5)),
                        at: CGPoint(x: labelX, y: v.position.y)
                    )
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

    private struct VertebraData {
        let position: CGPoint
        let rotation: Angle
        let width: CGFloat
        let color: Color
    }

    private func computeVertebrae(cx: CGFloat, cy: CGFloat, scale s: CGFloat,
                                   fc: CGFloat, hd: CGFloat, sr: CGFloat,
                                   ll: CGFloat, tw: CGFloat, isLandscape: Bool) -> [VertebraData] {
        let count = 7
        let spacing: CGFloat = 22 * s
        let baseWidth: CGFloat = 30 * s
        let startY = cy - CGFloat(count / 2) * spacing

        var vertebrae: [VertebraData] = []
        for i in 0..<count {
            let t = CGFloat(i) / CGFloat(count - 1) // 0 (top/cervical) to 1 (bottom/lumbar)
            let inverseT = 1.0 - t // top vertebrae affected more by progressive offset

            // Forward creep: progressive forward curve (top moves most)
            let forwardOffset = fc * 25 * s * inverseT

            // Lateral lean: progressive sideways displacement
            let lateralOffset = ll * 25 * s * inverseT

            // Twist: progressive alternating horizontal displacement
            let twistDisp = tw * 10 * s * inverseT * (i % 2 == 0 ? 1.0 : -1.0)

            // Head drop compresses cervical region
            let headDropComp = (i < 2) ? hd * 8 * s : 0

            let x = cx + forwardOffset + lateralOffset + twistDisp
            let y = startY + CGFloat(i) * spacing + headDropComp

            // Rotation from twist
            let rotation = Angle(degrees: Double(tw * 8 * inverseT * (i % 2 == 0 ? 1 : -1)))

            // Width varies: thoracic slightly wider
            let widthMod: CGFloat = (2...4).contains(i) ? 1.1 + sr * 0.2 : 1.0
            let width = baseWidth * widthMod

            // Color: stress level based on region
            let stress: CGFloat
            if i < 2 { // cervical
                stress = max(hd, fc) * 0.7 + sr * 0.3
            } else if i < 5 { // thoracic
                stress = max(sr, fc) * 0.7 + tw * 0.3
            } else { // lumbar
                stress = (fc + hd + sr + ll + tw) / 5.0
            }
            let color = stressColor(fc: stress, threshold: 0.6)

            vertebrae.append(VertebraData(position: CGPoint(x: x, y: y), rotation: rotation, width: width, color: color))
        }
        return vertebrae
    }

    private func stressColor(fc: CGFloat, threshold: CGFloat) -> Color {
        if fc < threshold * 0.5 {
            return .green
        } else if fc < threshold {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant33View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.9
    )
    let observer = PostureDisplayObserver(source: source)
    Variant33View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant33View()
        .environmentObject(observer)
}
