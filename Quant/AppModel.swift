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

    // MARK: - Published Properties for Calibration

    @Published var calibrationStatus: CalibrationStatus = .waiting
    @Published var calibrationProgress: Float = 0.0
    @Published var baseline: Baseline?
    @Published var needsCalibration: Bool = true

    // MARK: - Private Properties

    private let arService = ARSessionService()
    private lazy var pipeline: Pipeline = {
        Pipeline(provider: arService)
    }()
    private var cancellables = Set<AnyCancellable>()
    private let calibrationService = CalibrationService()

    // Persistence keys
    private let baselineKey = "com.quant.baseline"

    // MARK: - Initialization

    init() {
        loadBaseline()
        setupPipeline()
    }

    // MARK: - Private Methods

    private func setupPipeline() {
        // Subscribe to pipeline updates
        pipeline.$latestSample
            .sink { [weak self] sample in
                guard let self = self, let sample = sample else { return }

                print("Sample processed: \(sample.timestamp)")

                // Feed samples to calibration service if calibrating
                if case .sampling = self.calibrationService.status {
                    self.calibrationService.addSample(sample)
                    self.updateCalibrationState()
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

    // MARK: - Calibration Methods

    func startCalibration() {
        calibrationService.startCalibration()
        updateCalibrationState()
    }

    func cancelCalibration() {
        calibrationService.reset()
        updateCalibrationState()
    }

    func retryCalibration() {
        calibrationService.reset()
        calibrationService.startCalibration()
        updateCalibrationState()
    }

    func finishCalibration() {
        if let baseline = calibrationService.computeBaseline() {
            self.baseline = baseline
            saveBaseline(baseline)
            needsCalibration = false
            print("Calibration complete. Baseline saved.")
        }
        calibrationService.reset()
        updateCalibrationState()
    }

    private func updateCalibrationState() {
        calibrationStatus = calibrationService.status
        calibrationProgress = calibrationService.progress
    }

    // MARK: - Baseline Persistence

    private func saveBaseline(_ baseline: Baseline) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(baseline)
            UserDefaults.standard.set(data, forKey: baselineKey)
            print("Baseline saved to UserDefaults")
        } catch {
            print("Failed to save baseline: \(error)")
        }
    }

    private func loadBaseline() {
        guard let data = UserDefaults.standard.data(forKey: baselineKey) else {
            print("No saved baseline found")
            needsCalibration = true
            return
        }

        do {
            let decoder = JSONDecoder()
            let baseline = try decoder.decode(Baseline.self, from: data)

            // Check if baseline is stale
            if baseline.isStale() {
                print("Baseline is stale, needs recalibration")
                needsCalibration = true
                self.baseline = nil
            } else {
                print("Baseline loaded successfully")
                self.baseline = baseline
                needsCalibration = false
            }
        } catch {
            print("Failed to load baseline: \(error)")
            needsCalibration = true
        }
    }

    func clearBaseline() {
        UserDefaults.standard.removeObject(forKey: baselineKey)
        baseline = nil
        needsCalibration = true
        print("Baseline cleared")
    }
}
