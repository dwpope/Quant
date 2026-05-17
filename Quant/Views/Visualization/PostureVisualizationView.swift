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

    /// `bind(to:)` appends Combine subscriptions; guard so a re-appear does
    /// not stack duplicate pipelines onto the same ViewModel.
    @State private var didBind = false

    /// Calibration-pulse period (seconds) — a slow, organic "breathing" beat.
    private static let pulsePeriod = 1.6

    var body: some View {
        TimelineView(.animation) { timeline in
            let pulse = Self.pulse(at: timeline.date)
            RealityView { content in
                content.add(PostureVisualizationScene.makeGhost())
                content.add(PostureVisualizationScene.makeAssembly())
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
        .onAppear {
            guard !didBind else { return }
            viewModel.bind(to: appModel)
            didBind = true
        }
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
