import Combine
import Foundation

/// A ``PoseProvider`` that feeds pre-recorded samples into the Pipeline.
///
/// Wraps a ``ReplayService`` and converts each ``PoseSample`` into an
/// ``InputFrame`` with ``InputFrame/precomputedSample`` set, so the Pipeline
/// skips pose detection and runs the sample through metrics, posture, and
/// nudge engines — the same code path as live camera input.
public final class ReplayPoseProvider: PoseProvider {

    public var framePublisher: AnyPublisher<InputFrame, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    private let frameSubject = PassthroughSubject<InputFrame, Never>()
    private let replayService: ReplayService
    private var playbackTask: Task<Void, Never>?

    public init(replayService: ReplayService) {
        self.replayService = replayService
    }

    public func start() async throws {
        guard let stream = replayService.play() else { return }

        playbackTask = Task { [weak self] in
            for await sample in stream {
                guard let self = self else { break }
                let frame = InputFrame(
                    timestamp: sample.timestamp,
                    pixelBuffer: nil,
                    depthMap: nil,
                    cameraIntrinsics: nil,
                    precomputedSample: sample
                )
                self.frameSubject.send(frame)
            }
        }
    }

    public func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        replayService.stop()
    }
}
