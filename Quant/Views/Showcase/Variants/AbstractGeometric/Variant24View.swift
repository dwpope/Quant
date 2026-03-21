import SwiftUI
import PostureLogic

/// Variant 24: Pendulum Array — Five pendulums hang from a horizontal bar,
/// each deflecting based on its metric ratio. Uses physics-based spring
/// animations with damped harmonic oscillation for organic motion.
struct Variant24View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var pendulumAngles: [CGFloat] = Array(repeating: 0, count: 5)
    @State private var pendulumVelocities: [CGFloat] = Array(repeating: 0, count: 5)
    @State private var isActive = false

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private let metricKeys: [MetricKey] = MetricKey.allCases

    // Physics constants
    static let springConstant: CGFloat = 50.0
    static let damping: CGFloat = 0.88
    static let maxAngle: CGFloat = 45.0

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        pendulumContent(size: geo.size, isLandscape: isLandscape)
                    }
                } else {
                    pendulumContent(size: geo.size, isLandscape: isLandscape)
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
        .onAppear { isActive = true }
        .onDisappear { isActive = false }
        .animation(PostureAnimations.alertOnset, value: observer.data.isAlertMode)
    }

    private func pendulumContent(size: CGSize, isLandscape: Bool) -> some View {
        let barY: CGFloat = size.height * 0.12
        let stringLength = isLandscape ? size.height * 0.4 : size.height * 0.55
        let spacing = size.width / 6

        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isActive || isAbsent)) { timeline in
            Canvas { context, canvasSize in
                // Support bar
                var barPath = Path()
                barPath.move(to: CGPoint(x: spacing * 0.5, y: barY))
                barPath.addLine(to: CGPoint(x: canvasSize.width - spacing * 0.5, y: barY))
                context.stroke(barPath, with: .color(.primary), style: StrokeStyle(lineWidth: 4, lineCap: .round))

                for i in 0..<5 {
                    let attachX = spacing * CGFloat(i + 1)
                    let attachPoint = CGPoint(x: attachX, y: barY)
                    let ratio = isAbsent ? Float(0) : observer.data.metric(for: metricKeys[i]).clampedRatio
                    let isWorst = observer.data.metric(for: metricKeys[i]).isWorstOffender && observer.data.isAlertMode

                    // Effective string length
                    let effectiveLength: CGFloat
                    if observer.data.isAlertMode {
                        effectiveLength = isWorst ? stringLength * 1.2 : stringLength * 0.5
                    } else {
                        effectiveLength = stringLength
                    }

                    let angle = pendulumAngles[i]
                    let angleRad = Angle(degrees: Double(angle)).radians

                    let bobX = attachX + effectiveLength * CGFloat(sin(angleRad))
                    let bobY = barY + effectiveLength * CGFloat(cos(angleRad))
                    let bobPoint = CGPoint(x: bobX, y: bobY)

                    // Bob opacity in alert mode
                    let opacity: CGFloat = (observer.data.isAlertMode && !isWorst) ? 0.15 : 1.0

                    // Reference line (dashed plumb)
                    var refPath = Path()
                    refPath.move(to: attachPoint)
                    refPath.addLine(to: CGPoint(x: attachX, y: barY + effectiveLength))
                    context.stroke(
                        refPath,
                        with: .color(.secondary.opacity(0.1)),
                        style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])
                    )

                    // String
                    var stringPath = Path()
                    stringPath.move(to: attachPoint)
                    stringPath.addLine(to: bobPoint)
                    context.stroke(
                        stringPath,
                        with: .color(.primary.opacity(opacity * 0.6)),
                        style: StrokeStyle(lineWidth: 1.5)
                    )

                    // Bob color
                    let bobColor = PostureVisualStyle.metricColor(ratio: ratio)

                    // Bob (circle for all, but size varies)
                    let bobSize: CGFloat = isWorst ? 12 : 8
                    let bobPath = Path(ellipseIn: CGRect(
                        x: bobPoint.x - bobSize, y: bobPoint.y - bobSize,
                        width: bobSize * 2, height: bobSize * 2
                    ))
                    context.fill(bobPath, with: .color(bobColor.opacity(opacity)))

                    if isWorst {
                        let ringPath = Path(ellipseIn: CGRect(
                            x: bobPoint.x - bobSize - 3, y: bobPoint.y - bobSize - 3,
                            width: (bobSize + 3) * 2, height: (bobSize + 3) * 2
                        ))
                        context.stroke(ringPath, with: .color(.red), style: StrokeStyle(lineWidth: 1.5))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: timeline.date) { _, _ in
                stepPhysics(dt: 1.0 / 60.0)
            }

            // Labels + countdown
            VStack {
                Spacer()
                if observer.data.isAlertMode {
                    if let worst = observer.data.worstOffender {
                        Text(worst.key.displayName)
                            .font(.headline)
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

    private func stepPhysics(dt: CGFloat) {
        for i in 0..<5 {
            let ratio = isAbsent ? Float(0) : observer.data.metric(for: metricKeys[i]).clampedRatio
            let targetAngle = CGFloat(ratio) * Self.maxAngle

            let diff = pendulumAngles[i] - targetAngle
            pendulumVelocities[i] -= Self.springConstant * diff * dt
            pendulumVelocities[i] *= Self.damping
            pendulumAngles[i] += pendulumVelocities[i] * dt
        }
    }
}

// MARK: - Physics Testing Support

struct PendulumPhysics {
    var angle: CGFloat = 0
    var velocity: CGFloat = 0

    mutating func step(targetAngle: CGFloat, dt: CGFloat,
                       springConstant: CGFloat = 50.0, damping: CGFloat = 0.88) {
        let diff = angle - targetAngle
        velocity -= springConstant * diff * dt
        velocity *= damping
        angle += velocity * dt
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant24View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .twist,
        worstRatio: 0.9
    )
    let observer = PostureDisplayObserver(source: source)
    Variant24View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant24View()
        .environmentObject(observer)
}
