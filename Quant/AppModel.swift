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
    @Published var latestSample: PoseSample?

    // MARK: - Calibration Properties

    @Published var calibrationStatus: CalibrationStatus = .waiting
    @Published var calibrationProgress: Float = 0
    @Published var baseline: Baseline?
    @Published var needsCalibration: Bool = true

    // MARK: - Private Properties

    private let arService = ARSessionService()
    private lazy var pipeline: Pipeline = {
        Pipeline(provider: arService)
    }()
    private var cancellables = Set<AnyCancellable>()
    private let calibrationEngine = CalibrationEngine()

    private static let baselineKey = "com.quant.savedBaseline"

    // MARK: - Initialization

    init() {
        loadBaseline()
        setupPipeline()
    }

    // MARK: - Pipeline Setup

    private func setupPipeline() {
        pipeline.$latestSample
            .assign(to: &$latestSample)

        pipeline.$currentMode
            .assign(to: &$currentMode)

        pipeline.$depthConfidence
            .assign(to: &$depthConfidence)

        pipeline.$trackingQuality
            .assign(to: &$trackingQuality)

        pipeline.$fps
            .assign(to: &$fps)

        // Feed samples into the calibration engine while calibrating
        pipeline.$latestSample
            .compactMap { $0 }
            .sink { [weak self] sample in
                self?.feedCalibration(sample)
            }
            .store(in: &cancellables)
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

    func startCalibration() {
        calibrationEngine.reset()
        calibrationStatus = .waiting
        calibrationProgress = 0
    }

    func recalibrate() {
        baseline = nil
        pipeline.baseline = nil
        needsCalibration = true
        startCalibration()
    }

    // MARK: - Private Methods

    private func feedCalibration(_ sample: PoseSample) {
        guard needsCalibration else { return }

        let status = calibrationEngine.addSample(sample)
        calibrationStatus = status
        calibrationProgress = calibrationEngine.progress

        if case .success = status, let newBaseline = calibrationEngine.resultBaseline {
            baseline = newBaseline
            pipeline.baseline = newBaseline
            needsCalibration = false
            saveBaseline(newBaseline)
        }
    }

    // MARK: - Persistence

    private func saveBaseline(_ baseline: Baseline) {
        guard let data = try? JSONEncoder().encode(baseline) else { return }
        UserDefaults.standard.set(data, forKey: Self.baselineKey)
    }

    private func loadBaseline() {
        guard let data = UserDefaults.standard.data(forKey: Self.baselineKey),
              let saved = try? JSONDecoder().decode(Baseline.self, from: data) else {
            return
        }

        if saved.isStale() {
            UserDefaults.standard.removeObject(forKey: Self.baselineKey)
            return
        }

        baseline = saved
        pipeline.baseline = saved
        needsCalibration = false
    }
}
