import Combine
import Foundation

@MainActor public class Pipeline {
    // MARK: - Published Properties

    @Published public var latestSample: PoseSample?
    @Published public var currentMode: DepthMode = .twoDOnly
    @Published public var depthConfidence: DepthConfidence = .unavailable
    @Published public var trackingQuality: TrackingQuality = .lost
    @Published public var fps: Float = 0.0

    // MARK: - Private Properties

    private var subscriptions = Set<AnyCancellable>()
    private var poseService = PoseService()
    private var depthService = DepthService()
    private var modeSwitcher: ModeSwitcher

    // Latest pose observation
    private var latestPoseObservation: PoseObservation?

    // Pose processing state
    private var isPoseProcessing = false
    private var poseProcessingDropped = 0

    // FPS calculation
    private var lastFrameTime: TimeInterval = 0
    private var frameTimestamps: [TimeInterval] = []

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

        // Extract only what we need to avoid retaining the entire ARFrame
        let timestamp = frame.timestamp
        let hasPixelBuffer = frame.pixelBuffer != nil

        // Process pose asynchronously
        Task { [weak self] in
            guard let self = self else { return }

            // Extract pose keypoints using Vision
            let poseObservation = await self.poseService.process(frame: frame)

            // Update latest pose observation
            await MainActor.run {
                self.latestPoseObservation = poseObservation

                // Determine tracking quality based on pose detection
                let quality: TrackingQuality = self.computeTrackingQuality(
                    poseObservation: poseObservation,
                    hasPixelBuffer: hasPixelBuffer
                )
                self.trackingQuality = quality

                // Log pose detection results for debugging
                if let obs = poseObservation {
                    print("✓ Pose detected: \(obs.keypoints.count) keypoints, confidence: \(obs.confidence)")
                } else {
                    print("✗ No pose detected")
                }

                // Create pose sample (will be enhanced in Ticket 2.2 with actual pose fusion)
                self.latestSample = PoseSample(
                    timestamp: timestamp,
                    depthMode: mode,
                    headPosition: .zero,
                    shoulderMidpoint: .zero,
                    leftShoulder: .zero,
                    rightShoulder: .zero,
                    torsoAngle: 0,
                    headForwardOffset: 0,
                    shoulderTwist: 0,
                    trackingQuality: quality
                )

                // Mark as done processing
                self.isPoseProcessing = false
            }
        }
    }

    private func computeTrackingQuality(poseObservation: PoseObservation?, hasPixelBuffer: Bool) -> TrackingQuality {
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

        // Need at least shoulders and head for good tracking
        if hasLeftShoulder && hasRightShoulder && hasHead {
            return observation.confidence > 0.7 ? .good : .degraded
        }

        // Some keypoints but not enough
        if observation.keypoints.count >= 3 {
            return .degraded
        }

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
