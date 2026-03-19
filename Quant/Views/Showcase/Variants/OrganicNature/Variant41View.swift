import SwiftUI
import PostureLogic

// MARK: - Plant Geometry

/// Animatable plant geometry for smooth wilting transitions.
struct PlantGeometry: Equatable {
    // Stem control points (3 segments, cubic Bezier)
    var stemBendX: CGFloat = 0      // Forward creep bows stem
    var headDroop: CGFloat = 0      // Head drop nods the bloom
    var leafCurl: CGFloat = 0       // Shoulder rounding curls leaves inward
    var leanOffset: CGFloat = 0     // Lateral lean tilts the whole plant
    var twistAsymmetry: CGFloat = 0 // Twist makes leaf pairs asymmetric

    static func from(fc: Float, hd: Float, sr: Float, ll: Float, tw: Float) -> PlantGeometry {
        PlantGeometry(
            stemBendX: CGFloat(fc),
            headDroop: CGFloat(hd),
            leafCurl: CGFloat(sr),
            leanOffset: CGFloat(ll),
            twistAsymmetry: CGFloat(tw)
        )
    }

    /// Returns the stem midpoint horizontal offset scaled to the given max offset.
    func stemMidOffset(maxOffset: CGFloat) -> CGFloat {
        stemBendX * maxOffset
    }
}

/// Variant 41: Wilting Plant — A geometric houseplant that wilts based on posture metrics.
/// Stem bows with forward creep, bloom nods with head drop, leaves curl with shoulder rounding,
/// plant leans with lateral lean, and leaf pairs become asymmetric with twist.
struct Variant41View: View {
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
            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        plantCanvas(size: geo.size)
                    }
                } else {
                    plantCanvas(size: geo.size)
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

    private func plantCanvas(size: CGSize) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio
        let geo = PlantGeometry.from(fc: fc, hd: hd, sr: sr, ll: ll, tw: tw)
        let avgStress = (CGFloat(fc) + CGFloat(hd) + CGFloat(sr) + CGFloat(ll) + CGFloat(tw)) / 5

        return ZStack {
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let s = min(canvasSize.width, canvasSize.height) * 0.003
                let potTop = canvasSize.height * 0.72
                let stemBase = potTop
                let stemTop = canvasSize.height * 0.22

                // Overall lean
                let leanShift = geo.leanOffset * 30 * s

                // Plant hue: vibrant green -> dusty yellow-brown
                let hue = 0.33 - Double(avgStress) * 0.20
                let sat = max(0.3, 0.85 - Double(avgStress) * 0.55)
                let plantColor = Color(hue: hue, saturation: sat, brightness: 0.65)
                let stemColor = Color(hue: hue - 0.05, saturation: sat * 0.8, brightness: 0.45)

                // --- Pot ---
                let potWidth: CGFloat = 50 * s
                let potHeight: CGFloat = 35 * s
                var potPath = Path()
                potPath.move(to: CGPoint(x: cx - potWidth / 2, y: potTop))
                potPath.addLine(to: CGPoint(x: cx - potWidth * 0.35, y: potTop + potHeight))
                potPath.addLine(to: CGPoint(x: cx + potWidth * 0.35, y: potTop + potHeight))
                potPath.addLine(to: CGPoint(x: cx + potWidth / 2, y: potTop))
                potPath.closeSubpath()
                context.fill(potPath, with: .color(Color(hue: 0.06, saturation: 0.6, brightness: 0.5)))
                context.stroke(potPath, with: .color(Color(hue: 0.06, saturation: 0.4, brightness: 0.35)),
                               style: StrokeStyle(lineWidth: 2))

                // Pot rim
                let rimRect = CGRect(x: cx - potWidth / 2 - 3 * s, y: potTop - 5 * s, width: potWidth + 6 * s, height: 8 * s)
                context.fill(Path(roundedRect: rimRect, cornerRadius: 3), with: .color(Color(hue: 0.06, saturation: 0.5, brightness: 0.55)))

                // --- Stem (cubic Bezier, 3 segments) ---
                let stemBend = geo.stemMidOffset(maxOffset: 40 * s)
                let segHeight = (stemBase - stemTop) / 3

                var stemPath = Path()
                stemPath.move(to: CGPoint(x: cx + leanShift, y: stemBase))

                for i in 0..<3 {
                    let segFrac = CGFloat(i) / 3
                    let nextFrac = CGFloat(i + 1) / 3
                    let startY = stemBase - segFrac * (stemBase - stemTop)
                    let endY = stemBase - nextFrac * (stemBase - stemTop)
                    let midY = (startY + endY) / 2

                    let bendAtSeg = stemBend * (1.0 - segFrac * 0.3)
                    let cp1 = CGPoint(x: cx + leanShift + bendAtSeg * 0.3, y: startY - segHeight * 0.3)
                    let cp2 = CGPoint(x: cx + leanShift + bendAtSeg * 0.7, y: midY)
                    let endPt = CGPoint(x: cx + leanShift + bendAtSeg, y: endY)

                    stemPath.addCurve(to: endPt, control1: cp1, control2: cp2)
                }

                context.stroke(stemPath, with: .color(stemColor), style: StrokeStyle(lineWidth: 5 * s, lineCap: .round))

                // --- Leaf pairs (2 pairs at segments 1 and 2) ---
                let leafOpenAngle = .pi / 4 * (1.0 - Double(geo.leafCurl) * 0.8)
                let twistMod = Double(geo.twistAsymmetry) * 0.3

                for seg in 0..<2 {
                    let frac = CGFloat(seg + 1) / 3
                    let attachY = stemBase - frac * (stemBase - stemTop)
                    let attachX = cx + leanShift + stemBend * (1.0 - frac * 0.3)
                    let leafLen: CGFloat = (25 - CGFloat(seg) * 5) * s

                    // Left leaf
                    let leftAngle = .pi / 2 + leafOpenAngle + twistMod
                    drawLeaf(context: context, attachX: attachX, attachY: attachY,
                             angle: leftAngle, length: leafLen, color: plantColor, scale: s)

                    // Right leaf
                    let rightAngle = .pi / 2 - leafOpenAngle + twistMod
                    drawLeaf(context: context, attachX: attachX, attachY: attachY,
                             angle: rightAngle, length: leafLen, color: plantColor, scale: s)
                }

                // --- Bloom (8 petals at top) ---
                let bloomCenterX = cx + leanShift + stemBend
                let bloomCenterY = stemTop - Double(geo.headDroop) * 15 * s
                let petalLen: CGFloat = 12 * s
                let petalClose = Double(geo.headDroop) * 60 * .pi / 180

                let bloomColor = Color(hue: max(0, hue + 0.9), saturation: max(0.3, sat - 0.1), brightness: 0.75)

                for i in 0..<8 {
                    let baseAngle = Double(i) * .pi / 4
                    let adjustedAngle = baseAngle + (baseAngle > .pi ? petalClose : -petalClose)
                    let tipX = bloomCenterX + petalLen * cos(adjustedAngle)
                    let tipY = bloomCenterY - petalLen * sin(adjustedAngle)

                    var petal = Path()
                    petal.addEllipse(in: CGRect(x: -3 * s, y: -petalLen / 2, width: 6 * s, height: petalLen))

                    context.drawLayer { ctx in
                        ctx.translateBy(x: bloomCenterX, y: bloomCenterY)
                        ctx.rotate(by: Angle(radians: -.pi / 2 + adjustedAngle))
                        ctx.fill(Path(ellipseIn: CGRect(x: -3 * s, y: 0, width: 6 * s, height: petalLen)),
                                 with: .color(bloomColor.opacity(0.8)))
                    }
                }

                // Bloom center disc
                let discRadius: CGFloat = 5 * s
                context.fill(Path(ellipseIn: CGRect(x: bloomCenterX - discRadius, y: bloomCenterY - discRadius,
                                                     width: discRadius * 2, height: discRadius * 2)),
                             with: .color(Color(hue: 0.12, saturation: 0.8, brightness: 0.7)))

                // --- Seed icons (5 small shapes at bottom) ---
                let seedY = potTop + 50 * s
                let metrics: [(MetricKey, Float)] = [
                    (.forwardCreep, fc), (.headDrop, hd), (.shoulderRounding, sr),
                    (.lateralLean, ll), (.twist, tw)
                ]
                let seedSpacing: CGFloat = 22 * s
                let seedStartX = cx - seedSpacing * 2

                for (idx, (key, ratio)) in metrics.enumerated() {
                    let sx = seedStartX + CGFloat(idx) * seedSpacing
                    let seedW: CGFloat = 6 * s
                    let seedH: CGFloat = 10 * s
                    let fillH = seedH * CGFloat(min(ratio, 1.0))

                    // Seed outline
                    let seedRect = CGRect(x: sx - seedW / 2, y: seedY - seedH / 2, width: seedW, height: seedH)
                    context.stroke(Path(roundedRect: seedRect, cornerRadius: seedW / 2),
                                   with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 1))

                    // Seed fill
                    if fillH > 0 {
                        let fillRect = CGRect(x: sx - seedW / 2, y: seedY + seedH / 2 - fillH, width: seedW, height: fillH)
                        context.fill(Path(roundedRect: fillRect, cornerRadius: seedW / 2),
                                     with: .color(PostureVisualStyle.metricColor(ratio: ratio).opacity(0.7)))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Alert overlay
            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                VStack {
                    Spacer()
                    Text(worst.key.displayName)
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))

                    if let seconds = observer.data.nudgeCountdownSeconds {
                        // Water droplet countdown
                        HStack(spacing: 4) {
                            Image(systemName: "drop.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func drawLeaf(context: GraphicsContext, attachX: CGFloat, attachY: CGFloat,
                           angle: Double, length: CGFloat, color: Color, scale s: CGFloat) {
        context.drawLayer { ctx in
            ctx.translateBy(x: attachX, y: attachY)
            ctx.rotate(by: Angle(radians: -angle))
            let leafPath = Path(ellipseIn: CGRect(x: -4 * s, y: 0, width: 8 * s, height: length))
            ctx.fill(leafPath, with: .color(color.opacity(0.85)))
            // Leaf vein
            var vein = Path()
            vein.move(to: CGPoint(x: 0, y: 0))
            vein.addLine(to: CGPoint(x: 0, y: length * 0.9))
            ctx.stroke(vein, with: .color(color.opacity(0.4)), style: StrokeStyle(lineWidth: 0.8))
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant41View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .forwardCreep,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant41View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant41View()
        .environmentObject(observer)
}
