import Foundation
import Combine
import PostureLogic

@MainActor
final class LivePostureDataSource: ObservableObject, PostureDataSourceProtocol {
    // Teardown only releases stored properties; it touches no main-actor state.
    // Marking it `nonisolated` keeps Swift's MainActor isolated-deinit
    // back-deploy shim out of XCTest's NSInvocation-driven dealloc path, which
    // otherwise corrupts the heap and aborts under Xcode 26 / iOS 26.
    nonisolated deinit {}

    @Published private(set) var currentData: PostureDisplayData

    private var cancellables = Set<AnyCancellable>()

    init(appModel: AppModel) {
        self.currentData = PostureDisplayData.make(
            from: appModel.latestMetrics,
            postureState: appModel.postureState,
            nudgeDecision: appModel.nudgeDecision,
            trackingQuality: appModel.trackingQuality,
            thresholds: appModel.postureThresholds
        )

        Publishers.CombineLatest4(
            appModel.$latestMetrics,
            appModel.$postureState,
            appModel.$nudgeDecision,
            appModel.$trackingQuality
        )
        .map { [weak appModel] metrics, state, nudge, quality in
            PostureDisplayData.make(
                from: metrics,
                postureState: state,
                nudgeDecision: nudge,
                trackingQuality: quality,
                thresholds: appModel?.postureThresholds ?? PostureThresholds()
            )
        }
        .receive(on: RunLoop.main)
        .assign(to: &$currentData)
    }
}
