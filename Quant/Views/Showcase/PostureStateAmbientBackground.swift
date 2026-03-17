import SwiftUI
import PostureLogic

struct PostureStateAmbientBackground: View {
    let state: PostureState
    var intensity: Double = 0.3

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [color.opacity(intensity), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .ignoresSafeArea()
            .animation(PostureAnimations.modeTransition, value: stateKey)
    }

    private var color: Color {
        PostureVisualStyle.stateColor(for: state)
    }

    private var stateKey: String {
        PostureVisualStyle.stateLabel(for: state)
    }
}
