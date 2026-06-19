import Foundation
import RealityKit
import SwiftUI

/// SwiftUI container hosting the 3D posture visualization.
///
/// Step 5 — integration & polish. The static scaffold (Step 3) is driven live
/// by the ViewModel (Step 4); this step makes it demo-ready:
///
/// * A `TimelineView(.animation)` wraps the `RealityView` so `update:` re-runs
///   every frame. `RealityView` keeps its structural identity across timeline
///   ticks, so the scene is built **once** (`make`) and only re-bound
///   (`update`) — the Apple-documented SwiftUI↔RealityKit animation pattern.
///   This continuous re-application is also what makes the ViewModel's α=0.2
///   low-pass read as a smooth ~0.3 s ease on video.
/// * A pure wall-clock `pulse` (0…1) feeds the calibrating "breathing" grey
///   (see ``PostureVisualizationBinding/stateTint(stateColor:isCalibrating:pulse:)``).
/// * A faint static ghost (``PostureVisualizationScene/makeGhost()``) marks the
///   calibrated baseline behind the live assembly.
/// * Presented as a full-screen cover from `ContentView`, so it carries a
///   `\.dismiss` close affordance (mirrors `VariantShowcaseView`).
struct PostureVisualizationView: View {

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = PostureVisualizationViewModel()

    /// Dev tuning HUD visibility. Off by default — the shipped visualization
    /// stays purely graphical; this is opt-in for mapping refinement only.
    /// Mirrored into `viewModel.isTuningHUDActive` so the ViewModel only pays
    /// for the HUD's published properties while the panel is shown.
    @State private var showValues = false

    #if DEBUG
    /// Dev-notes panel (changelog + open actions) visibility — Debug only,
    /// stripped from Release so it never ships.
    @State private var showNotes = false

    /// Head-yaw calibration slider visibility — Debug only. Lets us tune
    /// `HeadYawTuning.oneEarCalibration` on device against known turn angles.
    @State private var showCalibration = false
    #endif

    /// Calibration-pulse period (seconds) — a slow, organic "breathing" beat.
    private static let pulsePeriod = 1.6

    var body: some View {
        TimelineView(.animation) { timeline in
            let pulse = Self.pulse(at: timeline.date)
            RealityView { content in
                // Async: the figure is loaded from `quant_person.usdz` (falls
                // back to the procedural scaffold on failure). The ghost is a
                // rest-pose clone of the live assembly, so it must be built
                // *after* loading and added first stays the live one for the
                // update lookup (the clone is renamed to PostureGhost).
                let assembly = await PostureVisualizationScene.loadAssembly()
                content.add(assembly)
                if !PostureVisualizationBinding.debug.hideGhost {
                    content.add(PostureVisualizationScene.makeGhost(from: assembly))
                }
                content.add(PostureVisualizationScene.makeCamera())
            } update: { content in
                guard let assembly = content.entities.first(where: {
                    $0.name == PostureVisualizationScene.EntityName.assembly
                }) else { return }
                PostureVisualizationBinding.apply(viewModel, to: assembly, pulse: pulse)
            }
        }
        .background(Color(white: 0.06))
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding()
            }
            .accessibilityLabel("Close visualization")
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 10) {
                if showValues {
                    PostureVisualizationValuesOverlay(viewModel: viewModel)
                        .transition(.opacity)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showValues.toggle() }
                    refreshTuningHUDActive()
                } label: {
                    Image(systemName: showValues ? "gauge.with.dots.needle.bottom.50percent" : "gauge.with.dots.needle.0percent")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(showValues ? 0.95 : 0.55))
                        .padding()
                }
                .accessibilityLabel(showValues ? "Hide tuning values" : "Show tuning values")
            }
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showNotes.toggle() }
                } label: {
                    Image(systemName: showNotes ? "info.circle.fill" : "info.circle")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(showNotes ? 0.95 : 0.55))
                        .padding()
                }
                .accessibilityLabel(showNotes ? "Hide dev notes" : "Show dev notes")

                if showNotes {
                    PostureVisualizationNotesOverlay()
                        .padding(.leading)
                        .transition(.opacity)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 10) {
                if showCalibration {
                    PostureVisualizationCalibrationOverlay(viewModel: viewModel, appModel: appModel)
                        .transition(.opacity)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showCalibration.toggle() }
                    refreshTuningHUDActive()
                } label: {
                    Image(systemName: showCalibration ? "slider.horizontal.3" : "slider.horizontal.below.rectangle")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(showCalibration ? 0.95 : 0.55))
                        .padding()
                }
                .accessibilityLabel(showCalibration ? "Hide tuning panel" : "Show tuning panel")
            }
        }
        #endif
        .onAppear {
            viewModel.bind(to: appModel)   // idempotent — replaces, never stacks
        }
    }

    /// The ViewModel only recomputes the raw-input HUD mirrors while
    /// `isTuningHUDActive` (an opt-in cost). Both the values gauge and — in Debug
    /// — the calibration panel display those mirrors, so the flag must be on while
    /// *either* is open, else the second panel shows stale zeros.
    private func refreshTuningHUDActive() {
        #if DEBUG
        viewModel.isTuningHUDActive = showValues || showCalibration
        #else
        viewModel.isTuningHUDActive = showValues
        #endif
    }

    /// Sine phase in 0…1 with period ``pulsePeriod``, derived purely from the
    /// wall clock so the pulse needs no stored animation state and stays in
    /// step regardless of how often the timeline ticks.
    private static func pulse(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        return (sin(2 * .pi * t / pulsePeriod) + 1) / 2
    }
}

#Preview {
    PostureVisualizationView()
        .environmentObject(AppModel())
}
