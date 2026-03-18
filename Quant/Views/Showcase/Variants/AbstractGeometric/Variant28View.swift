import SwiftUI
import PostureLogic

/// Variant 28: Sacred Geometry — A Flower of Life mandala with 19 circles in
/// hexagonal arrangement. Perfect posture = symmetric mandala with six-fold symmetry.
/// Degraded posture = distorted circles, broken symmetry, discordant pattern.
struct Variant28View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var breathScale: CGFloat = 0.99

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
                        mandalaContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    mandalaContent(size: geo.size, isLandscape: isLandscape)
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
        .onAppear { startBreathing() }
        .onChange(of: observer.data.postureState) { _, _ in startBreathing() }
    }

    private func mandalaContent(size: CGSize, isLandscape: Bool) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio

        let mandalaSize = min(size.width, size.height) * 0.75

        return ZStack {
            TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                Canvas { context, canvasSize in
                    let cx = canvasSize.width / 2
                    let cy = canvasSize.height / 2
                    let circleRadius = mandalaSize / 6

                    // Generate flower of life circle centers
                    let centers = flowerOfLifeCenters(
                        center: CGPoint(x: cx, y: cy),
                        radius: circleRadius
                    )

                    // Deformation parameters
                    let horizontalStretch = 1.0 + CGFloat(fc) * 0.3
                    let verticalSqueeze = 1.0 - CGFloat(fc) * 0.15
                    let topDrop = CGFloat(hd) * 20
                    let lateralNarrow = CGFloat(sr) * 15
                    let shearAmount = CGFloat(ll) * 12
                    let innerRotation = CGFloat(tw) * 0.15
                    let outerRotation = -CGFloat(tw) * 0.1

                    for (index, baseCenter) in centers.enumerated() {
                        var adjustedCenter = baseCenter

                        // Head drop: top circles slide down
                        if baseCenter.y < cy {
                            let topFraction = (cy - baseCenter.y) / (mandalaSize / 2)
                            adjustedCenter.y += topDrop * topFraction
                        }

                        // Shoulder rounding: lateral circles pull inward
                        let lateralDist = abs(baseCenter.x - cx)
                        if lateralDist > circleRadius * 0.5 {
                            let sign: CGFloat = baseCenter.x > cx ? -1 : 1
                            adjustedCenter.x += sign * lateralNarrow * (lateralDist / (mandalaSize / 2))
                        }

                        // Lateral lean: shear top relative to bottom
                        let vertFraction = (cy - adjustedCenter.y) / (mandalaSize / 2)
                        adjustedCenter.x += shearAmount * vertFraction

                        // Twist: rotate inner vs outer rings
                        let distFromCenter = hypot(adjustedCenter.x - cx, adjustedCenter.y - cy)
                        let rotation = distFromCenter < circleRadius * 1.5 ? innerRotation : outerRotation
                        if rotation != 0 {
                            let dx = adjustedCenter.x - cx
                            let dy = adjustedCenter.y - cy
                            adjustedCenter.x = cx + dx * cos(rotation) - dy * sin(rotation)
                            adjustedCenter.y = cy + dx * sin(rotation) + dy * cos(rotation)
                        }

                        // Forward creep: horizontal stretch
                        let rx = circleRadius * horizontalStretch
                        let ry = circleRadius * verticalSqueeze

                        // Alert mode: dim non-related circles
                        let circleOpacity: Double
                        if observer.data.isAlertMode {
                            circleOpacity = isCircleRelatedToWorst(index: index, centers: centers, cx: cx, cy: cy, radius: circleRadius) ? 0.6 : 0.05
                        } else {
                            circleOpacity = 0.6
                        }

                        let ellipsePath = Path(ellipseIn: CGRect(
                            x: adjustedCenter.x - rx,
                            y: adjustedCenter.y - ry,
                            width: rx * 2,
                            height: ry * 2
                        ))

                        // Subtle fill for intersections
                        context.fill(ellipsePath, with: .color(.teal.opacity(0.03 * circleOpacity)))

                        context.stroke(
                            ellipsePath,
                            with: .color(.primary.opacity(circleOpacity)),
                            style: StrokeStyle(lineWidth: 1)
                        )
                    }

                    // Golden ratio spiral (visible when posture is good)
                    let spiralOpacity = Double(max(0, observer.data.aggregateScore - 0.3) / 0.7)
                    if spiralOpacity > 0.05 {
                        let spiralPath = goldenSpiralPath(center: CGPoint(x: cx, y: cy), maxRadius: mandalaSize / 3)
                        context.stroke(
                            spiralPath,
                            with: .color(.yellow.opacity(spiralOpacity * 0.3)),
                            style: StrokeStyle(lineWidth: 0.8)
                        )
                    }
                }
            }
            .frame(width: mandalaSize, height: mandalaSize)
            .scaleEffect(breathScale)

            // Alert info
            VStack {
                Spacer()
                if observer.data.isAlertMode {
                    if let worst = observer.data.worstOffender {
                        Text(worst.key.displayName)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                    }
                    if let seconds = observer.data.nudgeCountdownSeconds {
                        Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func flowerOfLifeCenters(center: CGPoint, radius: CGFloat) -> [CGPoint] {
        var centers: [CGPoint] = [center]

        // Inner ring: 6 circles
        for i in 0..<6 {
            let angle = CGFloat(i) * (.pi / 3)
            centers.append(CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            ))
        }

        // Outer ring: 12 circles
        for i in 0..<6 {
            let angle = CGFloat(i) * (.pi / 3)
            // 6 at 2*radius on main axes
            centers.append(CGPoint(
                x: center.x + 2 * radius * cos(angle),
                y: center.y + 2 * radius * sin(angle)
            ))
            // 6 between main axes
            let midAngle = angle + .pi / 6
            let midR = radius * sqrt(3)
            centers.append(CGPoint(
                x: center.x + midR * cos(midAngle),
                y: center.y + midR * sin(midAngle)
            ))
        }

        return centers
    }

    private func isCircleRelatedToWorst(index: Int, centers: [CGPoint], cx: CGFloat, cy: CGFloat, radius: CGFloat) -> Bool {
        guard let worst = observer.data.worstOffender else { return false }
        let center = centers[index]

        switch worst.key {
        case .forwardCreep:
            return true // Forward creep affects all circles
        case .headDrop:
            return center.y < cy - radius * 0.5
        case .shoulderRounding:
            return abs(center.x - cx) > radius * 0.8
        case .lateralLean:
            return abs(center.y - cy) < radius * 1.5
        case .twist:
            let dist = hypot(center.x - cx, center.y - cy)
            return dist < radius * 1.5 || dist > radius * 2.5
        }
    }

    private func goldenSpiralPath(center: CGPoint, maxRadius: CGFloat) -> Path {
        let phi: CGFloat = (1 + sqrt(5)) / 2
        var path = Path()
        let steps = 60
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 4 * .pi
            let r = min(maxRadius, pow(phi, t / (2 * .pi)) * 2)
            let x = center.x + r * cos(t)
            let y = center.y + r * sin(t)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private func startBreathing() {
        breathScale = 0.99
        let duration: Double = observer.data.postureState.isBad ? 1.5 : 4.0
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            breathScale = 1.01
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant28View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .twist,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant28View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant28View()
        .environmentObject(observer)
}
