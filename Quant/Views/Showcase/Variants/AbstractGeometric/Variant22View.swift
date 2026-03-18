import SwiftUI
import PostureLogic

/// Variant 22: Radar Glyph — A pentagonal radar/spider chart where each axis
/// represents one posture metric. Perfect posture = tiny central pentagon.
/// Degraded posture = large, irregular polygon extending outward.
struct Variant22View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private let axisIcons: [(MetricKey, String)] = [
        (.forwardCreep, "figure.walk"),
        (.headDrop, "arrow.down.to.line"),
        (.shoulderRounding, "arrow.left.and.right.circle"),
        (.lateralLean, "arrow.left.arrow.right"),
        (.twist, "arrow.triangle.2.circlepath")
    ]

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        radarContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    radarContent(size: geo.size, isLandscape: isLandscape)
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

    private func radarContent(size: CGSize, isLandscape: Bool) -> some View {
        let maxRadius = min(size.width, size.height) * 0.35
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        let ratios: [Float] = MetricKey.allCases.map { key in
            isAbsent ? 0 : observer.data.metric(for: key).clampedRatio
        }

        let avgRatio = ratios.reduce(0, +) / Float(ratios.count)
        let fillColor: Color = avgRatio < 0.33 ? .teal : (avgRatio < 0.66 ? .orange : .red)
        let strokeColor: Color = avgRatio < 0.33 ? .teal : (avgRatio < 0.66 ? .orange : .red)

        return ZStack {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height / 2
                let startAngle = -CGFloat.pi / 2

                // Grid lines (3 concentric pentagons)
                for level in [0.33, 0.66, 1.0] as [CGFloat] {
                    let gridPath = pentagonPath(
                        center: CGPoint(x: cx, y: cy),
                        radius: maxRadius * level,
                        startAngle: startAngle
                    )
                    context.stroke(
                        gridPath,
                        with: .color(.secondary.opacity(0.15)),
                        style: StrokeStyle(lineWidth: 0.5)
                    )
                }

                // Axis lines
                for i in 0..<5 {
                    let angle = startAngle + CGFloat(i) * (2 * .pi / 5)
                    let endX = cx + maxRadius * cos(angle)
                    let endY = cy + maxRadius * sin(angle)

                    var axisPath = Path()
                    axisPath.move(to: CGPoint(x: cx, y: cy))
                    axisPath.addLine(to: CGPoint(x: endX, y: endY))
                    context.stroke(
                        axisPath,
                        with: .color(.secondary.opacity(0.2)),
                        style: StrokeStyle(lineWidth: 0.5)
                    )
                }

                // Data polygon
                var dataPath = Path()
                for i in 0..<5 {
                    let angle = startAngle + CGFloat(i) * (2 * .pi / 5)
                    let r = maxRadius * CGFloat(ratios[i])
                    let px = cx + r * cos(angle)
                    let py = cy + r * sin(angle)

                    if i == 0 {
                        dataPath.move(to: CGPoint(x: px, y: py))
                    } else {
                        dataPath.addLine(to: CGPoint(x: px, y: py))
                    }
                }
                dataPath.closeSubpath()

                context.fill(dataPath, with: .color(fillColor.opacity(0.3)))
                context.stroke(
                    dataPath,
                    with: .color(strokeColor),
                    style: StrokeStyle(lineWidth: 2)
                )

                // Vertex dots
                for i in 0..<5 {
                    let angle = startAngle + CGFloat(i) * (2 * .pi / 5)
                    let r = maxRadius * CGFloat(ratios[i])
                    let px = cx + r * cos(angle)
                    let py = cy + r * sin(angle)

                    let dotPath = Path(ellipseIn: CGRect(x: px - 3, y: py - 3, width: 6, height: 6))
                    context.fill(dotPath, with: .color(strokeColor))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Axis icon labels
            ForEach(0..<5, id: \.self) { i in
                let angle = -.pi / 2 + Double(i) * (2 * .pi / 5)
                let labelR = maxRadius + 24
                let lx = center.x + labelR * cos(angle)
                let ly = center.y + labelR * sin(angle)

                Image(systemName: axisIcons[i].1)
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.6))
                    .position(x: lx, y: ly)
            }

            // Alert mode: worst offender label + countdown
            if observer.data.isAlertMode {
                VStack(spacing: 4) {
                    if let worst = observer.data.worstOffender {
                        Text(worst.key.displayName)
                            .font(.caption.bold())
                            .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                    }
                    if let seconds = observer.data.nudgeCountdownSeconds {
                        Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .position(x: center.x, y: center.y + maxRadius + 50)
            }
        }
    }

    private func pentagonPath(center: CGPoint, radius: CGFloat, startAngle: CGFloat) -> Path {
        var path = Path()
        for i in 0..<5 {
            let angle = startAngle + CGFloat(i) * (2 * .pi / 5)
            let px = center.x + radius * cos(angle)
            let py = center.y + radius * sin(angle)
            if i == 0 {
                path.move(to: CGPoint(x: px, y: py))
            } else {
                path.addLine(to: CGPoint(x: px, y: py))
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant22View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .shoulderRounding,
        worstRatio: 0.9
    )
    let observer = PostureDisplayObserver(source: source)
    Variant22View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant22View()
        .environmentObject(observer)
}
