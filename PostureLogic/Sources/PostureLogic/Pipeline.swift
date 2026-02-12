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

    // Tracking quality temporal smoothing
    private var currentTrackingQuality: TrackingQuality = .lost
    private var recentQualities: [TrackingQuality] = []
    private let qualityWindowSize = 3  // Require 3 consecutive frames to change state (~50ms at 60fps)

    // MARK: - Initialization

    public init(provider: PoseProvider, thresholds: PostureThresholds = PostureThresholds()) {
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

        // Extract frame data to avoid retaining the entire InputFrame
        let hasPixelBuffer = frame.pixelBuffer != nil

        // Capture current tracking quality for hysteresis (must read on current thread to avoid race conditions)
        let currentQuality = currentTrackingQuality

        // Process pose asynchronously
        // Note: PoseService handles its own throttling to ~10 FPS to avoid Vision framework overload
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
            let rawQuality: TrackingQuality = self.computeTrackingQuality(
                poseObservation: poseObservation,
                hasPixelBuffer: hasPixelBuffer,
                previousQuality: currentQuality
            )

            // Apply temporal smoothing to prevent flickering
            // Update on main thread to ensure thread-safe access to recentQualities
            await MainActor.run {
                // Add to sliding window
                self.recentQualities.append(rawQuality)
                if self.recentQualities.count > self.qualityWindowSize {
                    self.recentQualities.removeFirst()
                }

                // Determine final quality based on temporal smoothing
                let finalQuality: TrackingQuality

                // If window is full, check if all values agree
                if self.recentQualities.count == self.qualityWindowSize {
                    let allSame = self.recentQualities.allSatisfy { $0 == self.recentQualities.first }
                    if allSame && self.recentQualities.first != self.currentTrackingQuality {
                        // All frames agree on a different quality - change state
                        finalQuality = self.recentQualities.first!
                    } else {
                        // Window doesn't agree or agrees with current state - keep current
                        finalQuality = self.currentTrackingQuality
                    }
                } else {
                    // Window not full yet - keep current quality
                    finalQuality = self.currentTrackingQuality
                }

                // Update published properties
                self.latestPoseObservation = poseObservation
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
                        // The result tells the UI/feedback layer what to do.
                        self.nudgeDecision = self.nudgeEngine.evaluate(
                            state: newPostureState,
                            trackingQuality: finalQuality,
                            movementLevel: smoothedMetrics.movementLevel,
                            taskMode: .unknown,  // TaskModeEngine added in Sprint 7
                            currentTime: smoothedMetrics.timestamp
                        )
                    }
                }
            }
        }
    }

    private func computeTrackingQuality(poseObservation: PoseObservation?, hasPixelBuffer: Bool, previousQuality: TrackingQuality) -> TrackingQuality {
        // No pixel buffer = lost
        guard hasPixelBuffer else {
            return .lost
        }

        // No pose detected = lost
        guard let observation = poseObservation else {
            return .lost
        }

        // Check if we have the critical keypoints (shoulders and head)
        let hasLeftShoulder = observation.keypoints.contains { $0.joint == .leftShoulder && $0.confidence > 0.5 }
        let hasRightShoulder = observation.keypoints.contains { $0.joint == .rightShoulder && $0.confidence > 0.5 }
        let hasHead = observation.keypoints.contains {
            ($0.joint == .nose || $0.joint == .leftEye || $0.joint == .rightEye) && $0.confidence > 0.5
        }

        let keypointCount = observation.keypoints.count

        // Apply hysteresis to prevent rapid state changes
        // Use different thresholds depending on current state to create "buffer zones"

        // Need at least shoulders and head for good tracking
        if hasLeftShoulder && hasRightShoulder && hasHead {
            // Determine confidence threshold based on previous state (hysteresis)
            let confidenceThreshold: Float
            switch previousQuality {
            case .good:
                // Higher bar to drop from good to degraded
                confidenceThreshold = 0.65
            case .degraded, .lost:
                // Lower bar to upgrade to good
                confidenceThreshold = 0.75
            }

            return observation.confidence > confidenceThreshold ? .good : .degraded
        }

        // Some keypoints but not enough for good tracking
        // Use hysteresis for degraded <-> lost transitions
        let keypointThreshold: Int
        switch previousQuality {
        case .lost:
            // Need more keypoints to upgrade from lost to degraded
            keypointThreshold = 4
        case .degraded, .good:
            // Need fewer keypoints to downgrade to lost
            keypointThreshold = 2
        }

        if keypointCount >= keypointThreshold {
            return .degraded
        }

        return .lost
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
