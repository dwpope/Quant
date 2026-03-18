import SwiftUI
import PostureLogic

/// Variant 36: Spirit Level — Three digital spirit levels (bubble levels) at head,
/// shoulder, and hip heights of a simplified body outline. Each contains a floating
/// bubble that rests at center when aligned. A vertical plumb line connects the three.
struct Variant36View: View {
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
                        spiritLevelCanvas(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    spiritLevelCanvas(size: geo.size, isLandscape: isLandscape)
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

    private func spiritLevelCanvas(size: CGSize, isLandscape: Bool) -> some View {
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

                // Faint body outline
                drawFaintBody(context: context, cx: cx, cy: cy, scale: s)

                // Spirit level dimensions
                let tubeW: CGFloat = 120 * s
                let tubeH: CGFloat = 24 * s
                let maxBubbleTravel = (tubeW - tubeH) / 2

                // Level positions
                let headLevelY = cy - 80 * s + CGFloat(hd) * 15 * s
                let shoulderLevelY = cy - 20 * s
                let hipLevelY = cy + 40 * s

                // Bubble displacements
                let headBubbleX = CGFloat(ll) * maxBubbleTravel + CGFloat(fc) * maxBubbleTravel * 0.3
                let shoulderBubbleX = CGFloat(ll) * maxBubbleTravel
                let hipBubbleX = CGFloat(ll) * maxBubbleTravel * 0.5

                // Rotations from twist
                let headRotation = Angle(degrees: Double(tw) * 6)
                let hipRotation = Angle(degrees: Double(-tw) * 6)

                // Draw levels
                drawSpiritLevel(context: context, center: CGPoint(x: cx, y: headLevelY),
                                tubeW: tubeW, tubeH: tubeH, bubbleOffset: headBubbleX,
                                rotation: headRotation, label: "HEAD", scale: s)
                drawSpiritLevel(context: context, center: CGPoint(x: cx, y: shoulderLevelY),
                                tubeW: tubeW, tubeH: tubeH, bubbleOffset: shoulderBubbleX,
                                rotation: .zero, label: "SHOULDER", scale: s)
                drawSpiritLevel(context: context, center: CGPoint(x: cx, y: hipLevelY),
                                tubeW: tubeW, tubeH: tubeH, bubbleOffset: hipBubbleX,
                                rotation: hipRotation, label: "HIP", scale: s)

                // Plumb line with bob
                let plumbX = cx - 55 * s
                let plumbTopY = headLevelY
                let plumbBottomY = hipLevelY + 30 * s
                let plumbLean = CGFloat(ll) * 15 * s

                var plumbLine = Path()
                plumbLine.move(to: CGPoint(x: plumbX, y: plumbTopY))
                plumbLine.addLine(to: CGPoint(x: plumbX + plumbLean, y: plumbBottomY))
                context.stroke(plumbLine, with: .color(.secondary.opacity(0.4)),
                               style: StrokeStyle(lineWidth: 1.5, dash: [4, 2]))

                // Bob
                let bobScale = 1.0 + CGFloat(fc) * 0.3
                let bobR: CGFloat = 6 * s * bobScale
                let bobCenter = CGPoint(x: plumbX + plumbLean, y: plumbBottomY)
                let bobRect = CGRect(x: bobCenter.x - bobR, y: bobCenter.y - bobR, width: bobR * 2, height: bobR * 2)
                context.fill(Path(ellipseIn: bobRect), with: .color(.secondary))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Alert overlay
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

    private func drawSpiritLevel(context: GraphicsContext, center: CGPoint,
                                  tubeW: CGFloat, tubeH: CGFloat, bubbleOffset: CGFloat,
                                  rotation: Angle, label: String, scale s: CGFloat) {
        context.drawLayer { ctx in
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: rotation)

            // Tube background
            let tubeRect = CGRect(x: -tubeW / 2, y: -tubeH / 2, width: tubeW, height: tubeH)
            let tubePath = Path(roundedRect: tubeRect, cornerRadius: tubeH / 2)

            // Pale green liquid fill
            let liquidGradient = Gradient(colors: [
                Color.green.opacity(0.08),
                Color.green.opacity(0.15),
                Color.green.opacity(0.08),
            ])
            ctx.fill(tubePath, with: .linearGradient(liquidGradient, startPoint: CGPoint(x: 0, y: -tubeH / 2), endPoint: CGPoint(x: 0, y: tubeH / 2)))
            ctx.stroke(tubePath, with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5))

            // Tick marks
            for pos: CGFloat in [-0.5, -0.25, 0, 0.25, 0.5] {
                let x = pos * (tubeW - tubeH)
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: -tubeH / 2))
                tick.addLine(to: CGPoint(x: x, y: -tubeH / 2 + 4))
                tick.move(to: CGPoint(x: x, y: tubeH / 2))
                tick.addLine(to: CGPoint(x: x, y: tubeH / 2 - 4))
                let tickOpacity: Double = pos == 0 ? 0.6 : 0.3
                ctx.stroke(tick, with: .color(.secondary.opacity(tickOpacity)), style: StrokeStyle(lineWidth: 1))
            }

            // Bubble
            let clampedOffset = max(-((tubeW - tubeH) / 2), min((tubeW - tubeH) / 2, bubbleOffset))
            let bubbleR = (tubeH - 6) / 2
            let normalizedOffset = abs(clampedOffset) / ((tubeW - tubeH) / 2)
            let bubbleColor: Color = normalizedOffset < 0.2 ? .green : (normalizedOffset < 0.6 ? .yellow : .red)
            let bubbleRect = CGRect(x: clampedOffset - bubbleR, y: -bubbleR, width: bubbleR * 2, height: bubbleR * 2)
            ctx.fill(Path(ellipseIn: bubbleRect), with: .color(bubbleColor.opacity(0.7)))
            ctx.stroke(Path(ellipseIn: bubbleRect), with: .color(bubbleColor), style: StrokeStyle(lineWidth: 1))

            // Label
            ctx.draw(
                Text(label).font(.system(size: 7 * s, weight: .medium, design: .monospaced)).foregroundColor(.secondary.opacity(0.5)),
                at: CGPoint(x: tubeW / 2 + 25 * s, y: 0)
            )
        }
    }

    private func drawFaintBody(context: GraphicsContext, cx: CGFloat, cy: CGFloat, scale s: CGFloat) {
        let color = Color.secondary.opacity(0.1)
        let lw: CGFloat = 1.5

        // Head circle
        let headRect = CGRect(x: cx - 12 * s, y: cy - 100 * s, width: 24 * s, height: 24 * s)
        context.stroke(Path(ellipseIn: headRect), with: .color(color), style: StrokeStyle(lineWidth: lw))

        // Shoulder line
        var shoulders = Path()
        shoulders.move(to: CGPoint(x: cx - 35 * s, y: cy - 30 * s))
        shoulders.addLine(to: CGPoint(x: cx + 35 * s, y: cy - 30 * s))
        context.stroke(shoulders, with: .color(color), style: StrokeStyle(lineWidth: lw))

        // Torso
        let torsoRect = CGRect(x: cx - 20 * s, y: cy - 30 * s, width: 40 * s, height: 60 * s)
        context.stroke(Path(roundedRect: torsoRect, cornerRadius: 6 * s), with: .color(color), style: StrokeStyle(lineWidth: lw))

        // Hip line
        var hips = Path()
        hips.move(to: CGPoint(x: cx - 22 * s, y: cy + 30 * s))
        hips.addLine(to: CGPoint(x: cx + 22 * s, y: cy + 30 * s))
        context.stroke(hips, with: .color(color), style: StrokeStyle(lineWidth: lw))
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant36View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .lateralLean,
        worstRatio: 0.8
    )
    let observer = PostureDisplayObserver(source: source)
    Variant36View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant36View()
        .environmentObject(observer)
}
