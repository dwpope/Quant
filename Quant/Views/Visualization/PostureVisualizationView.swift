import RealityKit
import SwiftUI

/// SwiftUI container hosting the 3D posture visualization.
///
/// Step 3 scaffold: renders the **static** placeholder scene built by
/// ``PostureVisualizationScene`` (shoulder disc, head, tick markers) viewed
/// through a slightly-angled overhead camera. There is intentionally **no
/// ViewModel binding here yet** — Step 4 adds the `RealityView` `update`
/// closure that drives entity transforms from
/// `PostureVisualizationViewModel`. Keeping Step 3 purely static keeps the
/// blast radius tiny and the RealityKit scaffold independently reviewable.
struct PostureVisualizationView: View {
    var body: some View {
        RealityView { content in
            content.add(PostureVisualizationScene.makeAssembly())
            content.add(PostureVisualizationScene.makeCamera())
        }
        .background(Color(white: 0.06))
        .ignoresSafeArea()
    }
}

#Preview {
    PostureVisualizationView()
}
