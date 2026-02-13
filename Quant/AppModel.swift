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
    @Published var poseConfidence: Float = 0.0
    @Published var poseKeypointCount: Int = 0
    @Published var missingCriticalJoints: String = ""
    @Published var latestSample: PoseSample?
    @Published var postureState: PostureState = .absent
    @Published var nudgeDecision: NudgeDecision = .none

    // MARK: - Calibration Properties

    @Published var calibrationStatus: CalibrationStatus = .waiting
    @Published var calibrationProgress: Float = 0
    @Published var baseline: Baseline?
    @Published var needsCalibration: Bool = true

    // MARK: - Audio Feedback

    /// The audio feedback service that plays a subtle tone when a nudge fires.
    ///
    /// Exposed as `private(set)` so the DebugOverlayView can read its state
    /// (e.g., last played time, total plays, enabled/disabled) but only
    /// AppModel can trigger playback.
    private(set) var audioService = AudioFeedbackService()

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

        pipeline.$poseConfidence
            .assign(to: &$poseConfidence)

        pipeline.$poseKeypointCount
            .assign(to: &$poseKeypointCount)

        pipeline.$missingCriticalJoints
            .assign(to: &$missingCriticalJoints)

        pipeline.$postureState
            .assign(to: &$postureState)

        pipeline.$nudgeDecision
            .assign(to: &$nudgeDecision)

        // React to nudge fire decisions — deliver feedback and record.
        //
        // When the NudgeEngine decides to fire, we:
        // 1. Play an audio cue via AudioFeedbackService (Ticket 4.2)
        // 2. Record the nudge so the NudgeEngine starts its cooldown timer
        //
        // The audio cue respects system volume and the mute switch (because
        // AudioFeedbackService uses the .ambient audio session category).
        // Watch haptic delivery will be added in Ticket 4.4.
        pipeline.$nudgeDecision
            .sink { [weak self] decision in
                guard let self = self else { return }
                if case .fire = decision {
                    // Play the audio feedback cue (subtle tone)
                    self.audioService.playNudgeCue()

                    // Record that the nudge was delivered so the NudgeEngine
                    // can start its cooldown timer and increment the hourly counter.
                    let now = Date().timeIntervalSince1970
                    self.pipeline.recordNudgeFired(at: now)
                    print("🔔 Nudge fired at \(now)")
                }
            }
            .store(in: &cancellables)

        // Detect acknowledgement: when posture transitions from .bad to .good,
        // tell the NudgeEngine the user responded to the nudge.
        // This is a simple version — Ticket 4.3 will add the full
        // acknowledgement window logic with timing.
        //
        // How this works:
        // `scan` keeps track of the previous state so we can detect transitions.
        // Each emission is a tuple of (previousState, currentState).
        // We then filter for `.bad → .good` transitions specifically.
        pipeline.$postureState
            .scan((PostureState.absent, PostureState.absent)) { previousPair, newState in
                // Shift: the "current" becomes the "previous", new value becomes "current"
                return (previousPair.1, newState)
            }
            .filter { oldState, newState in
                // Only react to .bad → .good transitions
                if case .good = newState, case .bad = oldState {
                    return true
                }
                return false
            }
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.pipeline.recordNudgeAcknowledgement()
                print("✅ Posture corrected — nudge acknowledged")
            }
            .store(in: &cancellables)

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
