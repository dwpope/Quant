import SwiftUI
import PostureLogic

/// Variant 43: Water Surface — A top-down view of a water surface that responds to posture metrics
/// via Metal shader-driven wave distortion. Good posture shows a calm pool; bad posture creates
/// turbulent waves, vortices, and chop. Uses the waveDistortion shader from MetalShaderBridge.
struct Variant43View: View {
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
                if isAbsent {
                    AbsenceOverlay {
                        waterContent(size: geo.size)
                    }
                } else {
                    waterContent(size: geo.size)
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

    @ViewBuilder
    private func waterContent(size: CGSize) -> some View {
        PostureShaderFallback {
            shaderWaterView(size: size)
        } fallbackContent: {
            canvasWaterFallback(size: size)
        }
    }

    @available(iOS 17, *)
    private func shaderWaterView(size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: isAbsent)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                // Base water surface gradient
                waterGradient(size: size)
                    .postureWaveEffect(data: observer.data, time: time)

                // Floating metric markers
                metricMarkers(size: size, time: time)

                // Alert overlay
                alertOverlay()
            }
        }
    }

    private func canvasWaterFallback(size: CGSize) -> some View {
        ZStack {
            waterGradient(size: size)

            // Simple concentric ripples as fallback
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height / 2
                let maxRadius = min(canvasSize.width, canvasSize.height) * 0.4

                for i in 0..<4 {
                    let radius = maxRadius * CGFloat(i + 1) / 4
                    context.stroke(
                        Path(ellipseIn: CGRect(x: cx - radius, y: cy - radius,
                                                width: radius * 2, height: radius * 2)),
                        with: .color(.white.opacity(0.1 - Double(i) * 0.02)),
                        style: StrokeStyle(lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            metricMarkers(size: size, time: 0)
            alertOverlay()
        }
    }

    private func waterGradient(size: CGSize) -> some View {
        RadialGradient(
            colors: [
                Color(hue: 0.50, saturation: 0.5, brightness: 0.55),  // lighter aqua center
                Color(hue: 0.52, saturation: 0.7, brightness: 0.35)   // deep teal edges
            ],
            center: .center,
            startRadius: 0,
            endRadius: max(size.width, size.height) * 0.7
        )
        .ignoresSafeArea()
    }

    private func metricMarkers(size: CGSize, time: TimeInterval) -> some View {
        let metrics: [(MetricKey, Float, CGFloat, CGFloat)] = [
            (.forwardCreep, observer.data.metric(for: .forwardCreep).clampedRatio, 0.5, 0.3),
            (.headDrop, observer.data.metric(for: .headDrop).clampedRatio, 0.35, 0.5),
            (.shoulderRounding, observer.data.metric(for: .shoulderRounding).clampedRatio, 0.65, 0.5),
            (.lateralLean, observer.data.metric(for: .lateralLean).clampedRatio, 0.35, 0.7),
            (.twist, observer.data.metric(for: .twist).clampedRatio, 0.65, 0.7),
        ]

        let worst = observer.data.worstOffender

        return ZStack {
            ForEach(Array(metrics.enumerated()), id: \.offset) { idx, item in
                let (key, ratio, fracX, fracY) = item
                let isWorst = worst?.key == key
                let waveOffX = isAbsent ? 0.0 : sin(time * 1.5 + Double(idx)) * Double(ratio) * 5
                let waveOffY = isAbsent ? 0.0 : cos(time * 1.2 + Double(idx) * 0.7) * Double(ratio) * 5

                // Leaf-shaped marker
                ZStack {
                    Ellipse()
                        .fill(isWorst && ratio > 0.5
                              ? Color(hue: Double(0.1 - min(Double(ratio), 1.0) * 0.1), saturation: 0.7, brightness: 0.7)
                              : Color(hue: 0.35, saturation: 0.5, brightness: 0.6))
                        .frame(width: isWorst ? 18 : 12, height: isWorst ? 24 : 16)

                    if isWorst || ratio > 0.3 {
                        Text(key.displayName.prefix(3).uppercased())
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .opacity(0.85)
                .offset(x: size.width * fracX - size.width / 2 + waveOffX,
                        y: size.height * fracY - size.height / 2 + waveOffY)
            }
        }
    }

    @ViewBuilder
    private func alertOverlay() -> some View {
        if observer.data.isAlertMode, let worst = observer.data.worstOffender {
            VStack {
                Spacer()
                Text(worst.key.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.5)))

                if let seconds = observer.data.nudgeCountdownSeconds {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.cyan)
                            .frame(width: 6, height: 6)
                        Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant43View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .twist,
        worstRatio: 0.9
    )
    let observer = PostureDisplayObserver(source: source)
    Variant43View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant43View()
        .environmentObject(observer)
}
