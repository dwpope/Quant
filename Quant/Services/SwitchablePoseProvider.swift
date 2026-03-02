import Foundation
import Combine
import PostureLogic

/// A proxy PoseProvider that forwards frames from a swappable underlying source.
///
/// This allows the Pipeline to be initialized once and kept alive while the
/// actual camera source (rear ARKit vs front AVFoundation) is swapped at runtime.
///
/// ## How It Works
///
/// ```
/// ARSessionService ──┐
///                     ├──→ SwitchablePoseProvider ──→ Pipeline
/// FrontCameraService ─┘       (attach/detach)
/// ```
///
/// Call `attach(source:)` to connect a new provider. The previous source's
/// subscription is automatically cancelled. Call `detach()` to stop forwarding
/// without attaching a new source.
///
/// ## Lifecycle
///
/// SwitchablePoseProvider does NOT manage the lifecycle of attached sources.
/// The caller (AppModel) is responsible for calling `start()` / `stop()` on
/// the actual camera services. This class only forwards frames.
final class SwitchablePoseProvider: PoseProvider {
    var framePublisher: AnyPublisher<InputFrame, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    private let frameSubject = PassthroughSubject<InputFrame, Never>()
    private var cancellable: AnyCancellable?

    /// Attach a new frame source, replacing any previously attached source.
    ///
    /// The previous source's subscription is cancelled immediately.
    /// Frames from the new source will be forwarded to `framePublisher`.
    ///
    /// - Parameter source: The PoseProvider to forward frames from.
    func attach(source: any PoseProvider) {
        cancellable?.cancel()
        cancellable = source.framePublisher.sink { [weak self] frame in
            self?.frameSubject.send(frame)
        }
    }

    /// Stop forwarding frames from the current source.
    func detach() {
        cancellable?.cancel()
        cancellable = nil
    }

    // MARK: - PoseProvider conformance (no-op)

    // Lifecycle is managed by the actual camera services, not this proxy.

    func start() async throws {
        // No-op — lifecycle managed by the attached source
    }

    func stop() {
        // No-op — lifecycle managed by the attached source
    }
}
