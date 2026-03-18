import SwiftUI
import PostureLogic

/// Variant 40: Load Diagram — A structural engineering stress diagram applied to a
/// simplified beam model of the human spine. The beam shows stress coloring (green to red)
/// and force arrows showing direction and magnitude of each postural deviation.
struct Variant40View: View {
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
                        loadDiagramCanvas(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    loadDiagramCanvas(size: geo.size, isLandscape: isLandscape)
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

    private func loadDiagramCanvas(size: CGSize, isLandscape: Bool) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio
        let score = observer.data.aggregateScore

        return ZStack {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height * 0.5
                let s = min(canvasSize.width, canvasSize.height) * 0.003

                let beamWidth: CGFloat = 20 * s
                let beamHeight: CGFloat = 220 * s
                let beamTop = cy - beamHeight / 2
                let beamBottom = cy + beamHeight / 2

                // Neutral axis (dashed vertical line)
                var neutralAxis = Path()
                neutralAxis.move(to: CGPoint(x: cx, y: beamTop - 10 * s))
                neutralAxis.addLine(to: CGPoint(x: cx, y: beamBottom + 20 * s))
                context.stroke(neutralAxis, with: .color(.secondary.opacity(0.2)), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))

                // Beam bending — side edges are Bezier curves
                let bendOffset = CGFloat(ll) * 15 * s
                let forwardBend = CGFloat(fc) * 5 * s

                // Stress gradient colors
                let cervicalStress = max(CGFloat(hd), CGFloat(fc)) * 0.7 + CGFloat(sr) * 0.3
                let thoracicStress = max(CGFloat(sr), CGFloat(fc)) * 0.7 + CGFloat(tw) * 0.3
                let lumbarStress = CGFloat(1.0 - score)

                // Draw beam in three sections
                let sectionHeight = beamHeight / 3
                let sections: [(CGFloat, CGFloat, String)] = [
                    (cervicalStress, 0, "Cervical"),
                    (thoracicStress, 1, "Thoracic"),
                    (lumbarStress, 2, "Lumbar"),
                ]

                for (stress, idx, label) in sections {
                    let sectionTop = beamTop + idx * sectionHeight
                    let sectionBottom = sectionTop + sectionHeight
                    let topBend = bendOffset * (1.0 - idx / 2.0)
                    let bottomBend = bendOffset * (1.0 - (idx + 1) / 2.0)
                    let widthMod = beamWidth + forwardBend * (1.0 - idx / 2.0)

                    let sectionRect = CGRect(
                        x: cx - widthMod / 2 + topBend,
                        y: sectionTop,
                        width: widthMod,
                        height: sectionHeight
                    )

                    let stressColor = beamStressColor(stress: stress)
                    context.fill(Path(sectionRect), with: .color(stressColor.opacity(0.6)))
                    context.stroke(Path(sectionRect), with: .color(stressColor), style: StrokeStyle(lineWidth: 1))

                    // Section cross-section marker
                    var crossSection = Path()
                    crossSection.move(to: CGPoint(x: sectionRect.minX - 5 * s, y: sectionBottom))
                    crossSection.addLine(to: CGPoint(x: sectionRect.maxX + 5 * s, y: sectionBottom))
                    context.stroke(crossSection, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 1))

                    // Region label
                    context.draw(
                        Text(label).font(.system(size: 8 * s, weight: .light, design: .monospaced)).foregroundColor(.secondary.opacity(0.5)),
                        at: CGPoint(x: cx - beamWidth / 2 - 30 * s, y: (sectionTop + sectionBottom) / 2)
                    )
                }

                // Force arrows
                let maxArrowLength: CGFloat = 60 * s

                // Forward Creep — horizontal right from thoracic region
                drawForceArrow(context: context, origin: CGPoint(x: cx + beamWidth / 2, y: cy - 15 * s),
                               dx: CGFloat(fc) * maxArrowLength, dy: 0,
                               color: beamStressColor(stress: CGFloat(fc)),
                               label: String(format: "FWD: %.2f", fc), scale: s)

                // Head Drop — downward from top
                drawForceArrow(context: context, origin: CGPoint(x: cx, y: beamTop),
                               dx: 0, dy: CGFloat(hd) * maxArrowLength,
                               color: beamStressColor(stress: CGFloat(hd)),
                               label: String(format: "HEAD: %.2f", hd), scale: s)

                // Shoulder Rounding — two inward arrows at shoulder level
                let shoulderY = beamTop + sectionHeight * 0.5
                drawForceArrow(context: context, origin: CGPoint(x: cx - beamWidth / 2 - 20 * s, y: shoulderY),
                               dx: CGFloat(sr) * maxArrowLength * 0.5, dy: 0,
                               color: beamStressColor(stress: CGFloat(sr)),
                               label: "", scale: s)
                drawForceArrow(context: context, origin: CGPoint(x: cx + beamWidth / 2 + 20 * s, y: shoulderY),
                               dx: -CGFloat(sr) * maxArrowLength * 0.5, dy: 0,
                               color: beamStressColor(stress: CGFloat(sr)),
                               label: String(format: "SHLD: %.2f", sr), scale: s)

                // Lateral Lean — horizontal from center
                let leanDir: CGFloat = ll > 0 ? 1 : -1
                drawForceArrow(context: context, origin: CGPoint(x: cx, y: cy),
                               dx: CGFloat(ll) * maxArrowLength * leanDir, dy: 0,
                               color: beamStressColor(stress: CGFloat(ll)),
                               label: String(format: "LEAN: %.2f", ll), scale: s)

                // Twist — torque couple (top right, bottom left)
                if tw > 0.05 {
                    drawForceArrow(context: context, origin: CGPoint(x: cx, y: beamTop + 20 * s),
                                   dx: CGFloat(tw) * maxArrowLength * 0.4, dy: 0,
                                   color: beamStressColor(stress: CGFloat(tw)),
                                   label: "", scale: s)
                    drawForceArrow(context: context, origin: CGPoint(x: cx, y: beamBottom - 20 * s),
                                   dx: -CGFloat(tw) * maxArrowLength * 0.4, dy: 0,
                                   color: beamStressColor(stress: CGFloat(tw)),
                                   label: String(format: "TWST: %.2f", tw), scale: s)
                }

                // Support symbol at base (triangle)
                var supportPath = Path()
                let supportW: CGFloat = 20 * s
                let supportH: CGFloat = 15 * s
                supportPath.move(to: CGPoint(x: cx, y: beamBottom))
                supportPath.addLine(to: CGPoint(x: cx - supportW / 2, y: beamBottom + supportH))
                supportPath.addLine(to: CGPoint(x: cx + supportW / 2, y: beamBottom + supportH))
                supportPath.closeSubpath()
                context.fill(supportPath, with: .color(.secondary.opacity(0.3)))
                context.stroke(supportPath, with: .color(.secondary), style: StrokeStyle(lineWidth: 1.5))

                // Ground line
                var groundLine = Path()
                groundLine.move(to: CGPoint(x: cx - 30 * s, y: beamBottom + supportH))
                groundLine.addLine(to: CGPoint(x: cx + 30 * s, y: beamBottom + supportH))
                context.stroke(groundLine, with: .color(.secondary), style: StrokeStyle(lineWidth: 1.5))

                // Reaction force arrow (upward)
                let totalLoad = (CGFloat(fc) + CGFloat(hd) + CGFloat(sr)) / 3
                if totalLoad > 0.05 {
                    drawForceArrow(context: context, origin: CGPoint(x: cx, y: beamBottom + supportH + 5 * s),
                                   dx: 0, dy: -totalLoad * maxArrowLength * 0.5,
                                   color: .secondary, label: "", scale: s)
                }

                // Alert cross-hatch on worst section
                if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                    let hatchSection: CGFloat
                    switch worst.key {
                    case .headDrop, .forwardCreep: hatchSection = 0
                    case .shoulderRounding, .twist: hatchSection = 1
                    case .lateralLean: hatchSection = 2
                    }
                    let hatchTop = beamTop + hatchSection * sectionHeight
                    let hatchRect = CGRect(x: cx - beamWidth / 2 - 2 * s, y: hatchTop, width: beamWidth + 4 * s, height: sectionHeight)

                    context.drawLayer { ctx in
                        ctx.clip(to: Path(hatchRect))
                        for offset in stride(from: -sectionHeight, to: beamWidth + sectionHeight, by: 6 * s) {
                            var hatchLine = Path()
                            hatchLine.move(to: CGPoint(x: hatchRect.minX + offset, y: hatchTop))
                            hatchLine.addLine(to: CGPoint(x: hatchRect.minX + offset + sectionHeight, y: hatchTop + sectionHeight))
                            ctx.stroke(hatchLine, with: .color(.red.opacity(0.3)), style: StrokeStyle(lineWidth: 0.8))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Alert label + countdown
            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        // Load gauge
                        if let seconds = observer.data.nudgeCountdownSeconds {
                            Text("LOAD")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.bottom, 8)
                    Text(worst.key.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                }
                .padding(.bottom, 20)
            }
        }
    }

    private func drawForceArrow(context: GraphicsContext, origin: CGPoint, dx: CGFloat, dy: CGFloat,
                                 color: Color, label: String, scale s: CGFloat) {
        guard abs(dx) > 1 || abs(dy) > 1 else { return }
        let tip = CGPoint(x: origin.x + dx, y: origin.y + dy)

        // Shaft
        var shaft = Path()
        shaft.move(to: origin)
        shaft.addLine(to: tip)
        context.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // Arrowhead
        let arrowLen: CGFloat = 8 * s
        let angle = atan2(dy, dx)
        let leftAngle = angle + .pi * 0.8
        let rightAngle = angle - .pi * 0.8

        var arrowHead = Path()
        arrowHead.move(to: tip)
        arrowHead.addLine(to: CGPoint(x: tip.x + arrowLen * cos(leftAngle), y: tip.y + arrowLen * sin(leftAngle)))
        arrowHead.move(to: tip)
        arrowHead.addLine(to: CGPoint(x: tip.x + arrowLen * cos(rightAngle), y: tip.y + arrowLen * sin(rightAngle)))
        context.stroke(arrowHead, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // Label
        if !label.isEmpty {
            let labelOffset: CGFloat = 12 * s
            let labelPt = CGPoint(x: tip.x + (dx > 0 ? labelOffset : -labelOffset), y: tip.y + (dy > 0 ? labelOffset : -labelOffset))
            context.draw(
                Text(label).font(.system(size: 7 * s, weight: .medium, design: .monospaced)).foregroundColor(color),
                at: labelPt
            )
        }
    }

    private func beamStressColor(stress: CGFloat) -> Color {
        if stress < 0.3 {
            return .green
        } else if stress < 0.6 {
            return .yellow
        } else if stress < 0.8 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant40View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.9
    )
    let observer = PostureDisplayObserver(source: source)
    Variant40View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant40View()
        .environmentObject(observer)
}
