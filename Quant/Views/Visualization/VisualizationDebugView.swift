// THROWAWAY — delete in Step 6 (plan.md).
//
// A developer-only screen that exercises `PostureVisualizationViewModel`
// across its full input range without a camera. Every slider/picker feeds the
// same camera-free `ingest(metrics:pose:state:quality:)` seam the live app
// uses; the readouts show all ten published outputs so the heuristics +
// low-pass smoothing can be validated by eye. Not wired into navigation here
// (that is Step 5) and removed entirely in Step 6.

import SwiftUI
import Foundation
import simd
import PostureLogic

struct VisualizationDebugView: View {

    // Live pipeline (used only when the "use live data" toggle is on). Repo
    // convention: AppModel is injected as an environment object.
    @EnvironmentObject private var appModel: AppModel

    // The system under test. Owned here so its @Published outputs drive the
    // readouts directly.
    @StateObject private var viewModel = PostureVisualizationViewModel()

    // MARK: Synthetic inputs (drive the VM when not on live data)

    @State private var twist: Double = 0              // RawMetrics.twist
    @State private var lateralLean: Double = 0        // RawMetrics.lateralLean
    @State private var forwardCreep: Double = 0       // RawMetrics.forwardCreep
    @State private var headForwardOffset: Double = 0  // PoseSample.headForwardOffset (m)
    @State private var shoulderTwist: Double = 0      // PoseSample.shoulderTwist (deg)
    @State private var shoulderTiltDegrees: Double = 0 // drives roll via shoulder line
    @State private var stateChoice: StateChoice = .calibrating
    @State private var trackingQuality: TrackingQuality = .good
    @State private var useLiveData: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Mode") {
                    Toggle("Use live data (camera pipeline)", isOn: $useLiveData)
                }

                Section("RawMetrics inputs") {
                    sliderRow("twist", $twist, in: -1 ... 1)
                    sliderRow("lateralLean", $lateralLean, in: -1 ... 1)
                    sliderRow("forwardCreep", $forwardCreep, in: -1 ... 2)
                }

                Section("PoseSample inputs") {
                    sliderRow("headForwardOffset (m)", $headForwardOffset, in: -0.3 ... 0.3)
                    sliderRow("shoulderTwist (deg)", $shoulderTwist, in: -90 ... 90)
                    sliderRow("shoulder line tilt (deg) → roll", $shoulderTiltDegrees, in: -90 ... 90)
                }

                Section("Discrete inputs") {
                    Picker("PostureState", selection: $stateChoice) {
                        ForEach(StateChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("TrackingQuality", selection: $trackingQuality) {
                        ForEach(Self.qualities, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }

                Section("Outputs (all 10 @Published)") {
                    outputRow("shoulderRotationDegrees", viewModel.shoulderRotationDegrees)
                    outputRow("sideLeanOffsetPoints", viewModel.sideLeanOffsetPoints)
                    outputRow("headForwardOffsetPoints", viewModel.headForwardOffsetPoints)
                    outputRow("assemblyScale", viewModel.assemblyScale)
                    outputRow("headYawDegrees", viewModel.headYawDegrees)
                    outputRow("headPitchDegrees", viewModel.headPitchDegrees)
                    outputRow("headRollDegrees", viewModel.headRollDegrees)
                    outputRow("opacity", viewModel.opacity)
                    HStack {
                        Text("stateColor").font(.caption)
                        Spacer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(viewModel.stateColor)
                            .frame(width: 32, height: 18)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary))
                    }
                    HStack {
                        Text("isCalibrating").font(.caption)
                        Spacer()
                        Image(systemName: viewModel.isCalibrating
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(viewModel.isCalibrating ? .green : .secondary)
                    }
                }
            }
            .navigationTitle("Visualization Debug")
        }
        .onAppear { pushUpdate() }
        .onChange(of: inputSignature) { pushUpdate() }
        // While on live data, re-push whenever any pipeline publisher emits.
        .onReceive(appModel.$latestMetrics) { _ in if useLiveData { pushUpdate() } }
        .onReceive(appModel.$latestSample) { _ in if useLiveData { pushUpdate() } }
        .onReceive(appModel.$postureState) { _ in if useLiveData { pushUpdate() } }
        .onReceive(appModel.$trackingQuality) { _ in if useLiveData { pushUpdate() } }
    }

    // MARK: Update plumbing

    /// One Equatable value covering every control, so a single `.onChange`
    /// re-pushes on any synthetic edit or mode flip (no per-slider modifiers).
    private var inputSignature: [Double] {
        [twist, lateralLean, forwardCreep, headForwardOffset, shoulderTwist,
         shoulderTiltDegrees,
         Double(StateChoice.allCases.firstIndex(of: stateChoice) ?? 0),
         Double(Self.qualities.firstIndex(of: trackingQuality) ?? 0),
         useLiveData ? 1 : 0]
    }

    /// Routes synthetic *or* live inputs through the same camera-free seam.
    private func pushUpdate() {
        if useLiveData {
            viewModel.ingest(
                metrics: appModel.latestMetrics,
                pose: appModel.latestSample,
                state: appModel.postureState,
                quality: appModel.trackingQuality
            )
        } else {
            viewModel.ingest(
                metrics: syntheticMetrics,
                pose: syntheticPose,
                state: stateChoice.postureState,
                quality: trackingQuality
            )
        }
    }

    private var syntheticMetrics: RawMetrics {
        RawMetrics(
            timestamp: Date().timeIntervalSince1970,
            forwardCreep: Float(forwardCreep),
            headDrop: 0,
            shoulderRounding: 0,
            lateralLean: Float(lateralLean),
            twist: Float(twist),
            movementLevel: 0,
            headMovementPattern: .still
        )
    }

    /// Builds a `PoseSample` whose shoulder line subtends `shoulderTiltDegrees`,
    /// because the VM derives roll from `atan2(rightS.y−leftS.y,
    /// rightS.x−leftS.x)`. With left at the origin and right on the unit
    /// circle, that angle equals the slider value (pre 1.5× amplify / ±45 cap).
    private var syntheticPose: PoseSample {
        let t = shoulderTiltDegrees * .pi / 180
        return PoseSample(
            timestamp: Date().timeIntervalSince1970,
            depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0, 0, Float(headForwardOffset)),
            shoulderMidpoint: .zero,
            leftShoulder: .zero,
            rightShoulder: SIMD3<Float>(Float(cos(t)), Float(sin(t)), 0),
            torsoAngle: 0,
            headForwardOffset: Float(headForwardOffset),
            shoulderTwist: Float(shoulderTwist),
            shoulderWidthRaw: 0.3,
            trackingQuality: trackingQuality
        )
    }

    // MARK: Row builders

    private func sliderRow(
        _ title: String,
        _ value: Binding<Double>,
        in range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: "%.3f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .disabled(useLiveData)
        }
    }

    private func outputRow(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title).font(.caption)
            Spacer()
            Text(String(format: "%.3f", value))
                .font(.caption.monospacedDigit())
        }
    }

    // MARK: Discrete input choices

    private static let qualities: [TrackingQuality] = [.lost, .degraded, .good]

    private enum StateChoice: String, CaseIterable, Identifiable {
        case absent, calibrating, good, drifting, bad
        var id: String { rawValue }
        var postureState: PostureState {
            switch self {
            case .absent:      return .absent
            case .calibrating: return .calibrating
            case .good:        return .good
            case .drifting:    return .drifting(since: Date().timeIntervalSince1970)
            case .bad:         return .bad(since: Date().timeIntervalSince1970)
            }
        }
    }
}

#Preview {
    VisualizationDebugView()
        .environmentObject(AppModel())
}
