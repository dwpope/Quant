import SwiftUI
import Combine
import PostureLogic

@MainActor
class AppModel: ObservableObject {
    private let arService = ARSessionService()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupPipeline()
    }
    
    private func setupPipeline() {
        arService.framePublisher
            .sink { frame in
                print("Frame received: \(frame.timestamp)")
            }
            .store(in: &cancellables)
    }
    
    func startMonitoring() async {
        do {
            try await arService.start()
        } catch {
            print("Failed to start AR service: \(error)")
        }
    }
}
