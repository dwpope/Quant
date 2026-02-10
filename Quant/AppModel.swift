import SwiftUI
import Combine
import PostureLogic

@MainActor
class AppModel: ObservableObject {
    // MARK: - Published Properties for Debug UI

    @Published var currentMode: DepthMode = .twoDOnly
    @Published var depthConfidence: DepthConfidence = .unavailable
    @Published var trackingQuality: TrackingQuality = .lost
    @Published var fps: Float = 0.0

    // MARK: - Private Properties

    private let arService = ARSessionService()
    private lazy var pipeline: Pipeline = {
        Pipeline(provider: arService)
    }()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupPipeline()
    }

    // MARK: - Private Methods

    private func setupPipeline() {
        // Subscribe to pipeline updates
        pipeline.$latestSample
            .sink { sample in
                if let sample = sample {
                    print("Sample processed: \(sample.timestamp)")
                }
            }
            .store(in: &cancellables)

        // Bind pipeline properties to published properties for UI
        pipeline.$currentMode
            .assign(to: &$currentMode)

        pipeline.$depthConfidence
            .assign(to: &$depthConfidence)

        pipeline.$trackingQuality
            .assign(to: &$trackingQuality)

        pipeline.$fps
            .assign(to: &$fps)
    }

    // MARK: - Public Methods

    func startMonitoring() async {
        do {
            try await arService.start()
            print("AR session started successfully")
        } catch {
            print("Failed to start AR service: \(error)")
        }
    }

    func stopMonitoring() {
        arService.stop()
        cancellables.removeAll()
        print("AR session stopped and subscriptions cleaned up")
    }

    deinit {
        // Ensure cleanup on deallocation
        stopMonitoring()
    }
}
