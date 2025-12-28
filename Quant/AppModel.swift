import SwiftUI
import Combine
import PostureLogic

@MainActor
class AppModel: ObservableObject {
    private let arService = ARSessionService()
    private lazy var pipeline: Pipeline = {
        Pipeline(provider: arService)
    }()
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupPipeline()
    }

    private func setupPipeline() {
        pipeline.$latestSample
            .sink { sample in
                if let sample = sample {
                    print("Sample processed: \(sample.timestamp)")
                }
            }
            .store(in: &cancellables)
    }

    func startMonitoring() async {
        do {
            try await arService.start()
            print("AR session started successfully")
        } catch {
            print("Failed to start AR service: \(error)")
        }
    }
}
