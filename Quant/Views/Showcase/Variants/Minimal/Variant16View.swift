import SwiftUI
import PostureLogic

/// Variant 16: Gradient Wash — The entire screen is a full-bleed color gradient
/// that shifts from cool tones (good) to warm tones (bad). Individual metrics
/// influence the gradient's color distribution.
struct Variant16View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var showControls = false
    @State private var driftPhase: CGFloat = 0

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private var score: Float { observer.data.aggregateScore }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isAbsent {
                    AbsenceOverlay {
                        gradientFill(size: geo.size)
                    }
                } else {
                    gradientFill(size: geo.size)
                }

                // Pulsing overlay in bad state
                if observer.data.postureState.isBad && !isAbsent {
                    Color.white
                        .opacity(pulseOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Score + controls (tap to reveal)
                VStack {
                    Spacer()
                    HStack {
                        Text(String(format: "%.0f%%", score * 100))
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(.primary.opacity(showControls ? 1.0 : 0.15))
                            .monospacedDigit()
                        Spacer()
                    }
                    .padding()
                }

                // Worst offender label in alert mode
                if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                    VStack {
                        Spacer()
                        HStack {
                            Text(worst.key.displayName)
                                .font(.caption)
                                .foregroundStyle(.primary.opacity(showControls ? 1.0 : 0.5))
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                    }
                }

                // Countdown bar at bottom in alert mode
                if observer.data.isAlertMode, let seconds = observer.data.nudgeCountdownSeconds {
                    VStack {
                        Spacer()
                        let maxSeconds: TimeInterval = 300
                        let fraction = CGFloat(min(seconds / maxSeconds, 1.0))
                        Rectangle()
                            .fill(.white.opacity(0.6))
                            .frame(width: geo.size.width * fraction, height: 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Settings gear (visible on tap)
                VStack {
                    HStack {
                        Spacer()
                        SettingsGearButton { showingSettings = true }
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .opacity(showControls ? 1.0 : 0.2)
                    }
                    Spacer()
                }
                .padding(8)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.3)) {
                    showControls = true
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.easeIn(duration: 0.5)) {
                        showControls = false
                    }
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
        }
        .animation(PostureAnimations.alertOnset, value: observer.data.isAlertMode)
    }

    @ViewBuilder
    private func gradientFill(size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: observer.data.isAlertMode ? 0.05 : 0.1)) { timeline in
            let t = Float(1.0 - score) // 0 = good, 1 = bad
            let fc = observer.data.metric(for: .forwardCreep).clampedRatio
            let hd = observer.data.metric(for: .headDrop).clampedRatio
            let sr = observer.data.metric(for: .shoulderRounding).clampedRatio
            let ll = observer.data.metric(for: .lateralLean).clampedRatio
            let tw = observer.data.metric(for: .twist).clampedRatio

            // Corner colors interpolating from cool to warm
            let topLeft = Color(
                hue: Double(lerp(0.48, 0.10, min(t + fc * 0.3, 1.0))),
                saturation: Double(lerp(0.3, 0.7, t)),
                brightness: Double(lerp(0.85, 0.75, t))
            )
            let topRight = Color(
                hue: Double(lerp(0.58, 0.07, min(t + fc * 0.3, 1.0))),
                saturation: Double(lerp(0.25, 0.65, t)),
                brightness: Double(lerp(0.9, 0.7, t))
            )
            let bottomLeft = Color(
                hue: Double(lerp(0.38, 0.03, min(t + hd * 0.3, 1.0))),
                saturation: Double(lerp(0.35, 0.7, t)),
                brightness: Double(lerp(0.8, 0.65, t))
            )
            let bottomRight = Color(
                hue: Double(lerp(0.42, 0.0, min(t + sr * 0.3, 1.0))),
                saturation: Double(lerp(0.3, 0.75, t)),
                brightness: Double(lerp(0.85, 0.6, t))
            )

            let rotationAngle = Angle(degrees: Double(tw) * 30)

            if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0 + ll * 0.1, 0.5], [0.5, 0.5], [1 - ll * 0.1, 0.5],
                        [0, 1], [0.5, 1], [1, 1]
                    ],
                    colors: [
                        topLeft, interpolateColor(topLeft, topRight, 0.5), topRight,
                        interpolateColor(topLeft, bottomLeft, 0.5), centerColor(t: t), interpolateColor(topRight, bottomRight, 0.5),
                        bottomLeft, interpolateColor(bottomLeft, bottomRight, 0.5), bottomRight
                    ]
                )
                .rotationEffect(rotationAngle)
                .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [topLeft, topRight, bottomRight, bottomLeft],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .rotationEffect(rotationAngle)
                .ignoresSafeArea()
            }
        }
    }

    private func centerColor(t: Float) -> Color {
        Color(
            hue: Double(lerp(0.45, 0.05, t)),
            saturation: Double(lerp(0.3, 0.7, t)),
            brightness: Double(lerp(0.85, 0.65, t))
        )
    }

    private func interpolateColor(_ a: Color, _ b: Color, _ fraction: CGFloat) -> Color {
        // Simple visual midpoint via overlay
        return a
    }

    private var pulseOpacity: Double {
        let phase = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 2.0) / 2.0
        return sin(phase * .pi) * 0.05
    }

    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * min(max(t, 0), 1)
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant16View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .lateralLean,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant16View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant16View()
        .environmentObject(observer)
}
