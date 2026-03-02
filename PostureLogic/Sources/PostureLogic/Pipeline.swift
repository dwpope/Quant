import Combine
import Foundation

public class Pipeline {
    // MARK: - Published Properties

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

    /// The calibration baseline. Set this after a successful calibration to enable posture metrics.
    public var baseline: Baseline?

    /// The thresholds used by all engines in the pipeline.
    public var thresholds: PostureThresholds {
        didSet {
            postureEngine.thresholds = thresholds
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

    // Latest pose observation
    private var latestPoseObservation: PoseObservation?

    // FPS calculation
    private var lastFrameTime: TimeInterval = 0
    private var frameTimestamps: [TimeInterval] = []

    // Frame throttle to avoid spawning async Tasks at 60fps
    // Matches PoseService's ~10 FPS throttle rate
    private var lastPoseFrameTime: TimeInterval = 0
    private let poseFrameInterval: TimeInterval = 0.1

    // Tracking quality temporal smoothing
    private var currentTrackingQuality: TrackingQuality = .lost
    private var recentQualities: [TrackingQuality] = []
    private let qualityWindowSize = 3  // Require 3 consecutive frames to change state (~50ms at 60fps)

    // MARK: - Initialization

    public init(provider: PoseProvider, thresholds: PostureThresholds = PostureThresholds()) {
        self.thresholds = thresholds
        self.modeSwitcher = ModeSwitcher(thresholds: thresholds)
        self.postureEngine = PostureEngine(thresholds: thresholds)
        self.nudgeEngine = NudgeEngine(thresholds: thresholds)

        provider.framePublisher
            .sink { [weak self] frame in
                self?.process(frame)
            }
            .store(in: &subscriptions)
    }

    // MARK: - Private Methods

    private func process(_ frame: InputFrame) {
        // Compute FPS
        let currentFPS = computeFPS(timestamp: frame.timestamp)

        // Compute depth confidence
        let confidence = depthService.computeConfidence(from: frame)

        // Update mode based on depth confidence
        let mode = modeSwitcher.update(confidence: confidence, timestamp: frame.timestamp)

        // Update published properties on main thread
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.fps = currentFPS
            self.depthConfidence = confidence
            self.currentMode = mode
        }

        // Throttle async Task creation to ~10 FPS to prevent ARFrame retention.
        // CVPixelBuffers in InputFrame keep ARFrames alive until the Task completes;
        // spawning at 60fps causes 10+ ARFrames to pile up in flight.
        guard frame.timestamp - lastPoseFrameTime >= poseFrameInterval else {
            return
        }
        lastPoseFrameTime = frame.timestamp

        // Extract frame data to avoid retaining the entire InputFrame
        let hasPixelBuffer = frame.pixelBuffer != nil

        // Capture current tracking quality for hysteresis (must read on current thread to avoid race conditions)
        let currentQuality = currentTrackingQuality

        // Process pose asynchronously at ~10 FPS
        Task { [weak self, poseService, frame] in
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
                self.poseConfidence = poseObservation?.confidence ?? 0.0
                self.poseKeypointCount = poseObservation?.keypoints.count ?? 0
                self.missingCriticalJoints = missingJoints
                self.trackingQuality = finalQuality
                self.currentTrackingQuality = finalQuality

                // Fuse pose into a normalized PoseSample
                if let observation = poseObservation {
                    let sample = self.fusion.fuse(
                        pose: observation,
                        depthSamples: nil,
                        confidence: confidence,
                        trackingQuality: finalQuality
                    )
                    self.latestSample = sample

                    if let sample = sample {
                        let rawMetrics = self.metricsEngine.compute(
                            from: sample,
                            baseline: self.baseline
                        )
                        let smoothedMetrics = self.metricsSmoother.smooth(
                            rawMetrics,
                            sample: sample
                        )
                        self.latestMetrics = smoothedMetrics

                        // Update the posture state machine with the latest metrics.
                        // The engine decides good/drifting/bad based on thresholds
                        // and pauses its timers when tracking quality is low.
                        let newPostureState = self.postureEngine.update(
                            metrics: smoothedMetrics,
                            taskMode: .unknown,  // TaskModeEngine added in Sprint 7
                            trackingQuality: finalQuality
                        )
                        self.postureState = newPostureState

                        // Evaluate nudge decision based on the updated posture state.
                        // The NudgeEngine checks: Is posture bad long enough?
                        // Is cooldown active? Is the hourly limit reached?
                        // The metrics are passed so the engine can determine the
                        // specific nudge reason (forwardCreep, headDrop, etc.).
                        self.nudgeDecision = self.nudgeEngine.evaluate(
                            state: newPostureState,
                            trackingQuality: finalQuality,
                            movementLevel: smoothedMetrics.movementLevel,
                            taskMode: .unknown,  // TaskModeEngine added in Sprint 7
                            currentTime: smoothedMetrics.timestamp,
                            metrics: smoothedMetrics
                        )
                    }
                }
            }
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

    // MARK: - Nudge Control Methods

    /// Record that a nudge was delivered to the user.
    ///
    /// Call this from the feedback layer (AppModel) after the audio cue
    /// or watch haptic is successfully delivered. This starts the cooldown
    /// timer and increments the hourly nudge counter in the NudgeEngine.
    ///
    /// - Parameter currentTime: The timestamp when the nudge was delivered.
    ///   Pass `Date().timeIntervalSince1970` in production, or a test value.
    public func recordNudgeFired(at currentTime: TimeInterval) {
        nudgeEngine.recordNudgeFired(at: currentTime)
    }

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
