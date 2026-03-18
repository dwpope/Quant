import SwiftUI
import PostureLogic

/// Variant 31: Body Silhouette — A 2D filled silhouette of a human figure that
/// deforms smoothly as posture metrics change. When posture is perfect, the
/// silhouette stands upright and symmetric. A ghost reference silhouette at 10% opacity
/// shows the ideal pose.
struct Variant31View: View {
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
                        silhouetteCanvas(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    silhouetteCanvas(size: geo.size, isLandscape: isLandscape)
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

    private func silhouetteCanvas(size: CGSize, isLandscape: Bool) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio

        let score = observer.data.aggregateScore
        let fillColor: Color = score > 0.7 ? .primary : (score > 0.4 ? .orange : .red)

        return ZStack {
            Canvas { context, canvasSize in
                let cx = canvasSize.width * (isLandscape ? 0.35 : 0.5)
                let cy = canvasSize.height * 0.5
                let s = min(canvasSize.width * 0.6, canvasSize.height * 0.8) / 300

                // Ghost reference silhouette
                let ghostPath = silhouettePath(cx: cx, cy: cy, scale: s, fc: 0, hd: 0, sr: 0, ll: 0, tw: 0)
                context.fill(ghostPath, with: .color(.primary.opacity(0.08)))

                // Active silhouette
                let activePath = silhouettePath(cx: cx, cy: cy, scale: s,
                                                fc: CGFloat(fc), hd: CGFloat(hd), sr: CGFloat(sr),
                                                ll: CGFloat(ll), tw: CGFloat(tw))
                context.fill(activePath, with: .color(fillColor))
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

    private func silhouettePath(cx: CGFloat, cy: CGFloat, scale s: CGFloat,
                                fc: CGFloat, hd: CGFloat, sr: CGFloat,
                                ll: CGFloat, tw: CGFloat) -> Path {
        // Forward lean shifts upper body rightward
        let forwardShift = fc * 20 * s
        // Head drop lowers head
        let headDrop = hd * 20 * s
        // Shoulder rounding narrows shoulder width
        let shoulderNarrow = sr * 15 * s
        // Lateral lean shifts upper body
        let leanShift = ll * 25 * s
        // Twist makes shoulders asymmetric
        let twistDiff = tw * 12 * s

        var path = Path()

        // Head center
        let headX = cx + forwardShift + leanShift
        let headY = cy - 120 * s + headDrop
        let headR: CGFloat = 18 * s

        // Head (circle approximation as part of path)
        path.addEllipse(in: CGRect(x: headX - headR, y: headY - headR, width: headR * 2, height: headR * 2))

        // Body outline (simplified)
        let neckY = headY + headR + 5 * s
        let shoulderY = neckY + 12 * s
        let shoulderLeftX = cx + forwardShift * 0.8 + leanShift * 0.7 - (45 * s - shoulderNarrow) - twistDiff
        let shoulderRightX = cx + forwardShift * 0.8 + leanShift * 0.7 + (45 * s - shoulderNarrow) + twistDiff
        let waistY = cy + 30 * s
        let waistLeftX = cx + leanShift * 0.2 - 22 * s
        let waistRightX = cx + leanShift * 0.2 + 22 * s
        let hipY = cy + 80 * s
        let hipLeftX = cx - 25 * s
        let hipRightX = cx + 25 * s

        var bodyPath = Path()
        // Neck
        bodyPath.move(to: CGPoint(x: headX - 7 * s, y: neckY))
        bodyPath.addLine(to: CGPoint(x: shoulderLeftX, y: shoulderY))
        // Left arm stub
        bodyPath.addLine(to: CGPoint(x: shoulderLeftX - 8 * s, y: shoulderY + 50 * s))
        bodyPath.addLine(to: CGPoint(x: shoulderLeftX - 2 * s, y: shoulderY + 52 * s))
        bodyPath.addLine(to: CGPoint(x: shoulderLeftX + 5 * s, y: shoulderY + 15 * s))
        // Left torso down to waist
        bodyPath.addQuadCurve(to: CGPoint(x: waistLeftX, y: waistY),
                              control: CGPoint(x: shoulderLeftX + 3 * s, y: (shoulderY + waistY) / 2))
        // Hip
        bodyPath.addLine(to: CGPoint(x: hipLeftX, y: hipY))
        // Across bottom
        bodyPath.addLine(to: CGPoint(x: hipRightX, y: hipY))
        // Right side up
        bodyPath.addLine(to: CGPoint(x: waistRightX, y: waistY))
        bodyPath.addQuadCurve(to: CGPoint(x: shoulderRightX + 5 * s, y: shoulderY + 15 * s),
                              control: CGPoint(x: shoulderRightX - 3 * s, y: (shoulderY + waistY) / 2))
        // Right arm stub
        bodyPath.addLine(to: CGPoint(x: shoulderRightX + 2 * s, y: shoulderY + 52 * s))
        bodyPath.addLine(to: CGPoint(x: shoulderRightX + 8 * s, y: shoulderY + 50 * s))
        bodyPath.addLine(to: CGPoint(x: shoulderRightX, y: shoulderY))
        // Back to neck
        bodyPath.addLine(to: CGPoint(x: headX + 7 * s, y: neckY))
        bodyPath.closeSubpath()

        path.addPath(bodyPath)
        return path
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant31View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .headDrop,
        worstRatio: 0.8
    )
    let observer = PostureDisplayObserver(source: source)
    Variant31View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant31View()
        .environmentObject(observer)
}
