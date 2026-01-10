import Combine
import Foundation

@MainActor public class Pipeline {
    // MARK: - Published Properties

    @Published public var latestSample: PoseSample?
    @Published public var latestMetrics: RawMetrics?
    @Published public var currentMode: DepthMode = .twoDOnly
    @Published public var depthConfidence: DepthConfidence = .unavailable
    @Published public var trackingQuality: TrackingQuality = .lost
    @Published public var fps: Float = 0.0

    // MARK: - Private Properties

    private var subscriptions = Set<AnyCancellable>()
    nonisolated(unsafe) private var poseService = PoseService()
    private var depthService = DepthService()
    private var poseDepthFusion = PoseDepthFusion()
    private var modeSwitcher: ModeSwitcher
    private var metricsEngine = MetricsEngine()

    // Baseline for metrics comparison (nil for now, will be set via calibration later)
    private var baseline: Baseline?

    // Latest pose observation
    private var latestPoseObservation: PoseObservation?

    // Pose processing state
    private var isPoseProcessing = false
    private var poseProcessingDropped = 0

    // Track last pose process time to detect throttling
    private var lastPoseProcessTime: TimeInterval = 0
    private let minPoseInterval: TimeInterval = 0.1  // Match PoseService throttle

    // FPS calculation
    private var lastFrameTime: TimeInterval = 0
    private var frameTimestamps: [TimeInterval] = []

    // Serial queue for Vision processing to prevent ARFrame buildup
    private let visionQueue = DispatchQueue(label: "com.quant.vision", qos: .userInitiated)

    // MARK: - Initialization

    public init(provider: PoseProvider, thresholds: PostureThresholds = PostureThresholds()) {
        self.modeSwitcher = ModeSwitcher(thresholds: thresholds)

        provider.framePublisher
            .sink { [weak self] frame in
                self?.process(frame)
            }
            .store(in: &subscriptions)
    }

    // MARK: - Private Methods

    private func process(_ frame: InputFrame) {
        updateFPS(timestamp: frame.timestamp)

        // Compute depth confidence
        let confidence = depthService.computeConfidence(from: frame)
        self.depthConfidence = confidence

        // Update mode based on depth confidence
        let mode = modeSwitcher.update(confidence: confidence, timestamp: frame.timestamp)
        self.currentMode = mode

        // Skip pose processing if already processing to avoid frame buildup
        guard !isPoseProcessing else {
            poseProcessingDropped += 1
            return
        }

        // Mark as processing
        isPoseProcessing = true

        // Extract only what we need BEFORE dispatching to avoid retaining the entire InputFrame/ARFrame
        let timestamp = frame.timestamp
        let pixelBuffer = frame.pixelBuffer
        let depthMap = frame.depthMap
        let cameraIntrinsics = frame.cameraIntrinsics
        let hasPixelBuffer = pixelBuffer != nil

        // Debug: Log pixel buffer status
        if !hasPixelBuffer {
            print("⚠️ Pipeline: Received frame with nil pixel buffer at \(timestamp)")
        }

        // Process pose on serial queue to prevent ARFrame buildup
        // Using serial queue with SYNCHRONOUS processing ensures only ONE Vision request at a time
        // and pixel buffer is released immediately after processing
        visionQueue.async { [weak self] in
            guard let self = self else { return }

            // Extract pose keypoints using Vision (SYNCHRONOUS on background queue)
            // This blocks the serial queue until Vision completes, preventing ARFrame buildup
            let poseObs = self.poseService.processSync(pixelBuffer: pixelBuffer, timestamp: timestamp)

            // Update on main actor
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // Check if frame was actually processed (not throttled)
                let wasProcessed = timestamp - self.lastPoseProcessTime >= self.minPoseInterval

                // Only update state if PoseService actually processed (not throttled)
                // When processSync returns nil, it could be:
                // 1. Throttled (too soon since last process)
                // 2. No pixel buffer
                // 3. Vision found no pose
                // We only want to update for cases 2 & 3, not case 1 (throttle)

                // If we got a result (pose found), definitely update
                if let obs = poseObs {
                    self.latestPoseObservation = obs
                    self.lastPoseProcessTime = timestamp

                    let quality: TrackingQuality = self.computeTrackingQuality(
                        poseObservation: obs,
                        hasPixelBuffer: hasPixelBuffer
                    )
                    self.trackingQuality = quality

                    print("✓ Pose detected: \(obs.keypoints.count) keypoints, confidence: \(obs.confidence)")

                    // Sample depth at keypoint positions if available
                    var depthSamples: [DepthAtPoint]? = nil
                    if let depthMap = depthMap, cameraIntrinsics != nil {
                        // Extract keypoint positions to sample
                        let positions = obs.keypoints.map { $0.position }
                        let frameForDepth = InputFrame(
                            timestamp: timestamp,
                            pixelBuffer: nil,  // Don't need pixel buffer for depth sampling
                            depthMap: depthMap,
                            cameraIntrinsics: cameraIntrinsics
                        )
                        depthSamples = self.depthService.sampleDepth(at: positions, from: frameForDepth)
                    }

                    // Fuse pose with depth to create real PoseSample
                    let sample = self.poseDepthFusion.fuse(
                        pose: obs,
                        depthSamples: depthSamples,
                        confidence: confidence,
                        cameraIntrinsics: cameraIntrinsics
                    )
                    self.latestSample = sample

                    // Debug: Log sample positions to verify they're not zero
                    print("📊 Sample positions - Head: \(sample.headPosition), Shoulders: \(sample.shoulderMidpoint)")
                    print("📊 Sample mode: \(sample.depthMode.rawValue), quality: \(sample.trackingQuality.rawValue)")

                    // Compute metrics from sample
                    let metrics = self.metricsEngine.compute(from: sample, baseline: self.baseline)
                    self.latestMetrics = metrics

                    print("📈 Metrics - Forward: \(metrics.forwardCreep), Head: \(metrics.headDrop), Lean: \(metrics.lateralLean), Twist: \(metrics.twist)")
                    if self.baseline == nil {
                        print("⚠️ No baseline set - metrics will be zero. Implement calibration (Ticket 5.1) to get real metrics.")
                    }
                }
                // If no pixel buffer, update to lost
                else if !hasPixelBuffer {
                    self.latestPoseObservation = nil
                    self.lastPoseProcessTime = timestamp
                    self.trackingQuality = .lost
                    print("✗ No pose detected (no pixel buffer)")

                    let sample = PoseSample(
                        timestamp: timestamp,
                        depthMode: mode,
                        headPosition: .zero,
                        shoulderMidpoint: .zero,
                        leftShoulder: .zero,
                        rightShoulder: .zero,
                        torsoAngle: 0,
                        headForwardOffset: 0,
                        shoulderTwist: 0,
                        trackingQuality: .lost
                    )
                    self.latestSample = sample

                    // Compute metrics (will be zeros without baseline)
                    let metrics = self.metricsEngine.compute(from: sample, baseline: self.baseline)
                    self.latestMetrics = metrics
                }
                // If frame was processed but no pose found (person left frame)
                else if wasProcessed && hasPixelBuffer {
                    self.latestPoseObservation = nil
                    self.lastPoseProcessTime = timestamp
                    self.trackingQuality = .lost
                    print("✗ No pose detected (person not in frame)")

                    let sample = PoseSample(
                        timestamp: timestamp,
                        depthMode: mode,
                        headPosition: .zero,
                        shoulderMidpoint: .zero,
                        leftShoulder: .zero,
                        rightShoulder: .zero,
                        torsoAngle: 0,
                        headForwardOffset: 0,
                        shoulderTwist: 0,
                        trackingQuality: .lost
                    )
                    self.latestSample = sample

                    // Compute metrics (will be zeros without baseline)
                    let metrics = self.metricsEngine.compute(from: sample, baseline: self.baseline)
                    self.latestMetrics = metrics
                }
                // Otherwise it was throttled - keep previous state
                // Don't spam logs or update state for throttled frames

                // Mark as done processing
                self.isPoseProcessing = false
            }
        }
    }

    private func computeTrackingQuality(poseObservation: PoseObservation?, hasPixelBuffer: Bool) -> TrackingQuality {
        // No pixel buffer = lost
        guard hasPixelBuffer else {
            print("⚠️ TrackingQuality: lost (no pixel buffer)")
            return .lost
        }

        // No pose detected = lost
        guard let observation = poseObservation else {
            print("⚠️ TrackingQuality: lost (no pose observation)")
            return .lost
        }

        // Check if we have the critical keypoints (shoulders and head)
        let leftShoulder = observation.keypoints.first { $0.joint == .leftShoulder }
        let rightShoulder = observation.keypoints.first { $0.joint == .rightShoulder }
        let nose = observation.keypoints.first { $0.joint == .nose }
        let leftEye = observation.keypoints.first { $0.joint == .leftEye }
        let rightEye = observation.keypoints.first { $0.joint == .rightEye }

        // Use lower confidence thresholds (0.3) to match real-world Vision detection
        let hasLeftShoulder = (leftShoulder?.confidence ?? 0) > 0.3
        let hasRightShoulder = (rightShoulder?.confidence ?? 0) > 0.3
        let hasHead = (nose?.confidence ?? 0) > 0.3 || (leftEye?.confidence ?? 0) > 0.3 || (rightEye?.confidence ?? 0) > 0.3

        // Detailed logging for debugging
        print("🔍 Keypoint details:")
        print("  Left shoulder: \(leftShoulder != nil ? String(format: "%.2f", leftShoulder!.confidence) : "missing")")
        print("  Right shoulder: \(rightShoulder != nil ? String(format: "%.2f", rightShoulder!.confidence) : "missing")")
        print("  Nose: \(nose != nil ? String(format: "%.2f", nose!.confidence) : "missing")")
        print("  Left eye: \(leftEye != nil ? String(format: "%.2f", leftEye!.confidence) : "missing")")
        print("  Right eye: \(rightEye != nil ? String(format: "%.2f", rightEye!.confidence) : "missing")")
        print("  Has critical keypoints: L_shoulder=\(hasLeftShoulder), R_shoulder=\(hasRightShoulder), head=\(hasHead)")

        // Best case: both shoulders and head
        if hasLeftShoulder && hasRightShoulder && hasHead {
            let quality: TrackingQuality = observation.confidence > 0.7 ? .good : .degraded
            print("✅ TrackingQuality: \(quality) (both shoulders + head)")
            return quality
        }

        // Good enough: one shoulder and head (sufficient for posture tracking)
        if (hasLeftShoulder || hasRightShoulder) && hasHead {
            let quality: TrackingQuality = observation.confidence > 0.7 ? .good : .degraded
            print("✅ TrackingQuality: \(quality) (one shoulder + head)")
            return quality
        }

        // Some keypoints but not the critical ones
        if observation.keypoints.count >= 3 {
            print("⚠️ TrackingQuality: degraded (\(observation.keypoints.count) keypoints but missing shoulders/head)")
            return .degraded
        }

        print("⚠️ TrackingQuality: lost (insufficient keypoints)")
        return .lost
    }

    private func updateFPS(timestamp: TimeInterval) {
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
                fps = Float(frameTimestamps.count - 1) / Float(duration)
            }
        }
    }
}
