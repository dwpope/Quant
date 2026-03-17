import Foundation
import Combine
import PostureLogic

@MainActor
final class LivePostureDataSource: ObservableObject, PostureDataSourceProtocol {
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
