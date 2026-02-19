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

    // MARK: - Watch Connectivity

    /// The Watch connectivity service that sends nudge events to the Apple Watch.
    ///
    /// Exposed as `private(set)` so the DebugOverlayView can read its state
    /// (e.g., paired, reachable, send count) but only AppModel can trigger sends.
    private(set) var watchService = WatchConnectivityService()

    /// The haptic type to use when sending a test nudge to the Watch.
    @Published var selectedHaptic: String = "notification"

    // MARK: - Private Properties

    private let arService = ARSessionService()
    private lazy var pipeline: Pipeline = {
        Pipeline(provider: arService)
    }()
    private var cancellables = Set<AnyCancellable>()
    private let calibrationEngine = CalibrationEngine()
    private var lastNudgeFiredTime: TimeInterval?
    private var countdownTimer: Timer?
    private var countdownRemaining: Int = 0
    private let countdownDuration: Int = 3
    private var countdownCompleted: Bool = false

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
        // 2. Send a haptic nudge to Apple Watch via WatchConnectivityService (Ticket 4.4)
        // 3. Record the nudge so the NudgeEngine starts its cooldown timer
        //
        // The audio cue respects system volume and the mute switch (because
        // AudioFeedbackService uses the .ambient audio session category).
        // The Watch haptic is delivered via WCSession sendMessage for <2s latency.
        pipeline.$nudgeDecision
            .sink { [weak self] decision in
                guard let self = self else { return }
                if case .fire = decision {
                    // Play the audio feedback cue (subtle tone)
                    self.audioService.playNudgeCue()

                    // Send haptic nudge to Apple Watch
                    self.watchService.sendNudge()

                    // Record that the nudge was delivered so the NudgeEngine
                    // can start its cooldown timer and increment the hourly counter.
                    let now = Date().timeIntervalSince1970
                    self.pipeline.recordNudgeFired(at: now)
                    self.lastNudgeFiredTime = now
                    print("🔔 Nudge fired at \(now)")
                }
            }
            .store(in: &cancellables)

        // Detect acknowledgement: when posture transitions from .bad to .good
        // within the acknowledgement window after a nudge fired, tell the
        // NudgeEngine the user responded to the nudge.
        //
        // `scan` keeps track of the previous state so we can detect transitions.
        // Each emission is a tuple of (previousState, currentState).
        // We filter for `.bad → .good` transitions, then check timing.
        pipeline.$postureState
            .scan((PostureState.absent, PostureState.absent)) { previousPair, newState in
                return (previousPair.1, newState)
            }
            .filter { oldState, newState in
                if case .good = newState, case .bad = oldState {
                    return true
                }
                return false
            }
            .sink { [weak self] _ in
                guard let self = self else { return }
                let now = Date().timeIntervalSince1970

                guard let nudgeTime = self.lastNudgeFiredTime else {
                    print("Posture corrected — no recent nudge to acknowledge")
                    return
                }

                let elapsed = now - nudgeTime
                if elapsed <= self.pipeline.thresholds.acknowledgementWindow {
                    self.pipeline.recordNudgeAcknowledgement()
                    self.lastNudgeFiredTime = nil
                    print("✅ Posture corrected — nudge acknowledged (\(String(format: "%.0f", elapsed))s after nudge)")
                } else {
                    print("Posture corrected — outside acknowledgement window (\(String(format: "%.0f", elapsed))s after nudge)")
                }
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
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownCompleted = false
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

    func sendTestNudge() {
        watchService.sendNudge(hapticType: selectedHaptic)
    }

    // MARK: - Private Methods

    private func feedCalibration(_ sample: PoseSample) {
        guard needsCalibration else { return }

        // While waiting, detect good tracking and start countdown
        if case .waiting = calibrationStatus, !countdownCompleted {
            guard sample.trackingQuality >= .good else { return }
            startCountdown()
            return
        }

        // During countdown, don't feed samples to the engine
        if case .countdown = calibrationStatus {
            // If tracking drops during countdown, cancel and go back to waiting
            if sample.trackingQuality < .good {
                countdownTimer?.invalidate()
                countdownTimer = nil
                countdownCompleted = false
                calibrationStatus = .waiting
            }
            return
        }

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

    private func startCountdown() {
        countdownRemaining = countdownDuration
        calibrationStatus = .countdown(countdownRemaining)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                self.countdownRemaining -= 1
                if self.countdownRemaining > 0 {
                    self.calibrationStatus = .countdown(self.countdownRemaining)
                } else {
                    timer.invalidate()
                    self.countdownTimer = nil
                    self.countdownCompleted = true
                    // Countdown finished — engine is in .waiting state,
                    // so the next good sample will start sampling
                    self.calibrationStatus = .waiting
                }
            }
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
