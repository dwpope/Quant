import RealityKit
import SwiftUI

/// SwiftUI container hosting the 3D posture visualization.
///
/// Step 4: the scaffold's static scene (built once in `make`) is now driven
/// live. `update:` re-runs whenever the observed `PostureVisualizationViewModel`
/// publishes — it resolves the assembly root by name and hands it to
/// ``PostureVisualizationBinding/apply(_:to:)``, which writes the entity
/// transforms. The view owns the ViewModel and binds it to `AppModel`'s
/// pipeline publishers once on appear (repo convention: `AppModel` is an
/// environment object). Smooth animated transitions and navigation wiring are
/// Step 5 — Step 4 keeps the blast radius to "values reach the entities".
struct PostureVisualizationView: View {

    @EnvironmentObject private var appModel: AppModel

    @StateObject private var viewModel = PostureVisualizationViewModel()

    /// `bind(to:)` appends Combine subscriptions; guard so a re-appear does
    /// not stack duplicate pipelines onto the same ViewModel.
    @State private var didBind = false

    var body: some View {
        RealityView { content in
            content.add(PostureVisualizationScene.makeAssembly())
            content.add(PostureVisualizationScene.makeCamera())
        } update: { content in
            guard let assembly = content.entities.first(where: {
                $0.name == PostureVisualizationScene.EntityName.assembly
            }) else { return }
            PostureVisualizationBinding.apply(viewModel, to: assembly)
        }
        .background(Color(white: 0.06))
        .ignoresSafeArea()
        .onAppear {
            guard !didBind else { return }
            viewModel.bind(to: appModel)
            didBind = true
        }
    }
}

#Preview {
    PostureVisualizationView()
        .environmentObject(AppModel())
}
