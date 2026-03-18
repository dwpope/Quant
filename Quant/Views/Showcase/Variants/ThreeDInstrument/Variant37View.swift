import SwiftUI
import PostureLogic

/// Variant 37: Gyroscope Rings — Three concentric gimbal rings in perspective,
/// each tilting on a different rotational axis. When posture is perfect, rings are
/// coplanar nested circles. As posture degrades, rings tilt creating a chaotic arrangement.
struct Variant37View: View {
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
                        gyroscopeContent(size: geo.size)
                    }
                } else {
                    gyroscopeContent(size: geo.size)
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

    private func gyroscopeContent(size: CGSize) -> some View {
        let fc = isAbsent ? Float(0) : observer.data.metric(for: .forwardCreep).clampedRatio
        let hd = isAbsent ? Float(0) : observer.data.metric(for: .headDrop).clampedRatio
        let sr = isAbsent ? Float(0) : observer.data.metric(for: .shoulderRounding).clampedRatio
        let ll = isAbsent ? Float(0) : observer.data.metric(for: .lateralLean).clampedRatio
        let tw = isAbsent ? Float(0) : observer.data.metric(for: .twist).clampedRatio

        let smallDim = min(size.width, size.height)
        let outerDiam = smallDim * 0.7
        let middleDiam = smallDim * 0.52
        let innerDiam = smallDim * 0.36

        let rollAngle = Double(ll) * 30 // outer ring — lateral lean
        let pitchAngle = Double((fc + hd) / 2) * 30 // middle ring — forward/head
        let yawAngle = Double(tw) * 30 // inner ring — twist

        return ZStack {
            // Outer ring (Roll / Lateral Lean) — Blue
            Ellipse()
                .stroke(Color.blue, lineWidth: 3)
                .frame(width: outerDiam, height: outerDiam)
                .rotation3DEffect(.degrees(rollAngle), axis: (x: 0, y: 0, z: 1))
                .opacity(observer.data.isAlertMode && observer.data.worstOffender?.key != .lateralLean ? 0.2 : 1.0)

            // Middle ring (Pitch / Forward + Head) — Green
            Ellipse()
                .stroke(Color.green, lineWidth: 2.5)
                .frame(width: middleDiam, height: middleDiam)
                .rotation3DEffect(.degrees(pitchAngle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                .opacity(observer.data.isAlertMode && observer.data.worstOffender?.key != .forwardCreep && observer.data.worstOffender?.key != .headDrop ? 0.2 : 1.0)

            // Shoulder rounding deforms middle ring
            Ellipse()
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                .frame(width: middleDiam, height: middleDiam * (1.0 - CGFloat(sr) * 0.15))
                .rotation3DEffect(.degrees(pitchAngle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                .opacity(CGFloat(sr) > 0.1 ? 0.4 : 0)

            // Inner ring (Yaw / Twist) — Orange
            Ellipse()
                .stroke(Color.orange, lineWidth: 2)
                .frame(width: innerDiam, height: innerDiam)
                .rotation3DEffect(.degrees(yawAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .opacity(observer.data.isAlertMode && observer.data.worstOffender?.key != .twist ? 0.2 : 1.0)

            // Head marker dot on inner ring
            Circle()
                .fill(observer.data.isAlertMode ? Color.red : Color.orange)
                .frame(width: 8, height: 8)
                .offset(y: -innerDiam / 2)
                .rotation3DEffect(.degrees(yawAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)

            // Alert overlay
            if observer.data.isAlertMode, let worst = observer.data.worstOffender {
                VStack(spacing: 4) {
                    Text(worst.key.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(PostureVisualStyle.stateColor(for: observer.data.postureState))
                    if let seconds = observer.data.nudgeCountdownSeconds {
                        Text(PostureVisualStyle.nudgeCountdownLabel(seconds: seconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.6), value: fc)
        .animation(.easeInOut(duration: 0.6), value: hd)
        .animation(.easeInOut(duration: 0.6), value: ll)
        .animation(.easeInOut(duration: 0.6), value: tw)
    }
}

// MARK: - Previews

#Preview("Good Posture") {
    let source = MockPostureDataSource.preview(state: .good)
    let observer = PostureDisplayObserver(source: source)
    Variant37View()
        .environmentObject(observer)
}

#Preview("Alert Mode") {
    let source = MockPostureDataSource.preview(
        state: .drifting(since: Date().timeIntervalSince1970 - 5),
        worstMetric: .twist,
        worstRatio: 0.85
    )
    let observer = PostureDisplayObserver(source: source)
    Variant37View()
        .environmentObject(observer)
}

#Preview("Absent") {
    let source = MockPostureDataSource.preview(state: .absent)
    let observer = PostureDisplayObserver(source: source)
    Variant37View()
        .environmentObject(observer)
}
