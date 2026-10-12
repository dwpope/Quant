import Combine
import Foundation

public class Pipeline {
    // MARK: - Published Properties

    /// Emits every raw `PoseObservation` produced by the Vision pipeline.
    ///
    /// Subscribers (e.g., `SipDetector`) can consume observations independently
    /// without Pipeline knowing they exist. This mirrors the fan-out pattern used
    /// throughout the posture system.
    ///
    /// Emitted from the same `@MainActor` task that updates all other published
    /// properties, so subscribers receive observations in the same order as
    /// `latestSample`, `trackingQuality`, etc.
    public let poseObservationPublisher = PassthroughSubject<PoseObservation, Never>()

    @Published public var latestSample: PoseSample?
    @Published public var latestMetrics: RawMetrics?
    @Published public var currentMode: DepthMode = .twoDOnly
    @Published public var depthConfidence: DepthConfidence = .unavailable
    @Published public var trackingQuality: TrackingQuality = .lost
    @Published public var fps: Float = 0.0
    @Published public var poseConfidence: Float = 0.0
    @Published public var poseKeypointCount: Int = 0
    @Published public var missingCriticalJoints: String = ""
    @Published public var postureState: PostureState = .absent

    /// The latest nudge decision from the NudgeEngine.
    ///
    /// This tells the UI and feedback systems what to do:
    /// - `.none`: Nothing happening — posture is fine or not bad enough yet.
    /// - `.pending`: Bad posture detected, counting down to nudge.
    /// - `.fire`: Time to nudge! The feedback layer should play audio/haptic.
    /// - `.suppressed`: Would nudge, but blocked by cooldown/limit/etc.
    ///
    /// When this becomes `.fire`, the caller (AppModel) should:
    /// 1. Deliver feedback (audio cue, watch haptic)
    /// 2. Call `recordNudgeFired()` on the pipeline
    @Published public var nudgeDecision: NudgeDecision = .none

    /// When the head was turned to one side and held there, on the frame clock, or nil. Timed
    /// only once calibrated: forward creep is what tells a turned neck from a turned chair.
    @Published public private(set) var headTurnedSince: TimeInterval?

    /// Nudges are held back until this moment, on the calendar clock: the user silenced them
    /// from the phone or the Watch. Compared with `now()`, never with the frame clock.
    public var nudgesSilencedUntil: Date?

    /// The calendar clock `nudgesSilencedUntil` is compared with. Swappable for tests.
    var now: () -> Date = Date.init

    private var nudgesSilenced: Bool {
        guard let until = nudgesSilencedUntil else { return false }
        return now() < until
    }

    /// The inferred activity classification based on recent movement patterns.
    /// Updated each frame after smoothing using a rolling window of metrics.
    @Published public var taskMode: TaskMode = .unknown

    /// Whether the calibration baseline is stale (position shifted or expired).
    /// Checked periodically (every 60s) rather than every frame.
    @Published var baselineStaleness: StaleBaselineResult = .fresh

    /// Current device thermal level. Updated by ThermalMonitor when provided.
    @Published public var thermalLevel: ThermalLevel = .nominal

    /// In-memory log of absence intervals for this session.
    /// Each entry is opened when `.absent` is entered and closed when it exits.
    /// Internal telemetry only — not surfaced in posture score or analytics.
    @Published public private(set) var absenceSegments: [(start: TimeInterval, end: TimeInterval?)] = []

    /// Set to true when the user returns from a long absence (≥ absentResumeThreshold).
    /// The UI should show a dismissible recalibration prompt when this is true.
    /// Clear it by calling dismissRecalibrationPrompt().
    @Published public private(set) var showRecalibrationPrompt: Bool = false

    /// The calibration baseline. Set this after a successful calibration to enable posture metrics.
    public var baseline: Baseline?

    /// Optional recorder that captures every PoseSample produced by the pipeline.
    /// Set this to a ``RecorderService`` instance to start recording.
    public var recorder: (any RecorderServiceProtocol)?

    /// The thresholds used by all engines in the pipeline.
    public var thresholds: PostureThresholds {
        didSet {
            postureEngine.thresholds = thresholds
            // The nudge engine reads the cooldown, the hourly cap and the time to nudge from
            // these. It used to keep its init values, so changes here silently didn't apply.
            nudgeEngine.thresholds = thresholds
        }
    }

    // MARK: - Private Properties

    private var subscriptions = Set<AnyCancellable>()
    private var poseService = PoseService()
    private var depthService = DepthService()
    private var fusion = PoseDepthFusion()
    private var metricsEngine = MetricsEngine()
    private var metricsSmoother = MetricsSmoother()
    private var modeSwitcher: ModeSwitcher
    private var postureEngine: PostureEngine
    private var nudgeEngine: NudgeEngine

    /// When a head held turned is worth a nudge. Reaches the tracker and the nudge engine,
    /// whether set at init or after.
    public var headTurnThresholds: HeadTurnThresholds {
        didSet {
            headTurnTracker.thresholds = headTurnThresholds
            nudgeEngine.headTurnThresholds = headTurnThresholds
        }
    }
    private let headTurnTracker: HeadTurnTracker

    /// Frame timestamp of the latest nudge evaluation, on the clock the NudgeEngine measures
    /// with. ``recordNudgeFired()`` records the fire at this time.
    private var lastNudgeEvaluationTime: TimeInterval?
    private var taskModeEngine = TaskModeEngine()
    private var staleBaselineDetector = StaleBaselineDetector()
    private var recentMetricsBuffer: [RawMetrics] = []
    private let metricsBufferMaxSize = 100
    private var lastStalenessCheckTime: TimeInterval = 0

    // Latest pose observation
    private var latestPoseObservation: PoseObservation?

    // FPS calculation
    private var lastFrameTime: TimeInterval = 0
    private var frameTimestamps: [TimeInterval] = []

    // Frame throttle to avoid spawning async Tasks at 60fps
    // Matches PoseService's ~10 FPS throttle rate
    // Confined to the provider's (serial) frame-delivery thread, like
    // `frameTimestamps` — only `process(_:)` touches it.
    private var lastPoseFrameTime: TimeInterval = 0

    // Thermal monitoring
    private var thermalMonitor: (any ThermalMonitorProtocol)?

    /// Guards `thermalPolicy` and `poseFrameInterval`: written from whatever
    /// thread the thermal monitor publishes on, read on the frame-delivery
    /// thread in `process(_:)`. Unsynchronized cross-thread access to these
    /// was a (benign-looking but undefined) data race.
    private let thermalStateLock = NSLock()
    private var thermalPolicy: ThermalPolicy = .nominal
    private var poseFrameInterval: TimeInterval = 0.1

    /// Snapshot of the thermal-derived throttle state, taken once per frame so
    /// a mid-frame thermal change can't yield a half-updated policy/interval pair.
    private var thermalState: (policy: ThermalPolicy, frameInterval: TimeInterval) {
        thermalStateLock.lock()
        defer { thermalStateLock.unlock() }
        return (thermalPolicy, poseFrameInterval)
    }

    /// `frameInterval: nil` keeps the previous interval (mirrors the original
    /// behaviour when a policy reports `maxFPS <= 0`, i.e. detection paused).
    private func setThermalState(policy: ThermalPolicy, frameInterval: TimeInterval?) {
        thermalStateLock.lock()
        defer { thermalStateLock.unlock() }
        thermalPolicy = policy
        if let frameInterval {
            poseFrameInterval = frameInterval
        }
    }

    // Tracking quality temporal smoothing
    private var currentTrackingQuality: TrackingQuality = .lost
    private var recentQualities: [TrackingQuality] = []
    private let qualityWindowSize = 3  // Require 3 consecutive frames to change state (~50ms at 60fps)

    // MARK: - Initialization

    public init(
        provider: PoseProvider,
        thresholds: PostureThresholds = PostureThresholds(),
        headTurnThresholds: HeadTurnThresholds = HeadTurnThresholds(),
        thermalMonitor: (any ThermalMonitorProtocol)? = nil
    ) {
        self.thresholds = thresholds
        self.headTurnThresholds = headTurnThresholds
        self.thermalMonitor = thermalMonitor
        self.modeSwitcher = ModeSwitcher(thresholds: thresholds)
        self.postureEngine = PostureEngine(thresholds: thresholds)
        self.nudgeEngine = NudgeEngine(thresholds: thresholds, headTurnThresholds: headTurnThresholds)
        self.headTurnTracker = HeadTurnTracker(thresholds: headTurnThresholds)

        // Subscribe to thermal level changes
        if let monitor = thermalMonitor {
            self.thermalLevel = monitor.currentLevel
            self.setThermalState(
                policy: monitor.currentPolicy,
                frameInterval: monitor.currentPolicy.maxFPS > 0
                    ? TimeInterval(1.0 / monitor.currentPolicy.maxFPS)
                    : 0.1
            )
            monitor.levelPublisher
                .sink { [weak self] level in
                    guard let self = self else { return }
                    let policy = ThermalPolicy.policy(for: level)
                    self.setThermalState(
                        policy: policy,
                        frameInterval: policy.maxFPS > 0
                            ? TimeInterval(1.0 / policy.maxFPS)
                            : nil
                    )
                    // `thermalLevel` is @Published — it must be set on the
                    // main thread, but thermal notifications can arrive on any
                    // thread. Stay synchronous when already on main so callers
                    // (and tests) observe the change immediately.
                    if Thread.isMainThread {
                        self.thermalLevel = level
                    } else {
                        DispatchQueue.main.async { self.thermalLevel = level }
                    }
                }
                .store(in: &subscriptions)
        }

        provider.framePublisher
            .sink { [weak self] frame in
                self?.process(frame)
            }
            .store(in: &subscriptions)
    }

    // MARK: - Private Methods

    private func process(_ frame: InputFrame) {
        // Precomputed sample path — replay/test bypass.
        // Skips pose detection and fusion; runs metrics, posture, and nudge engines.
        if let sample = frame.precomputedSample {
            processPrecomputed(sample, timestamp: frame.timestamp)
            return
        }

        // Single locked snapshot per frame of the thermal-derived throttle
        // state (it is written from the thermal monitor's thread).
        let (thermalPolicy, poseFrameInterval) = thermalState

        // Thermal throttle: skip all processing when critical
        if thermalPolicy.detectionPaused {
            return
        }

        // Compute FPS. Cheap (timestamp bookkeeping) and must run on every
        // ARFrame so the readout reflects true input throughput, not the
        // throttled pose cadence — so it stays above the gate.
        let currentFPS = computeFPS(timestamp: frame.timestamp)

        // Throttle async Task creation to ~10 FPS to prevent ARFrame retention.
        // CVPixelBuffers in InputFrame keep ARFrames alive until the Task completes;
        // spawning at 60fps causes 10+ ARFrames to pile up in flight.
        //
        // Everything below the gate runs at the pose cadence (~10 FPS) instead of
        // the 60 FPS frame rate. This is the thermal hot-path fix: depth-confidence
        // reads a 400-point grid out of the depth pixel buffer (~24k reads/sec at
        // 60fps vs ~4k at 10fps), and the per-frame @MainActor hop was invalidating
        // every SwiftUI observer of fps/depthConfidence/currentMode 60×/sec.
        guard frame.timestamp - lastPoseFrameTime >= poseFrameInterval else {
            return
        }
        lastPoseFrameTime = frame.timestamp

        // Compute depth confidence (heavy: 400-point depth-buffer grid read).
        let confidence = depthService.computeConfidence(from: frame)

        // Update mode based on depth confidence. Time-based decision, so the
        // slower cadence does not affect its hysteresis.
        let mode = modeSwitcher.update(confidence: confidence, timestamp: frame.timestamp)

        // Update published properties on main thread (now at ~10 FPS).
        framesInFlight.begin()
        Task { @MainActor [weak self, framesInFlight] in
            defer { framesInFlight.end() }
            guard let self = self else { return }
            self.fps = currentFPS
            self.depthConfidence = confidence
            self.currentMode = mode
        }

        // Extract frame data to avoid retaining the entire InputFrame
        let hasPixelBuffer = frame.pixelBuffer != nil

        // Capture current tracking quality for hysteresis (must read on current thread to avoid race conditions)
        let currentQuality = currentTrackingQuality

        // Process pose asynchronously at ~10 FPS
        framesInFlight.begin()
        Task { [weak self, poseService, frame, framesInFlight] in
            defer { framesInFlight.end() }
            guard let self = self else { return }

            // Extract pose keypoints using Vision
            let poseResult = await poseService.process(frame: frame)

            if case .throttled = poseResult {
                return
            }

            let poseObservation: PoseObservation?
            switch poseResult {
            case .observation(let observation):
                poseObservation = observation
            case .noPose, .failed:
                poseObservation = nil
            case .throttled:
                poseObservation = nil
            }

            // Sample depth at keypoint positions when depth is available and not
            // thermally disabled. Uses the policy snapshot taken with this frame,
            // so the decision is consistent with the throttle gate above.
            let depthSamples: [DepthAtPoint]?
            if let observation = poseObservation, confidence >= .medium, thermalPolicy.depthEnabled {
                let keypointPositions = observation.keypoints.map { $0.position }
                depthSamples = self.depthService.sampleDepth(at: keypointPositions, from: frame)
            } else {
                depthSamples = nil
            }

            // Determine tracking quality based on pose detection (with hysteresis)
            let qualityResult = Pipeline.computeTrackingQualityWithDiag(
                poseObservation: poseObservation,
                hasPixelBuffer: hasPixelBuffer,
                previousQuality: currentQuality
            )
            let rawQuality = qualityResult.quality
            let missingJoints = qualityResult.missingJoints

            // Apply temporal smoothing to prevent flickering
            // Update on main thread to ensure thread-safe access to recentQualities
            await MainActor.run {
                guard self.takesFrame(at: frame.timestamp) else { return }
                // Add to sliding window
                self.recentQualities.append(rawQuality)
                if self.recentQualities.count > self.qualityWindowSize {
                    self.recentQualities.removeFirst()
                }

                // Determine final quality using majority vote (2-of-3)
                // instead of unanimous agreement, so one flicker doesn't block upgrades
                let finalQuality: TrackingQuality

                if self.recentQualities.count == self.qualityWindowSize {
                    // Count occurrences of each quality level
                    let counts = Dictionary(grouping: self.recentQualities, by: { $0 })
                    // Pick the quality that appears most often (majority wins)
                    if let majority = counts.max(by: { $0.value.count < $1.value.count })?.key {
                        finalQuality = majority
                    } else {
                        finalQuality = self.currentTrackingQuality
                    }
                } else {
                    // Window not full yet - keep current quality
                    finalQuality = self.currentTrackingQuality
                }

                // Update published properties
                self.latestPoseObservation = poseObservation
                if let observation = poseObservation {
                    self.poseObservationPublisher.send(observation)
                }
                self.poseConfidence = poseObservation?.confidence ?? 0.0
                self.poseKeypointCount = poseObservation?.keypoints.count ?? 0
                self.missingCriticalJoints = missingJoints
                self.trackingQuality = finalQuality
                self.currentTrackingQuality = finalQuality

                // Fuse pose into a normalized PoseSample
                if let observation = poseObservation {
                    let sample = self.fusion.fuse(
                        pose: observation,
                        depthSamples: depthSamples,
                        confidence: confidence,
                        intrinsics: frame.cameraIntrinsics,
                        trackingQuality: finalQuality
                    )
                    self.ingest(sample, quality: finalQuality, at: frame.timestamp)
                } else {
                    self.judgeWithoutPose(at: frame.timestamp, quality: .lost)
                }
            }
        }
    }

    /// Whether to take a frame: not one that finished after a newer one (2026-10-10).
    ///
    /// Pose detection runs concurrently, so now and then a frame's result lands after a newer
    /// frame's: Dave's session-4 recording has four in seven minutes, each 0.1 s back. Taken, it
    /// stepped every timer backwards; the nudge engine read that as a break and wiped the
    /// slouched time and the good streak. A step back of `newTimelineAfter` or more is a new
    /// timeline (a replay after live frames), not a late frame, so it's taken.
    ///
    /// A new timeline starts the engines afresh (2026-10-11): their clocks were left behind, and
    /// the nudge engine took every replay frame after live frames for a late one.
    private func takesFrame(at timestamp: TimeInterval) -> Bool {
        let stepBack = lastTakenFrameTime - timestamp
        if stepBack >= Self.newTimelineAfter {
            startNewTimeline()
        } else if stepBack >= 0 {
            return false  // late
        }
        lastTakenFrameTime = timestamp
        return true
    }

    /// Starts every engine afresh, as for a new timeline: a replay after live frames, or live
    /// frames after a replay. The app calls it when it starts or stops a replay, so a recording
    /// that begins less than `newTimelineAfter` before the last frame isn't dropped as late.
    public func resetTimeline() {
        lastTakenFrameTime = -.infinity
        startNewTimeline()
    }

    private func startNewTimeline() {
        postureEngine.reset()
        nudgeEngine.reset()
        headTurnTracker.reset()
        metricsSmoother.reset()
        recentMetricsBuffer.removeAll()
        recentQualities.removeAll()
        headTurnedSince = nil
        lastNudgeEvaluationTime = nil
    }

    private var lastTakenFrameTime: TimeInterval = -.infinity
    private static let newTimelineAfter: TimeInterval = 5

    /// One frame's pose through every engine, from a camera or a replay (2026-10-11: the two
    /// paths had their own copies of this). A pose that couldn't be built is judged without one.
    /// Internal so tests can drive it.
    @MainActor
    func ingest(_ sample: PoseSample?, quality: TrackingQuality, at timestamp: TimeInterval) {
        latestSample = sample
        guard let sample else {
            judgeWithoutPose(at: timestamp, quality: quality == .lost ? .lost : .degraded)
            return
        }
        recorder?.record(sample: sample)

        let rawMetrics = metricsEngine.compute(from: sample, baseline: baseline)
        let smoothedMetrics = metricsSmoother.smooth(rawMetrics, sample: sample)
        latestMetrics = smoothedMetrics

        // Infer task mode from rolling window of recent metrics
        recentMetricsBuffer.append(smoothedMetrics)
        if recentMetricsBuffer.count > metricsBufferMaxSize {
            recentMetricsBuffer.removeFirst()
        }
        let inferredTaskMode = taskModeEngine.infer(from: recentMetricsBuffer)
        taskMode = inferredTaskMode

        // Update the posture state machine with the latest metrics.
        // The engine decides good/drifting/bad based on thresholds
        // and pauses its timers when tracking quality is low.
        let previousPostureState = postureState
        let newPostureState = postureEngine.update(
            metrics: smoothedMetrics,
            taskMode: inferredTaskMode,
            trackingQuality: quality,
            chairTurned: isChairTurned(sample: sample, metrics: smoothedMetrics),
            reclined: isReclined(sample: sample, metrics: smoothedMetrics),
            neckTurned: isNeckTurned(sample: sample, metrics: smoothedMetrics)
        )
        postureState = newPostureState

        // Track absence segments (internal telemetry).
        let wasAbsent = previousPostureState == .absent
        let isAbsent = newPostureState == .absent
        if isAbsent && !wasAbsent {
            recordAbsenceStart(at: smoothedMetrics.timestamp)
        } else if wasAbsent && !isAbsent {
            if let idx = absenceSegments.indices.last, absenceSegments[idx].end == nil {
                absenceSegments[idx].end = smoothedMetrics.timestamp
            }
        }

        // Forward recalibration prompt from engine to UI.
        if postureEngine.consumeRecalibrationPrompt() {
            showRecalibrationPrompt = true
        }

        // Evaluate nudge decision based on the updated posture state.
        // The NudgeEngine checks: Is posture bad long enough?
        // Is cooldown active? Is the hourly limit reached?
        // The metrics and the signals that counted are passed so the engine can name the
        // specific nudge reason (forwardCreep, headDrop, sink).
        lastNudgeEvaluationTime = smoothedMetrics.timestamp
        let turnedSince = updateHeadTurn(sample: sample, metrics: smoothedMetrics, trackingQuality: quality)
        nudgeDecision = nudgeEngine.evaluate(
            state: newPostureState,
            trackingQuality: quality,
            movementLevel: smoothedMetrics.movementLevel,
            taskMode: inferredTaskMode,
            currentTime: smoothedMetrics.timestamp,
            metrics: smoothedMetrics,
            headTurnedSince: turnedSince,
            silenced: nudgesSilenced,
            slouchSignals: postureEngine.slouchSignals
        )

        // Periodic staleness check (every 60s, not every frame)
        if let baseline, smoothedMetrics.timestamp - lastStalenessCheckTime >= 60 {
            lastStalenessCheckTime = smoothedMetrics.timestamp
            baselineStaleness = staleBaselineDetector.check(
                current: sample,
                baseline: baseline,
                baselineAge: Date().timeIntervalSince(baseline.timestamp)
            )
        }
    }

    /// Opens an absence segment, keeping only the most recent `maxAbsenceSegments`: nothing
    /// reads them yet, and they grew for as long as the app ran.
    private func recordAbsenceStart(at timestamp: TimeInterval) {
        absenceSegments.append((start: timestamp, end: nil))
        if absenceSegments.count > Self.maxAbsenceSegments {
            absenceSegments.removeFirst(absenceSegments.count - Self.maxAbsenceSegments)
        }
    }

    private static let maxAbsenceSegments = 200

    /// A frame without a pose to judge (2026-10-08, 2026-10-11).
    ///
    /// `.lost`: Vision found no person. Until 2026-10-08 such frames never reached the posture
    /// engine, so walking away froze the panel on its last words; now after `absentThreshold`
    /// the state is `.absent`, and there's nothing to nudge for.
    ///
    /// `.degraded`: a person, but no pose could be built from them, as with one shoulder hidden
    /// by an arm (a pose needs both). Until 2026-10-11 nothing ran on such a frame either, and the
    /// state, the nudge decision and the Watch froze; now the timers pause and the decision says
    /// tracking is too poor to judge.
    private func judgeWithoutPose(at timestamp: TimeInterval, quality: TrackingQuality) {
        if quality != .lost { trackingQuality = quality }
        let previousPostureState = postureState
        let newPostureState = postureEngine.updateWithoutPose(at: timestamp, quality: quality)
        postureState = newPostureState

        // Track absence segments (internal telemetry).
        if newPostureState == .absent && previousPostureState != .absent {
            recordAbsenceStart(at: timestamp)
        }

        // No head to be judged turned: the head-turn timer winds down through its grace period.
        let turnedSince: TimeInterval?
        if baseline != nil {
            turnedSince = headTurnTracker.update(headYaw: 0, forwardCreep: 0, trackingQuality: quality,
                                                 timestamp: timestamp)
        } else {
            turnedSince = nil
        }
        headTurnedSince = turnedSince

        lastNudgeEvaluationTime = timestamp
        nudgeDecision = nudgeEngine.evaluate(
            state: newPostureState,
            trackingQuality: quality,
            movementLevel: 0,
            taskMode: taskMode,
            currentTime: timestamp,
            metrics: nil,
            headTurnedSince: turnedSince,
            silenced: nudgesSilenced
        )
    }

    /// The whole chair turned: head and shoulders together. Only once calibrated, like the head
    /// turn, since it needs forward creep.
    private func isChairTurned(sample: PoseSample, metrics: RawMetrics) -> Bool {
        guard let baseline else { return false }
        return HeadTurnTracker.isChairTurned(
            headYaw: sample.headYaw - baseline.headYaw, forwardCreep: metrics.forwardCreep,
            thresholds: headTurnThresholds)
    }

    /// The head turned with the shoulders square (`HeadTurnTracker.isNeckTurned`), from the
    /// calibrated angle. Only once calibrated.
    private func isNeckTurned(sample: PoseSample, metrics: RawMetrics) -> Bool {
        guard let baseline else { return false }
        return HeadTurnTracker.isNeckTurned(
            headYaw: sample.headYaw - baseline.headYaw, forwardCreep: metrics.forwardCreep,
            thresholds: headTurnThresholds)
    }

    /// Leaning back against the backrest (`PostureEngine.isReclined`). Only once calibrated.
    private func isReclined(sample: PoseSample, metrics: RawMetrics) -> Bool {
        guard let baseline else { return false }
        return PostureEngine.isReclined(
            forwardCreep: metrics.forwardCreep, headYawFromCalibration: sample.headYaw - baseline.headYaw,
            thresholds: thresholds, headTurn: headTurnThresholds)
    }

    /// Times a head held turned. Not before calibrating: without a baseline forward creep reads
    /// zero, and it's what tells a turned neck from a turned chair.
    private func updateHeadTurn(sample: PoseSample, metrics: RawMetrics,
                                trackingQuality: TrackingQuality) -> TimeInterval? {
        guard let baseline else {
            headTurnTracker.reset()
            headTurnedSince = nil
            return nil
        }
        // Measured from where you looked when calibrating: yaw is camera-absolute, and the
        // phone needn't sit straight in front.
        let since = headTurnTracker.update(
            headYaw: sample.headYaw - baseline.headYaw, forwardCreep: metrics.forwardCreep,
            trackingQuality: trackingQuality, timestamp: metrics.timestamp)
        headTurnedSince = since
        return since
    }

    /// Fast path for precomputed samples (replay / test).
    /// Skips pose detection, depth, mode switching, and throttle.
    /// Frames handed to tasks and not yet finished. See `settled()`.
    private let framesInFlight = FramesInFlight()

    /// Returns once every frame handed in so far has been processed (2026-10-12). For tests,
    /// which used to sleep a fixed time per frame and hope; also for a caller that must read the
    /// results of a burst of replayed frames.
    public func settled() async {
        await framesInFlight.settled()
    }

    private func processPrecomputed(_ sample: PoseSample, timestamp: TimeInterval) {
        let currentFPS = computeFPS(timestamp: timestamp)

        framesInFlight.begin()
        Task { @MainActor [weak self, framesInFlight] in
            defer { framesInFlight.end() }
            guard let self = self else { return }
            guard self.takesFrame(at: timestamp) else { return }
            self.fps = currentFPS
            self.trackingQuality = sample.trackingQuality
            self.currentTrackingQuality = sample.trackingQuality
            self.ingest(sample, quality: sample.trackingQuality, at: timestamp)
        }
    }

    static func computeTrackingQuality(poseObservation: PoseObservation?, hasPixelBuffer: Bool, previousQuality: TrackingQuality) -> TrackingQuality {
        return computeTrackingQualityWithDiag(poseObservation: poseObservation, hasPixelBuffer: hasPixelBuffer, previousQuality: previousQuality).quality
    }

    struct TrackingQualityResult {
        let quality: TrackingQuality
        let missingJoints: String
    }

    static func computeTrackingQualityWithDiag(poseObservation: PoseObservation?, hasPixelBuffer: Bool, previousQuality: TrackingQuality) -> TrackingQualityResult {
        // No pixel buffer = lost
        guard hasPixelBuffer else {
            return TrackingQualityResult(quality: .lost, missingJoints: "no pixelBuffer")
        }

        // No pose detected = lost
        guard let observation = poseObservation else {
            return TrackingQualityResult(quality: .lost, missingJoints: "no pose")
        }

        let minConf: Float = 0.3

        // Check critical keypoints — at least ONE shoulder + head region
        let hasLeftShoulder = observation.keypoints.contains { $0.joint == .leftShoulder && $0.confidence > minConf }
        let hasRightShoulder = observation.keypoints.contains { $0.joint == .rightShoulder && $0.confidence > minConf }
        let hasAnyShoulder = hasLeftShoulder || hasRightShoulder

        // Accept any head-region joint (nose, eyes, ears)
        let headJoints: Set<Joint> = [.nose, .leftEye, .rightEye, .leftEar, .rightEar]
        let hasHead = observation.keypoints.contains {
            headJoints.contains($0.joint) && $0.confidence > minConf
        }

        let keypointCount = observation.keypoints.count

        // Build diagnostic string for missing joints
        var missing: [String] = []
        if !hasLeftShoulder { missing.append("LShldr") }
        if !hasRightShoulder { missing.append("RShldr") }
        if !hasHead { missing.append("Head") }
        let missingStr = missing.isEmpty ? "none" : missing.joined(separator: ",")

        // Need at least one shoulder and a head joint for good tracking
        if hasAnyShoulder && hasHead {
            // Determine confidence threshold based on previous state (hysteresis)
            let confidenceThreshold: Float
            switch previousQuality {
            case .good:
                confidenceThreshold = 0.75
            case .degraded, .lost:
                confidenceThreshold = 0.65
            }

            let quality: TrackingQuality = observation.confidence > confidenceThreshold ? .good : .degraded
            return TrackingQualityResult(quality: quality, missingJoints: missingStr)
        }

        // Some keypoints but not enough for good tracking
        let keypointThreshold: Int
        switch previousQuality {
        case .lost:
            keypointThreshold = 4
        case .degraded, .good:
            keypointThreshold = 2
        }

        let quality: TrackingQuality = keypointCount >= keypointThreshold ? .degraded : .lost
        return TrackingQualityResult(quality: quality, missingJoints: missingStr)
    }

    // MARK: - Recalibration Prompt Control

    /// Dismisses the recalibration prompt shown after a long absence.
    ///
    /// Call this when the user taps "Dismiss" or "Not now" on the prompt.
    /// The old baseline stays in effect; StaleBaselineDetector will catch
    /// any drift that accumulated during the absence.
    public func dismissRecalibrationPrompt() {
        showRecalibrationPrompt = false
    }

    // MARK: - Nudge Control Methods

    /// Record that a nudge was delivered to the user.
    ///
    /// Call this from the feedback layer (AppModel) after the audio cue or watch haptic is
    /// delivered. This starts the cooldown timer and counts toward the hourly limit.
    ///
    /// It takes no time on purpose. The NudgeEngine measures the cooldown and the hourly window
    /// on the frame clock (seconds since boot until 2026-10-05, since 1970 now). This used to take a
    /// time, and the documented production value was `Date().timeIntervalSince1970`, about
    /// 1.79 billion against ~670,000. `currentTime - lastNudgeTime` was then always far below
    /// the cooldown, so the cooldown never ended and the app nudged once per launch. The fire
    /// is now recorded at the frame that produced it, so the clocks can't be mixed.
    public func recordNudgeFired() {
        guard let frameTime = lastNudgeEvaluationTime else { return }  // no frame, no fire
        nudgeEngine.recordNudgeFired(at: frameTime)
    }

    /// The nudge engine's debug dump: cooldown, hourly count, last decision.
    var nudgeDebugState: [String: Any] { nudgeEngine.debugState }

    /// Record that the user corrected their posture after a nudge.
    ///
    /// Call this when the PostureEngine transitions from `.bad` back to `.good`
    /// within the acknowledgement window. This suppresses re-nudging for the
    /// same slouch episode.
    public func recordNudgeAcknowledgement() {
        nudgeEngine.recordAcknowledgement()
    }

    /// Reset the NudgeEngine state. Call this on app relaunch or recalibration.
    public func resetNudgeEngine() {
        nudgeEngine.reset()
        headTurnTracker.reset()
    }

    private func computeFPS(timestamp: TimeInterval) -> Float {
        // Track timestamps for rolling average
        frameTimestamps.append(timestamp)

        // Keep only last 30 frames for FPS calculation
        if frameTimestamps.count > 30 {
            frameTimestamps.removeFirst()
        }

        // Calculate FPS from timestamp deltas
        if frameTimestamps.count >= 2 {
            let duration = frameTimestamps.last! - frameTimestamps.first!
            if duration > 0 {
                return Float(frameTimestamps.count - 1) / Float(duration)
            }
        }

        return 0.0
    }
}
