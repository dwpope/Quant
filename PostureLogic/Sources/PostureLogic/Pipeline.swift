import Combine
import Foundation

public class Pipeline {
    @Published public var latestSample: PoseSample?
    private var subscriptions = Set<AnyCancellable>()
    
    public init(provider: PoseProvider) {
        provider.framePublisher
            .sink { [weak self] frame in
                self?.process(frame)
            }
            .store(in: &subscriptions)
    }
    
    private func process(_ frame: InputFrame) {
        // Simple pass-through for Sprint 0 verification
        self.latestSample = PoseSample(
            timestamp: frame.timestamp,
            depthMode: .twoDOnly,
            headPosition: .zero,
            shoulderMidpoint: .zero,
            leftShoulder: .zero,
            rightShoulder: .zero,
            torsoAngle: 0,
            headForwardOffset: 0,
            shoulderTwist: 0,
            trackingQuality: .good
        )
    }
}
