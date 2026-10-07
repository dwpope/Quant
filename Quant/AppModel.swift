import SwiftUI
import Combine
import AVFoundation
import PostureLogic

@MainActor
class AppModel: ObservableObject {
    // Teardown only releases stored properties; it touches no main-actor state.
    // Marking it `nonisolated` keeps Swift's MainActor isolated-deinit
    // back-deploy shim out of XCTest's NSInvocation-driven dealloc path, which
    // otherwise corrupts the heap and aborts under Xcode 26 / iOS 26.
    nonisolated deinit {}

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
    @Published var thermalLevel: ThermalLevel = .nominal

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

    /// Whether the rear camera can run, for the recovery screen. Follows `arService`.
    @Published var rearCameraStatus: RearCameraStatus = .ok

    // MARK: - Camera Preview

    @Published var showCameraPreview: Bool = false

    // MARK: - Audio Feedback

    /// The audio feedback service that plays a subtle tone when a nudge fires.
    ///
    /// Exposed as `private(set)` so the DebugOverlayView can read its state
    /// (e.g., last played time, total plays, enabled/disabled) but only
    /// AppModel can trigger playback.
    private(set) var audioService = AudioFeedbackService()

    // MARK: - Hydration

    /// The sip detection engine. Subscribes to `poseObservationPublisher`
    /// independently — Pipeline does not know it exists.
    let sipDetector = SipDetector()

    /// Persists and exposes today's confirmed sip events.
    let sipStore = SipStore()

    /// Records raw sip data for personalised threshold calibration.
    let sipCalibrationCapture = SipCalibrationCapture()

    // MARK: - Training Mode

    /// When true, each confirmed sip:
    ///   - captures a `SipTrainingRecord` (scores + 3s pose buffer) into `sipTrainingStore`
    ///   - enqueues a label popup so the user can classify the event
    ///
    /// Backed by UserDefaults so the toggle persists across launches.
    @Published var isTrainingModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isTrainingModeEnabled, forKey: Keys.isTrainingModeEnabled)
            if !isTrainingModeEnabled {
                sipTrainingBuffer.reset()
                labelQueue.drainAsUnconfirmed()
            }
        }
    }

    /// Rolling ~3-second pose buffer fed by the same observation publisher
    /// as `SipDetector`. Snapshotted at confirmation time to build training records.
    let sipTrainingBuffer = SipTrainingBuffer()

    /// Sidecar persistence for `SipTrainingRecord`s captured in training mode.
    let sipTrainingStore = SipTrainingStore()

    /// The label popup currently shown to the user. `nil` when no popup is
    /// pending. Driven by `labelQueue`.
    @Published private(set) var activeSipLabelItem: PendingSipLabel?

    private let labelQueue = SipLabelQueue()

    /// True during the 5-second countdown before capture begins.
    @Published var sipCalibrationCountingDown = false

    /// Seconds remaining in the countdown (5…1).
    @Published var sipCalibrationCountdown: Int = 0

    /// True while a 10-second sip capture window is active.
    @Published var sipCalibrationActive = false

    /// Progress (0–1) through the current 10-second capture window.
    @Published var sipCalibrationProgress: Double = 0

    private var sipCalibrationTimer: Timer?
    private var sipCalibrationStartTime: Date?

    // MARK: - Watch Connectivity

    /// The Watch connectivity service that sends nudge events to the Apple Watch.
    ///
    /// Exposed as `private(set)` so the DebugOverlayView can read its state
    /// (e.g., paired, reachable, send count) but only AppModel can trigger sends.
    private(set) var watchService = WatchConnectivityService()

    // MARK: - Computed Properties

    /// Exposes the pipeline's current PostureThresholds for the debug overlay.
    var postureThresholds: PostureThresholds {
        pipeline.thresholds
    }

    // MARK: - Private Properties

    let arService = ARSessionService()
    let frontService = FrontCameraSessionService()
    let arFaceService = ARFaceTrackingService()
    private let switchableProvider = SwitchablePoseProvider()
    private let thermalMonitor = ThermalMonitor()
    private lazy var pipeline: Pipeline = {
        Pipeline(provider: switchableProvider, thermalMonitor: thermalMonitor)
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

    /// Delay between tearing down one camera session and starting the next, so the
    /// hardware is released first (see `switchCameraMode`). Device-tunable starting
    /// value; raise if a mode switch ever stalls the incoming session.
    private let cameraReleaseSettleMs = 250

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
        /// `.v2` since 2026-10-05, when head drop started counting the way it reads on the device
        /// (negative, 0.015 default). A value stored under the old meaning (+0.15) would silence it.
        static let headDropThreshold = "com.quant.posture.headDrop.v2"
        static let shoulderRoundingThreshold = "com.quant.posture.shoulderRounding"
        static let slouchDurationBeforeNudge = "com.quant.posture.slouchDuration"
        static let nudgeCooldown = "com.quant.posture.nudgeCooldown"
        /// `.v2` since 2026-10-05, when the default became 0 (no hourly cap): a 2 stored under
        /// the old key was only ever the old default, and would otherwise keep the cap on.
        static let maxNudgesPerHour = "com.quant.posture.maxNudgesPerHour.v2"
        static let nudgesSilencedUntil = "com.quant.nudges.silencedUntil"
        static let isTrainingModeEnabled = "com.quant.training.enabled"
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

        // Load persisted camera mode. Compute into a local so the unsupported-device
        // coercion runs before `self.cameraMode` is assigned (Swift forbids reading a
        // stored property mid-init). An explicit persisted choice always wins; with
        // none saved, default to .frontFace on TrueDepth-capable devices (the
        // decoupled ARFaceAnchor head source is the figure's most accurate path),
        // else .rearDepth. A persisted .frontFace on a device without TrueDepth face
        // tracking would crash session.run, so coerce it to the 2D front path.
        var initialMode: CameraMode
        if let raw = defaults.string(forKey: Keys.cameraMode),
           let saved = CameraMode(rawValue: raw) {
            initialMode = saved
        } else {
            initialMode = ARFaceTrackingService.isFaceTrackingSupported ? .frontFace : .rearDepth
        }
        if initialMode == .frontFace && !ARFaceTrackingService.isFaceTrackingSupported {
            initialMode = .front2D
        }
        self.cameraMode = initialMode

        // In .frontFace the head source is ARKit's decoupled ARFaceAnchor, so the
        // viz turn↓tilt fade (which only existed to cancel the old 2D phantom nod)
        // is switched off — otherwise it flattens a real head-circle into an oval.
        PostureVisualizationBinding.faceTrackingActive = (initialMode == .frontFace)

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

        self.isTrainingModeEnabled = defaults.bool(forKey: Keys.isTrainingModeEnabled)

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

        // The rear camera's equivalent, so a failure shows a screen instead of only logs.
        arService.statusPublisher
            .receive(on: RunLoop.main)
            .assign(to: &$rearCameraStatus)

        loadBaseline()
        setupPipeline()
        loadNudgeSilence()
        loadSipThresholds()
        setupWatchSubscriptions()
        updatePipelineThresholds()
        setupLabelQueue()
    }

    // MARK: - Silencing nudges

    /// How long nudges can be silenced for, from the phone or the Watch.
    static let silenceOptionsMinutes = [30, 60, 120]

    /// Nudges are held back until then, or nil. Set from the phone or the Watch; kept across
    /// launches. On the calendar clock, which the pipeline compares with the calendar clock.
    @Published private(set) var nudgesSilencedUntil: Date?

    /// What the pipeline is holding nudges back until. For the tests and the diagnostics panel.
    var pipelineNudgesSilencedUntil: Date? { pipeline.nudgesSilencedUntil }

    func silenceNudges(forMinutes minutes: Int, now: Date = Date()) {
        setNudgeSilence(until: now.addingTimeInterval(TimeInterval(minutes) * 60))
    }

    func resumeNudges() {
        setNudgeSilence(until: nil)
    }

    /// The Watch's request: minutes to silence for, 0 to resume.
    func handleSilenceRequest(minutes: Int) {
        if minutes > 0 { silenceNudges(forMinutes: minutes) } else { resumeNudges() }
    }

    private func setNudgeSilence(until: Date?) {
        nudgesSilencedUntil = until
        pipeline.nudgesSilencedUntil = until
        if let until {
            UserDefaults.standard.set(until.timeIntervalSince1970, forKey: Keys.nudgesSilencedUntil)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.nudgesSilencedUntil)
        }
        watchService.sendNudgeSilence(until: until)
    }

    /// A silence still running when the app was quit carries on; one that has ended is dropped.
    private func loadNudgeSilence() {
        let stored = UserDefaults.standard.object(forKey: Keys.nudgesSilencedUntil) as? Double
        guard let stored, stored > Date().timeIntervalSince1970 else {
            UserDefaults.standard.removeObject(forKey: Keys.nudgesSilencedUntil)
            return
        }
        let until = Date(timeIntervalSince1970: stored)
        nudgesSilencedUntil = until
        pipeline.nudgesSilencedUntil = until
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

        pipeline.$thermalLevel
            .assign(to: &$thermalLevel)

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
                if case .fire(let reason) = decision {
                    // Play the audio feedback cue (subtle tone)
                    self.audioService.playNudgeCue()

                    // Send haptic nudge to Apple Watch, with what to do about it
                    self.watchService.sendNudge(body: reason.coachingMessage)

                    // Record that the nudge was delivered so the NudgeEngine
                    // can start its cooldown timer and increment the hourly counter.
                    // The pipeline records it on its own frame clock. This used to pass
                    // the calendar clock, and the cooldown then never ended.
                    self.pipeline.recordNudgeFired()
                    // Calendar clock, compared only with the calendar clock below.
                    let now = Date().timeIntervalSince1970
                    self.lastNudgeFiredTime = now
                    print("🔔 Nudge fired at \(now)")
                }
            }
            .store(in: &cancellables)

        // The posture log: one line per change, checked once per frame (the nudge decision is
        // published every frame, after the posture state and metrics it was decided from).
        pipeline.$nudgeDecision
            .sink { [weak self] decision in
                guard let self else { return }
                let events = self.postureLogRecorder.events(
                    state: self.pipeline.postureState, decision: decision,
                    taskMode: self.pipeline.taskMode, metrics: self.pipeline.latestMetrics,
                    headYaw: self.pipeline.latestSample.map { $0.headYaw - (self.baseline?.headYaw ?? 0) },
                    now: Date())
                self.postureLogStore.append(events)
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

        // Feed pose observations into SipCalibrationCapture when active.
        pipeline.poseObservationPublisher
            .sink { [weak self] observation in
                guard let self = self, self.sipCalibrationActive else { return }
                self.sipCalibrationCapture.process(observation)
            }
            .store(in: &cancellables)

        // Feed pose observations into SipDetector independently.
        // Pipeline doesn't know SipDetector exists — it just emits observations
        // and SipDetector subscribes like any other consumer.
        pipeline.poseObservationPublisher
            .sink { [weak self] observation in
                self?.sipDetector.process(observation)
            }
            .store(in: &cancellables)

        // Feed pose observations into SipTrainingBuffer when training mode is on.
        // The buffer accumulates a ~3s rolling window so the snapshot grabbed
        // on sip confirmation contains real pre-event pose history.
        pipeline.poseObservationPublisher
            .sink { [weak self] observation in
                guard let self = self, self.isTrainingModeEnabled else { return }
                self.sipTrainingBuffer.process(observation)
            }
            .store(in: &cancellables)

        // When a sip is confirmed: always persist to SipStore, and when
        // training mode is on also capture a sidecar record + enqueue a label.
        sipDetector.onSipConfirmed = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.sipStore.add(event)

                guard self.isTrainingModeEnabled else { return }

                let record = SipTrainingRecord(
                    id: event.id,
                    capturedAt: Date().timeIntervalSince1970,
                    scores: self.sipDetector.scoresSnapshot,
                    thresholds: self.sipDetector.thresholds,
                    bufferFrames: self.sipTrainingBuffer.snapshot()
                )
                self.sipTrainingStore.save(record)
                self.labelQueue.enqueue(
                    PendingSipLabel(event: event, scores: self.sipDetector.scoresSnapshot)
                )
            }
        }
    }

    // MARK: - Label Queue Setup

    private func setupLabelQueue() {
        // Mirror queue state onto the published property so SwiftUI can drive the popup.
        labelQueue.onActiveItemChanged = { [weak self] item in
            self?.activeSipLabelItem = item
        }
        // Forward confirmed labels to SipStore.
        labelQueue.onLabel = { [weak self] id, label in
            self?.sipStore.setLabel(id: id, label: label)
        }
        // Drain the queue whenever the app enters the background so no event
        // is left awaiting review while the process is suspended or terminated.
        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.labelQueue.drainAsUnconfirmed()
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

        // Silencing nudges from the Watch, and telling it when a silence ends.
        watchService.silenceRequested
            .sink { [weak self] minutes in self?.handleSilenceRequest(minutes: minutes) }
            .store(in: &cancellables)

        watchService.reachabilityChanged
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else { return }
                self.watchService.sendNudgeSilence(until: self.nudgesSilencedUntil)
            }
            .store(in: &cancellables)

        // The Watch as a remote for Jev captures. See `JevRemote`.
        watchService.jevRemoteCommand
            .sink { [weak self] command in
                Task { @MainActor [weak self] in await self?.handleJevRemote(command) }
            }
            .store(in: &cancellables)

        watchService.reachabilityChanged
            .filter { $0 }
            .sink { [weak self] _ in self?.pushJevStatusToWatch(force: true) }
            .store(in: &cancellables)

        // Tracking and the thresholds' state change on their own while someone is getting into
        // position, so the status is re-checked once a second and sent only when it changed.
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.pushJevStatusToWatch(force: false) }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    func startMonitoring() async {
        UIApplication.shared.isIdleTimerDisabled = true
        do {
            try await activeService.start()
            print("\(cameraMode) session started successfully")
        } catch {
            print("Failed to start \(cameraMode) service: \(error)")
        }
    }

    func stopMonitoring() {
        activeService.stop()
        UIApplication.shared.isIdleTimerDisabled = false
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

        // Never switch into face tracking on hardware that can't run it.
        guard mode != .frontFace || ARFaceTrackingService.isFaceTrackingSupported else {
            print("Ignoring switch to .frontFace — device lacks TrueDepth face tracking")
            return
        }

        // Capture the previous service before changing the mode
        let previousService = activeService

        // Update mode and persist immediately so the UI reflects the change right away
        cameraMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Keys.cameraMode)

        // Gate the viz turn↓tilt fade on the head source: off for ARKit-decoupled
        // .frontFace (round circle), the device-tuned legacy value otherwise.
        PostureVisualizationBinding.faceTrackingActive = (mode == .frontFace)

        // Yield so SwiftUI can update the picker before heavy camera work begins
        await Task.yield()

        // Stop and detach previous source
        previousService.stop()
        switchableProvider.detach()

        // Let the outgoing capture session actually release the camera before the new
        // one runs. ARKit/AVCapture `pause()`/`stopRunning()` return before the
        // hardware is freed, and .frontFace, .front2D and .rearDepth all contend for a
        // shared camera — starting the next session too eagerly stalls it (the
        // mode-switch camera war). This settle is timing-based; tune on device.
        try? await Task.sleep(for: .milliseconds(cameraReleaseSettleMs))

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

    /// Restart the rear camera from its recovery screen.
    func retryRearCamera() async {
        guard cameraMode == .rearDepth else { return }
        arService.stop()
        do {
            try await arService.start()
        } catch {
            print("Failed to restart rear camera: \(error)")
        }
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

    // MARK: - Training Mode Actions

    /// Applies a label chosen by the user in the confirmation popup.
    /// Forwards to `SipLabelQueue`, which fires `onLabel` → `SipStore.setLabel`.
    func applyLabel(_ label: SipEvent.Label, toSipID id: UUID) {
        labelQueue.applyLabel(label, toID: id)
    }

    /// Dismisses the active label popup without a user choice. The event
    /// is written as `.unconfirmed` so it doesn't block the queue.
    func dismissLabelAsUnconfirmed(id: UUID) {
        labelQueue.applyLabel(.unconfirmed, toID: id)
    }

    // MARK: - Recording Controls

    func startRecording() {
        let metadata = SessionMetadata(
            deviceModel: Self.deviceModelName(),
            depthAvailable: currentMode != .twoDOnly,
            thresholds: pipeline.thresholds,
            // Captured here or never: RawMetrics are all baseline-relative deltas, so without
            // the baseline that was live at record time the session cannot be replayed against
            // the threshold engine. The live baseline is cleared on recalibration and goes
            // stale after an hour, so it is unrecoverable after the fact.
            baseline: baseline
        )
        recorderService.startRecording(metadata: metadata)
        pipeline.recorder = recorderService
        isRecording = true
    }

    /// Attaches a human posture label to the session in progress.
    ///
    /// Stamped with the most recent recorded sample's timestamp, so the tag sits on the same
    /// clock as the samples it annotates (the camera frame clock). Stamping with `Date()`
    /// would put it on wall-clock and make it uncomparable to the sample stream.
    ///
    /// No-op when not recording, matching `RecorderService.addTag`.
    func tagCurrentSession(_ label: TagLabel) {
        guard isRecording else { return }
        recorderService.addTag(Tag(
            timestamp: recorderService.lastSampleTimestamp ?? 0,
            label: label,
            source: .manual
        ))
    }

    // MARK: - Jev classification (opt-in experiment, off by default, step 3b)
    //
    // This SHIPS — it is reachable in TestFlight, deliberately, so the experiment can be run on a
    // device remotely. It was `#if DEBUG` until 2026-09-24; that gate is gone, so read the
    // following as the current invariant rather than a historical note.
    //
    // WHAT PROTECTS THE USER NOW IS ONE BOOLEAN. `useJevClassifier` defaults to false and nothing
    // is sent until someone turns it on in the debug HUD. When it is on, a call sends nine
    // derived numbers plus tracking quality — no imagery — to a Cloudflare Worker, which forwards
    // to TypeSafe in the United States, where retention is open-ended. The threshold engine
    // remains the shipping classifier either way; Jev never drives a nudge.
    //
    // Because that default is the entire privacy boundary, it is pinned by a test
    // (QuantTests/JevPacingTests.test_useJevClassifier_shipsOff). Do not change it without
    // changing the README's privacy section in the same commit.
    //
    // The app still holds no credential: the Worker adds the TypeSafe bearer token. That is why
    // there is no key, no keychain and no xcconfig anywhere in this file — and why shipping this
    // path exposes an endpoint URL but never a secret.

    /// Opt-in from the debug HUD. Ships false, and that default is the only thing preventing
    /// posture data from leaving the device.
    @Published var useJevClassifier = false

    @Published private(set) var latestJevVerdict: JevVerdict?
    @Published private(set) var latestJevError: String?

    /// When the verdict above was produced. Surfaced because a call takes 130-475ms and runs on
    /// an interval, so the HUD is always showing a Jev verdict computed from an older frame than
    /// the threshold verdict beside it. Without this the two look simultaneous and are not.
    @Published private(set) var latestJevVerdictAt: Date?

    /// Step 3c's dataset.
    let jevComparisonStore = JevComparisonStore()

    /// One line per change in posture state, nudge decision and task mode, for reading back a
    /// real-use hour (2026-10-07). Local; it leaves the phone only through its export.
    let postureLogStore = PostureLogStore()
    private var postureLogRecorder = PostureLogRecorder()

    /// Minimum seconds between calls. Never per frame: 130ms p50 near the provider, 475ms p50
    /// and 715ms p99 from Europe via a gateway.
    var jevMinInterval: TimeInterval = 5

    private var lastJevAttemptAt: Date?

    static let jevProxyEndpoint = URL(string: "https://jev-proxy.quantaware.workers.dev/classify")!

    /// How Jev calls leave the app. Swappable so tests never reach the network. Read once, when
    /// the first classification builds the client.
    var jevTransport: JevTransport = URLSessionJevTransport()

    private lazy var jevClient = JevClient(
        endpoint: Self.jevProxyEndpoint,
        transport: jevTransport
    )

    /// Seconds between a Watch tap and the capture. In the first device session every Watch
    /// capture had the head turned and tipped down: the glance at the wrist was being recorded.
    /// Three seconds is enough to lower the wrist and look back at the screen.
    var jevRemoteCaptureDelay: TimeInterval = 3

    /// Whether a classification can happen now, and if not, why not.
    ///
    /// This returns a *reason* rather than a bare `nil` because "Classify now" silently doing
    /// nothing is indistinguishable from a broken button — which is how it was first reported
    /// from a device. Each refusal is established from the pipeline, not assumed:
    /// the flag is off; there is no baseline (metrics are all-zero rather than nil before
    /// calibration, so optionality cannot be the gate); the sample is nil while metrics keep a
    /// stale value, which would pair fresh numbers with an old pose; the interval has not
    /// elapsed; or a value is non-finite and the proxy would 400.
    ///
    /// **Pure.** Marking the attempt belongs to whoever actually makes it — the HUD renders this
    /// on every redraw, and a query that mutated would reset the interval continuously.
    func jevGate(now: Date = Date()) -> JevGate {
        guard useJevClassifier else { return .disabled }
        guard let baseline else { return .notCalibrated }
        guard let sample = latestSample, let metrics = latestMetrics else { return .noPose }

        let elapsed = now.timeIntervalSince(lastJevAttemptAt ?? .distantPast)
        if elapsed < jevMinInterval {
            return .tooSoon(secondsRemaining: (jevMinInterval - elapsed).rounded())
        }

        guard let features = JevFeatures.make(sample: sample, metrics: metrics, baseline: baseline)
        else { return .unusableValues }

        return .ready(features)
    }

    /// The payload to send now, or `nil` if a classification should not happen.
    ///
    /// Unlike ``jevGate(now:)`` this MARKS the attempt, so the interval holds even if the call
    /// that follows fails.
    func jevPayloadIfDue(now: Date = Date()) -> JevFeatures? {
        guard case .ready(let features) = jevGate(now: now) else { return nil }
        lastJevAttemptAt = now
        return features
    }

    /// Classifies once, if due, and records the result either way.
    func classifyWithJevIfDue(now: Date = Date()) async {
        jevAttempts += 1
        let gate = jevGate(now: now)
        guard case .ready(let features) = gate else {
            // Surface the refusal instead of leaving the last state on screen. A tap that does
            // nothing and says nothing is a bug report waiting to happen.
            latestJevError = gate.message
            return
        }
        lastJevAttemptAt = now
        // Taken with the features, before the call: the answer arrives up to half a second later,
        // and the thresholds' state from then isn't the one that goes with this pose.
        let atPose = JevCaptureContext(thresholdState: postureState,
                                       thresholds: pipeline.thresholds,
                                       taskMode: pipeline.taskMode,
                                       shoulderSink: latestMetrics?.shoulderSink)
        do {
            let verdict = try await jevClient.classify(features)
            recordJevComparison(features: features, verdict: verdict, error: nil, atPose: atPose)
        } catch {
            recordJevComparison(features: features, verdict: nil, error: String(describing: error),
                                atPose: atPose)
        }
    }

    // MARK: Jev remote (Apple Watch)

    /// The last status sent to the Watch, so an unchanged one is not sent again every second.
    private var lastJevStatusSent: JevRemote.Status?

    /// Every call to ``classifyWithJevIfDue(now:)``, refused or not. See `JevRemote.Status.attempts`.
    private(set) var jevAttempts = 0

    /// What the Watch shows. Pure.
    func jevRemoteStatus() -> JevRemote.Status {
        let thr = JevRemote.stateName(postureState).0
        // The state's own start is a frame timestamp. Frames are on the calendar clock since
        // 2026-10-05 (FrameClock), but a replayed recording may not be, so measure the elapsed
        // time on the frame clock and count back from now. Whole seconds, so a once-a-second status doesn't
        // differ every time only by frame jitter.
        let since = DriftClock.wallClockStart(postureState, frameNow: latestMetrics?.timestamp)
            .map { $0.timeIntervalSince1970.rounded() }
        let store = jevComparisonStore
        let record = store.comparisons.last.map { r in
            JevRemote.Status.Record(
                id: r.id,
                jevClass: r.jev?.posture,
                jevConfidence: r.jev?.confidence,
                thresholdStateAtCapture: JevRemote.stateName(r.thresholdState).0,
                capturedAt: r.capturedAt.timeIntervalSince1970,
                judged: r.userVerdict?.rawValue,
                discarded: r.isDiscarded)
        }
        return JevRemote.Status(
            enabled: useJevClassifier,
            calibrated: !needsCalibration,
            tracking: trackingQuality.rawValue,
            thresholdState: thr,
            thresholdSince: since,
            notice: latestJevError,
            lastRecord: record,
            judgedCount: store.adjudicatedCount,
            total: store.comparisons.count,
            trueClassOptions: JevClass.allCases.map(\.rawValue),
            attempts: jevAttempts,
            captureDelay: jevRemoteCaptureDelay,
            headTurnedSince: pipeline.headTurnedSince.flatMap {
                DriftClock.wallClock(of: $0, frameNow: latestMetrics?.timestamp)
            }.map { $0.timeIntervalSince1970.rounded() })
    }

    /// Acts on a request from the Watch, then reports back.
    ///
    /// A classify goes through the same gate as the on-screen button, so the Watch can't do
    /// anything the button couldn't, including switching the classifier on.
    func handleJevRemote(_ command: JevRemote.Command) async {
        switch command {
        case .classify:
            // Wait for the wrist to go down and the eyes to come back to the screen, unless the
            // answer is a refusal that waiting can't change.
            switch jevGate() {
            case .disabled, .notCalibrated:
                break
            default:
                if jevRemoteCaptureDelay > 0 {
                    try? await Task.sleep(for: .seconds(jevRemoteCaptureDelay))
                }
            }
            await classifyWithJevIfDue()
        case .judge(let id, let verdict, let trueClass):
            jevComparisonStore.setUserVerdict(id: id, verdict: verdict, trueClass: trueClass)
        case .discard(let id):
            jevComparisonStore.setDiscarded(id: id)
        case .statusRequest:
            break
        }
        pushJevStatusToWatch(force: true)
    }

    /// Sends the status if the Watch app is open and the status changed, or always if forced.
    private func pushJevStatusToWatch(force: Bool) {
        guard watchService.isReachable else { return }
        let status = jevRemoteStatus()
        guard force || status != lastJevStatusSent else { return }
        lastJevStatusSent = status
        watchService.sendJevStatus(status)
    }

    /// Stores the comparison and publishes the latest verdict.
    ///
    /// A failure is recorded too: that Jev was unavailable at a moment the thresholds had an
    /// opinion is itself a data point about whether this is worth shipping.
    /// `atPose` is what the thresholds were doing when the features were taken. Nil means "now",
    /// for callers that record at the moment of the pose.
    func recordJevComparison(features: JevFeatures, verdict: JevVerdict?, error: String?,
                             atPose: JevCaptureContext? = nil) {
        let context = atPose ?? JevCaptureContext(thresholdState: postureState,
                                                  thresholds: pipeline.thresholds,
                                                  taskMode: pipeline.taskMode,
                                                  shoulderSink: latestMetrics?.shoulderSink)
        latestJevVerdict = verdict
        latestJevError = error
        latestJevVerdictAt = Date()
        jevComparisonStore.add(JevComparisonRecord(
            id: UUID(),
            capturedAt: Date(),
            features: features,
            baseline: baseline ?? Baseline(
                timestamp: Date(), shoulderMidpoint: .zero, headPosition: .zero,
                torsoAngle: 0, shoulderWidth: 0, depthAvailable: false),
            thresholdState: context.thresholdState,
            thresholds: context.thresholds,
            taskMode: context.taskMode,
            jev: verdict,
            jevError: error,
            shoulderSink: context.shoulderSink
        ))
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

    // MARK: - Sip Calibration

    /// Starts a 5-second countdown, then a 10-second sip capture window.
    func beginSipCalibrationCapture() {
        sipCalibrationCountingDown = true
        sipCalibrationCountdown = 5

        sipCalibrationTimer?.invalidate()
        let countdownStart = Date()
        sipCalibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self = self else { timer.invalidate(); return }
                let elapsed = Date().timeIntervalSince(countdownStart)
                let remaining = 5.0 - elapsed
                if remaining > 0 {
                    self.sipCalibrationCountdown = Int(ceil(remaining))
                } else {
                    // Countdown finished — start actual capture
                    timer.invalidate()
                    self.sipCalibrationCountingDown = false
                    self.sipCalibrationCountdown = 0
                    self.startSipCapture()
                }
            }
        }
    }

    /// Begins the 10-second recording phase after the countdown completes.
    private func startSipCapture() {
        let now = Date()
        // The capture times itself on frame timestamps. `now` only drives the progress bar.
        sipCalibrationCapture.beginCapture()
        sipCalibrationActive = true
        sipCalibrationProgress = 0
        sipCalibrationStartTime = now

        sipCalibrationTimer?.invalidate()
        sipCalibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.sipCalibrationStartTime else {
                    timer.invalidate()
                    return
                }
                let elapsed = Date().timeIntervalSince(start)
                self.sipCalibrationProgress = min(elapsed / 10.0, 1.0)
                if elapsed >= 10.0 {
                    timer.invalidate()
                    self.sipCalibrationTimer = nil
                    self.sipCalibrationCapture.endCapture()
                    self.sipCalibrationActive = false
                    self.sipCalibrationProgress = 1.0
                }
            }
        }
    }

    /// Applies derived thresholds from completed calibration to the SipDetector
    /// and persists them to disk so they survive app restarts.
    func applySipCalibration() {
        guard let thresholds = sipCalibrationCapture.derivedThresholds else { return }
        sipDetector.thresholds = thresholds
        saveSipThresholds(thresholds)
    }

    // MARK: - Sip Threshold Persistence

    private static let sipThresholdsFile = "sip-thresholds.json"

    private var sipThresholdsURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.sipThresholdsFile)
    }

    private func loadSipThresholds() {
        guard let data = try? Data(contentsOf: sipThresholdsURL),
              let saved = try? JSONDecoder().decode(SipThresholds.self, from: data)
        else { return }
        sipDetector.thresholds = saved
    }

    private func saveSipThresholds(_ thresholds: SipThresholds) {
        guard let data = try? JSONEncoder().encode(thresholds) else { return }
        try? data.write(to: sipThresholdsURL, options: .atomic)
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
        case .frontFace: return arFaceService
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

    /// Debounce for `syncSettingsToWatch()`: the settings `didSet`s fire once
    /// per slider tick, and `applySettingsFromWatch` writes eight properties
    /// back-to-back — each re-triggering a sync, i.e. an echo straight back at
    /// the watch. Coalescing to one WCSession message after the burst settles
    /// keeps the channel quiet without changing what the watch eventually sees.
    private var settingsSyncTask: Task<Void, Never>?

    func syncSettingsToWatch() {
        settingsSyncTask?.cancel()
        settingsSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.sendSettingsToWatchNow()
        }
    }

    private func sendSettingsToWatchNow() {
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
