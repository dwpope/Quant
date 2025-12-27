import Foundation
import Combine

public final class MockPoseProvider: PoseProvider {
    public var framePublisher: AnyPublisher<InputFrame, Never> {
        frameSubject.eraseToAnyPublisher()
    }
    
    private let frameSubject = PassthroughSubject<InputFrame, Never>()
    private var isRunning = false
    
    public init() {}
    
    public func start() async throws {
        isRunning = true
    }
    
    public func stop() {
        isRunning = false
    }
    
    // MARK: - Test Helpers
    
    public func emit(frame: InputFrame) {
        guard isRunning else { return }
        frameSubject.send(frame)
    }
    
    public func emit(scenario: TestScenario) {
        for frame in scenario.frames {
            emit(frame: frame)
        }
    }
}
