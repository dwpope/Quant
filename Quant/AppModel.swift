import SwiftUI
import Combine
import AVFoundation
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
    @Published var latestMetrics: RawMetrics?
    @Published var postureState: PostureState = .absent
    @Published var nudgeDecision: NudgeDecision = .none

    // MARK: - Recording & Replay

    @Published private(set) var isRecording = false
    @Published private(set) var isReplaying = false

    // MARK: - Calibration Properties

    @Published var calibrationStatus: CalibrationStatus = .waiting
    @Published var calibrationProgress: Float = 0
    @Published var baseline: Baseline?
    @Published var needsCalibration: Bool = true

    // MARK: - Calibration Settings

    @Published var maxPositionVariance: Float {
        didSet {
            UserDefaults.standard.set(maxPositionVariance, forKey: Keys.maxPositionVariance)
            rebuildCalibrationEngine()
            syncSettingsToWatch()
        }
    }

    @Published var maxAngleVariance: Float {
        didSet {
            UserDefaults.standard.set(maxAngleVariance, forKey: Keys.maxAngleVariance)
            rebuildCalibrationEngine()
            syncSettingsToWatch()
        }
    }

    @Published var samplingDuration: Double {
        didSet {
            UserDefaults.standard.set(samplingDuration, forKey: Keys.samplingDuration)
            rebuildCalibrationEngine()
            syncSettingsToWatch()
        }
    }

    @Published var countdownDuration: Int {
        didSet {
            UserDefaults.standard.set(countdownDuration, forKey: Keys.countdownDuration)
            syncSettingsToWatch()
        }
    }

    // MARK: - Posture Threshold Settings

    @Published var forwardCreepThreshold: Float {
        didSet {
            UserDefaults.standard.set(forwardCreepThreshold, forKey: Keys.forwardCreepThreshold)
            updatePipelineThresholds()
        }
    }

    @Published var twistThreshold: Float {
        didSet {
            UserDefaults.standard.set(twistThreshold, forKey: Keys.twistThreshold)
            updatePipelineThresholds()
        }
    }

    @Published var sideLeanThreshold: Float {
        didSet {
            UserDefaults.standard.set(sideLeanThreshold, forKey: Keys.sideLeanThreshold)
            updatePipelineThresholds()
        }
    }

    @Published var driftingToBadThreshold: Double {
        didSet {
            UserDefaults.standard.set(driftingToBadThreshold, forKey: Keys.driftingToBadThreshold)
            updatePipelineThresholds()
        }
    }

    @Published var headDropThreshold: Float {
        didSet {
            UserDefaults.standard.set(headDropThreshold, forKey: Keys.headDropThreshold)
            updatePipelineThresholds()
        }
    }

    @Published var shoulderRoundingThreshold: Float {
        didSet {
            UserDefaults.standard.set(shoulderRoundingThreshold, forKey: Keys.shoulderRoundingThreshold)
            updatePipelineThresholds()
        }
    }

    @Published var slouchDurationBeforeNudge: Double {
        didSet {
            UserDefaults.standard.set(slouchDurationBeforeNudge, forKey: Keys.slouchDurationBeforeNudge)
            updatePipelineThresholds()
        }
    }

    @Published var nudgeCooldown: Double {
        didSet {
            UserDefaults.standard.set(nudgeCooldown, forKey: Keys.nudgeCooldown)
            updatePipelineThresholds()
        }
    }

    @Published var maxNudgesPerHour: Int {
        didSet {
            UserDefaults.standard.set(maxNudgesPerHour, forKey: Keys.maxNudgesPerHour)
            updatePipelineThresholds()
        }
    }

    // MARK: - Camera Mode

    @Published var cameraMode: CameraMode
    /// True when the front camera cannot start due to denied or restricted permission.
    /// The UI shows a permission-recovery screen when this is true and cameraMode is .front2D.
    @Published var frontCameraBlocked: Bool = false

    // MARK: - Camera Preview

    @Published var showCameraPreview: Bool = false

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
    @Published var selectedHaptic: String = "failure"

    // MARK: - Computed Properties

    /// Exposes the pipeline's current PostureThresholds for the debug overlay.
    var postureThresholds: PostureThresholds {
        pipeline.thresholds
    }

    // MARK: - Private Properties

    let arService = ARSessionService()
    let frontService = FrontCameraSessionService()
    private let switchableProvider = SwitchablePoseProvider()
    private lazy var pipeline: Pipeline = {
        Pipeline(provider: switchableProvider)
    }()
    private var cancellables = Set<AnyCancellable>()
    private let recorderService = RecorderService()
    private let replayService = ReplayService()
    private var calibrationEngine: CalibrationEngine
    private var lastNudgeFiredTime: TimeInterval?
    private var countdownTimer: Timer?
    private var countdownRemaining: Int = 0
    private var countdownCompleted: Bool = false

    private static let baselineKey = "com.quant.savedBaseline"

    private enum Keys {
        static let cameraMode = "com.quant.cameraMode"
        static let maxPositionVariance = "com.quant.cal.maxPositionVariance"
        static let maxAngleVariance = "com.quant.cal.maxAngleVariance"
        static let samplingDuration = "com.quant.cal.samplingDuration"
        static let countdownDuration = "com.quant.cal.countdownDuration"
        static let forwardCreepThreshold = "com.quant.posture.forwardCreep"
        static let twistThreshold = "com.quant.posture.twist"
        static let sideLeanThreshold = "com.quant.posture.sideLean"
        static let driftingToBadThreshold = "com.quant.posture.driftingToBad"
        static let headDropThreshold = "com.quant.posture.headDrop"
        static let shoulderRoundingThreshold = "com.quant.posture.shoulderRounding"
        static let slouchDurationBeforeNudge = "com.quant.posture.slouchDuration"
        static let nudgeCooldown = "com.quant.posture.nudgeCooldown"
        static let maxNudgesPerHour = "com.quant.posture.maxNudgesPerHour"
    }

    static let defaultMaxPositionVariance: Float = 0.06
    static let defaultMaxAngleVariance: Float = 6.0
    static let defaultSamplingDuration: Double = 5.0
    static let defaultCountdownDuration: Int = 3
    private static let defaultThresholds = PostureThresholds()
    static let defaultForwardCreepThreshold: Float = defaultThresholds.forwardCreepThreshold
    static let defaultTwistThreshold: Float = defaultThresholds.twistThreshold
    static let defaultSideLeanThreshold: Float = defaultThresholds.sideLeanThreshold
    static let defaultDriftingToBadThreshold: Double = defaultThresholds.driftingToBadThreshold
    static let defaultHeadDropThreshold: Float = defaultThresholds.headDropThreshold
    static let defaultShoulderRoundingThreshold: Float = defaultThresholds.shoulderRoundingThreshold
    static let defaultSlouchDurationBeforeNudge: Double = defaultThresholds.slouchDurationBeforeNudge
    static let defaultNudgeCooldown: Double = defaultThresholds.nudgeCooldown
    static let defaultMaxNudgesPerHour: Int = defaultThresholds.maxNudgesPerHour

    // MARK: - Initialization

    init() {
        let defaults = UserDefaults.standard

        // Load persisted camera mode (default: .rearDepth)
        if let raw = defaults.string(forKey: Keys.cameraMode),
           let saved = CameraMode(rawValue: raw) {
            self.cameraMode = saved
        } else {
            self.cameraMode = .rearDepth
        }

        let posVar = defaults.object(forKey: Keys.maxPositionVariance) as? Float ?? Self.defaultMaxPositionVariance
        let angVar = defaults.object(forKey: Keys.maxAngleVariance) as? Float ?? Self.defaultMaxAngleVariance
        let sampDur = defaults.object(forKey: Keys.samplingDuration) as? Double ?? Self.defaultSamplingDuration
        let countDur = defaults.object(forKey: Keys.countdownDuration) as? Int ?? Self.defaultCountdownDuration

        self.maxPositionVariance = posVar
        self.maxAngleVariance = angVar
        self.samplingDuration = sampDur
        self.countdownDuration = countDur

        self.forwardCreepThreshold = defaults.object(forKey: Keys.forwardCreepThreshold) as? Float ?? Self.defaultForwardCreepThreshold
        self.twistThreshold = defaults.object(forKey: Keys.twistThreshold) as? Float ?? Self.defaultTwistThreshold
        self.sideLeanThreshold = defaults.object(forKey: Keys.sideLeanThreshold) as? Float ?? Self.defaultSideLeanThreshold
        self.driftingToBadThreshold = defaults.object(forKey: Keys.driftingToBadThreshold) as? Double ?? Self.defaultDriftingToBadThreshold
        self.headDropThreshold = defaults.object(forKey: Keys.headDropThreshold) as? Float ?? Self.defaultHeadDropThreshold
        self.shoulderRoundingThreshold = defaults.object(forKey: Keys.shoulderRoundingThreshold) as? Float ?? Self.defaultShoulderRoundingThreshold
        self.slouchDurationBeforeNudge = defaults.object(forKey: Keys.slouchDurationBeforeNudge) as? Double ?? Self.defaultSlouchDurationBeforeNudge
        self.nudgeCooldown = defaults.object(forKey: Keys.nudgeCooldown) as? Double ?? Self.defaultNudgeCooldown
        self.maxNudgesPerHour = defaults.object(forKey: Keys.maxNudgesPerHour) as? Int ?? Self.defaultMaxNudgesPerHour

        let config = CalibrationConfig(
            samplingDuration: sampDur,
            maxPositionVariance: posVar,
            maxAngleVariance: angVar
        )
        self.calibrationEngine = CalibrationEngine(config: config)

        // Attach the persisted camera source to the switchable provider.
        // Pipeline is initialized once with switchableProvider and stays attached;
        // the actual camera source can be swapped at runtime via switchCameraMode().
        switchableProvider.attach(source: providerForMode(cameraMode))

        // Forward front camera permission status so the UI can show a
        // recovery screen when permission is denied or restricted.
        // Uses assign(to:) so the subscription is tied to this object's lifetime.
        frontService.$permissionStatus
            .map { $0 == .denied || $0 == .restricted }
            .receive(on: RunLoop.main)
            .assign(to: &$frontCameraBlocked)

        loadBaseline()
        setupPipeline()
        setupWatchSubscriptions()
        updatePipelineThresholds()
    }

    // MARK: - Pipeline Setup

    private func setupPipeline() {
        pipeline.$latestSample
            .assign(to: &$latestSample)

        pipeline.$latestMetrics
            .assign(to: &$latestMetrics)

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
                    self.watchService.sendNudge(hapticType: self.selectedHaptic)

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

    // MARK: - Watch Subscriptions

    private func setupWatchSubscriptions() {
        watchService.calibrationRequested
            .sink { [weak self] in
                self?.recalibrate()
            }
            .store(in: &cancellables)

        watchService.settingsReceived
            .sink { [weak self] settings in
                self?.applySettingsFromWatch(settings)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    func startMonitoring() async {
        do {
            try await activeService.start()
            print("\(cameraMode) session started successfully")
        } catch {
            print("Failed to start \(cameraMode) service: \(error)")
        }
    }

    func stopMonitoring() {
        activeService.stop()
        print("\(cameraMode) session stopped")
    }

    /// Switch to a different camera mode at runtime.
    ///
    /// This method:
    /// 1. Stops the currently active camera source
    /// 2. Detaches it from the switchable provider
    /// 3. Attaches the new source
    /// 4. Starts the new source
    /// 5. Triggers recalibration (baseline is camera-specific)
    /// 6. Persists the choice to UserDefaults
    func switchCameraMode(to mode: CameraMode) async {
        guard mode != cameraMode else { return }

        // Stop and detach current source
        activeService.stop()
        switchableProvider.detach()

        // Update mode
        cameraMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Keys.cameraMode)

        // Attach and start new source
        switchableProvider.attach(source: providerForMode(mode))
        do {
            try await activeService.start()
            print("Switched to \(mode) — session started")
        } catch {
            print("Failed to start \(mode) service: \(error)")
        }

        // Baseline from the previous camera is not valid for the new one —
        // shoulder positions and scale differ between rear and front views.
        recalibrate()
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
        UserDefaults.standard.removeObject(forKey: Self.baselineKey)
        needsCalibration = true
        startCalibration()
    }

    func sendTestNudge() {
        watchService.sendNudge(hapticType: selectedHaptic)
    }

    /// Re-attempt starting the front camera after the user grants permission in Settings.
    func retryFrontCamera() async {
        guard cameraMode == .front2D else { return }
        do {
            try await frontService.start()
        } catch {
            print("Failed to start front camera: \(error)")
        }
    }

    // MARK: - Recording Controls

    func startRecording() {
        let metadata = SessionMetadata(
            deviceModel: Self.deviceModelName(),
            depthAvailable: currentMode != .twoDOnly,
            thresholds: pipeline.thresholds
        )
        recorderService.startRecording(metadata: metadata)
        pipeline.recorder = recorderService
        isRecording = true
    }

    @discardableResult
    func stopRecording() -> URL? {
        pipeline.recorder = nil
        isRecording = false
        guard let session = recorderService.stopRecording() else { return nil }
        return exportSession(session)
    }

    // MARK: - Replay Controls

    func loadSession(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        let session = try JSONDecoder().decode(RecordedSession.self, from: data)
        replayService.load(session: session)
    }

    func startReplay() {
        let provider = ReplayPoseProvider(replayService: replayService)
        switchableProvider.attach(source: provider)
        isReplaying = true
        Task {
            try? await provider.start()
            // Playback finished naturally
            isReplaying = false
        }
    }

    func stopReplay() {
        replayService.stop()
        switchableProvider.detach()
        switchableProvider.attach(source: providerForMode(cameraMode))
        isReplaying = false
    }

    func resetCalibrationSettings() {
        maxPositionVariance = Self.defaultMaxPositionVariance
        maxAngleVariance = Self.defaultMaxAngleVariance
        samplingDuration = Self.defaultSamplingDuration
        countdownDuration = Self.defaultCountdownDuration
    }

    func resetPostureSettings() {
        forwardCreepThreshold = Self.defaultForwardCreepThreshold
        twistThreshold = Self.defaultTwistThreshold
        sideLeanThreshold = Self.defaultSideLeanThreshold
        driftingToBadThreshold = Self.defaultDriftingToBadThreshold
        headDropThreshold = Self.defaultHeadDropThreshold
        shoulderRoundingThreshold = Self.defaultShoulderRoundingThreshold
        slouchDurationBeforeNudge = Self.defaultSlouchDurationBeforeNudge
        nudgeCooldown = Self.defaultNudgeCooldown
        maxNudgesPerHour = Self.defaultMaxNudgesPerHour
        syncSettingsToWatch()
    }

    // MARK: - Private Methods

    /// Returns the PoseProvider for the given camera mode.
    private func providerForMode(_ mode: CameraMode) -> any PoseProvider {
        switch mode {
        case .rearDepth: return arService
        case .front2D: return frontService
        }
    }

    /// The currently active camera service, based on `cameraMode`.
    private var activeService: any PoseProvider {
        providerForMode(cameraMode)
    }

    private func exportSession(_ session: RecordedSession) -> URL? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else { return nil }
        let fileName = "posture-session-\(session.id.uuidString.prefix(8)).json"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            print("Failed to export session: \(error)")
            return nil
        }
    }

    private static func deviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? "Unknown"
            }
        }
    }

    private func rebuildCalibrationEngine() {
        let config = CalibrationConfig(
            samplingDuration: samplingDuration,
            maxPositionVariance: maxPositionVariance,
            maxAngleVariance: maxAngleVariance
        )
        calibrationEngine = CalibrationEngine(config: config)
    }

    private func updatePipelineThresholds() {
        var t = pipeline.thresholds
        t.forwardCreepThreshold = forwardCreepThreshold
        t.twistThreshold = twistThreshold
        t.sideLeanThreshold = sideLeanThreshold
        t.driftingToBadThreshold = driftingToBadThreshold
        t.headDropThreshold = headDropThreshold
        t.shoulderRoundingThreshold = shoulderRoundingThreshold
        t.slouchDurationBeforeNudge = slouchDurationBeforeNudge
        t.nudgeCooldown = nudgeCooldown
        t.maxNudgesPerHour = maxNudgesPerHour
        pipeline.thresholds = t
    }

    func syncSettingsToWatch() {
        let settings: [String: Any] = [
            Keys.maxPositionVariance: maxPositionVariance,
            Keys.maxAngleVariance: maxAngleVariance,
            Keys.samplingDuration: samplingDuration,
            Keys.countdownDuration: countdownDuration,
            Keys.forwardCreepThreshold: forwardCreepThreshold,
            Keys.twistThreshold: twistThreshold,
            Keys.sideLeanThreshold: sideLeanThreshold,
            Keys.driftingToBadThreshold: driftingToBadThreshold
        ]
        watchService.sendSettings(settings)
    }

    private func applySettingsFromWatch(_ settings: [String: Any]) {
        if let val = settings[Keys.maxPositionVariance] as? Float {
            maxPositionVariance = val
        }
        if let val = settings[Keys.maxAngleVariance] as? Float {
            maxAngleVariance = val
        }
        if let val = settings[Keys.samplingDuration] as? Double {
            samplingDuration = val
        }
        if let val = settings[Keys.countdownDuration] as? Int {
            countdownDuration = val
        }
        if let val = settings[Keys.forwardCreepThreshold] as? Float {
            forwardCreepThreshold = val
        }
        if let val = settings[Keys.twistThreshold] as? Float {
            twistThreshold = val
        }
        if let val = settings[Keys.sideLeanThreshold] as? Float {
            sideLeanThreshold = val
        }
        if let val = settings[Keys.driftingToBadThreshold] as? Double {
            driftingToBadThreshold = val
        }
    }

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
