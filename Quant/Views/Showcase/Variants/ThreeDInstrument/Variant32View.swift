import SwiftUI
import PostureLogic

/// Variant 32: Muscle Heatmap — A fixed body outline with colored hotspots overlaid
/// on specific body regions indicating strain. The outline never deforms — strain is
/// shown as radial gradient blobs that bloom and intensify per metric.
struct Variant32View: View {
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
                        heatmapCanvas(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    heatmapCanvas(size: geo.size, isLandscape: isLandscape)
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

    private func heatmapCanvas(size: CGSize, isLandscape: Bool) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio

        return ZStack {
            Canvas { context, canvasSize in
                let cx = canvasSize.width * (isLandscape ? 0.35 : 0.5)
                let cy = canvasSize.height * 0.5
                let s = min(canvasSize.width * 0.6, canvasSize.height * 0.8) / 300

                // Fixed body outline (always upright)
                drawBodyOutline(context: context, cx: cx, cy: cy, scale: s)

                // Heatmap zones
                let maxRadius: CGFloat = 40 * s

                // Forward Creep — chest/sternum area
                let chestCenter = CGPoint(x: cx, y: cy - 30 * s)
                drawHeatZone(context: context, center: chestCenter, ratio: CGFloat(fc), maxRadius: maxRadius)

                // Head Drop — neck/base of skull
                let neckCenter = CGPoint(x: cx, y: cy - 85 * s)
                drawHeatZone(context: context, center: neckCenter, ratio: CGFloat(hd), maxRadius: maxRadius * 0.8)

                // Shoulder Rounding — both deltoids
                let leftShoulder = CGPoint(x: cx - 35 * s, y: cy - 50 * s)
                let rightShoulder = CGPoint(x: cx + 35 * s, y: cy - 50 * s)
                drawHeatZone(context: context, center: leftShoulder, ratio: CGFloat(sr), maxRadius: maxRadius * 0.7)
                drawHeatZone(context: context, center: rightShoulder, ratio: CGFloat(sr), maxRadius: maxRadius * 0.7)

                // Lateral Lean — oblique/waist
                let waistCenter = CGPoint(x: cx + (ll > 0 ? 20 * s : -20 * s), y: cy + 20 * s)
                drawHeatZone(context: context, center: waistCenter, ratio: CGFloat(ll), maxRadius: maxRadius * 0.8)

                // Twist — diagonal across torso
                let twistCenter = CGPoint(x: cx, y: cy - 10 * s)
                drawHeatZone(context: context, center: twistCenter, ratio: CGFloat(tw), maxRadius: maxRadius * 0.9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Alert overlay
            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red.opacity(0.6))
                            .frame(width: 8, height: 8)
                        Text(worst.key.displayName)
                            .font(.caption.bold())
                            .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                    }
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

    private func drawBodyOutline(context: GraphicsContext, cx: CGFloat, cy: CGFloat, scale s: CGFloat) {
        let outlineColor = Color.secondary.opacity(0.3)
        let lineWidth: CGFloat = 2

        // Head
        let headRect = CGRect(x: cx - 16 * s, y: cy - 120 * s, width: 32 * s, height: 32 * s)
        context.stroke(Path(ellipseIn: headRect), with: .color(outlineColor), style: StrokeStyle(lineWidth: lineWidth))

        // Neck
        var neck = Path()
        neck.move(to: CGPoint(x: cx, y: cy - 88 * s))
        neck.addLine(to: CGPoint(x: cx, y: cy - 70 * s))
        context.stroke(neck, with: .color(outlineColor), style: StrokeStyle(lineWidth: lineWidth))

        // Shoulders
        var shoulders = Path()
        shoulders.move(to: CGPoint(x: cx - 45 * s, y: cy - 60 * s))
        shoulders.addLine(to: CGPoint(x: cx + 45 * s, y: cy - 60 * s))
        context.stroke(shoulders, with: .color(outlineColor), style: StrokeStyle(lineWidth: lineWidth))

        // Torso
        let torsoRect = CGRect(x: cx - 30 * s, y: cy - 60 * s, width: 60 * s, height: 100 * s)
        context.stroke(Path(roundedRect: torsoRect, cornerRadius: 8 * s), with: .color(outlineColor), style: StrokeStyle(lineWidth: lineWidth))

        // Arms
        for sign: CGFloat in [-1, 1] {
            var arm = Path()
            arm.move(to: CGPoint(x: cx + sign * 45 * s, y: cy - 60 * s))
            arm.addLine(to: CGPoint(x: cx + sign * 50 * s, y: cy + 10 * s))
            context.stroke(arm, with: .color(outlineColor), style: StrokeStyle(lineWidth: lineWidth))
        }

        // Legs
        for sign: CGFloat in [-1, 1] {
            var leg = Path()
            leg.move(to: CGPoint(x: cx + sign * 15 * s, y: cy + 40 * s))
            leg.addLine(to: CGPoint(x: cx + sign * 20 * s, y: cy + 110 * s))
            context.stroke(leg, with: .color(outlineColor), style: StrokeStyle(lineWidth: lineWidth))
        }
    }

    private func drawHeatZone(context: GraphicsContext, center: CGPoint, ratio: CGFloat, maxRadius: CGFloat) {
        guard ratio > 0.01 else { return }
        let radius = ratio * maxRadius

        let heatColor = thermalColor(ratio: ratio)

        context.drawLayer { ctx in
            ctx.blendMode = .plusLighter
            let gradient = Gradient(stops: [
                .init(color: heatColor.opacity(0.6), location: 0),
                .init(color: heatColor.opacity(0.2), location: 0.6),
                .init(color: .clear, location: 1.0),
            ])
            let ellipseRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            ctx.fill(
                Path(ellipseIn: ellipseRect),
                with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
            )
        }
    }

    private func thermalColor(ratio: CGFloat) -> Color {
        if ratio < 0.3 {
            return .blue
        } else if ratio < 0.5 {
            return .green
        } else if ratio < 0.7 {
            return .yellow
        } else if ratio < 0.85 {
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
    Variant32View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .shoulderRounding,
        worstRatio: 0.9
    )
    let observer = PostureDisplayObserver(source: source)
    Variant32View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant32View()
        .environmentObject(observer)
}
