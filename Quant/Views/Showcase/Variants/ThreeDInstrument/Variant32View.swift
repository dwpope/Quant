import SwiftUI
import SceneKit
import PostureLogic

/// Variant 32: Muscle Heatmap — A 3D body model (SceneKit) with emission-colored
/// stress regions overlaid on body parts. The 3D model deforms based on posture metrics
/// while surface nodes shift color from neutral to red based on each metric's ratio.
/// Falls back to Canvas-only rendering when SceneKit is unavailable.
struct Variant32View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    @State private var showingSettings = false
    @State private var scene = PostureSceneBuilder.makeBodyScene()

    private var isAbsent: Bool {
        switch observer.data.postureState {
        case .absent, .calibrating: return true
        default: return false
        }
    }

    private var displayData: PostureDisplayData {
        isAbsent ? PostureDisplayData.zero(thresholds: observer.data.thresholds) : observer.data
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PostureStateAmbientBackground(state: observer.data.postureState)

                if isAbsent {
                    AbsenceOverlay {
                        sceneKitBody
                    }
                } else {
                    sceneKitBody
                }

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

    private var sceneKitBody: some View {
        SceneKitViewBridge(
            scene: scene,
            data: displayData,
            isPlaying: !isAbsent
        )
    }
}

// MARK: - PostureDisplayData Zero Helper

private extension PostureDisplayData {
    static func zero(thresholds: PostureThresholds) -> PostureDisplayData {
        let metrics = MetricKey.allCases.map { key in
            MetricInfo(
                key: key,
                value: 0,
                ratio: 0,
                threshold: thresholds.threshold(for: key),
                isWorstOffender: false
            )
        }
        return PostureDisplayData(
            metrics: metrics,
            postureState: .absent,
            nudgeDecision: .none,
            trackingQuality: .lost,
            worstOffender: nil,
            timeInCurrentState: nil,
            nudgeCountdownSeconds: nil,
            thresholds: thresholds
        )
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
