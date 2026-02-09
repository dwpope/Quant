import Combine
import Foundation

public class Pipeline {
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

    // FPS calculation
    private var lastFrameTime: TimeInterval = 0
    private var frameTimestamps: [TimeInterval] = []

    // Tracking quality hysteresis
    private var previousTrackingQuality: TrackingQuality = .lost

    // Frame processing control
    private var activePoseProcessing = 0
    private let maxConcurrentPoseProcessing = 2
    private let processingQueue = DispatchQueue(label: "com.quant.pipeline.processing")

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

        // Check if we can process another frame (limit concurrent processing to prevent frame retention)
        var shouldProcess = false
        processingQueue.sync {
            if activePoseProcessing < maxConcurrentPoseProcessing {
                activePoseProcessing += 1
                shouldProcess = true
            }
        }

        guard shouldProcess else {
            // Skip this frame - too many frames already being processed
            return
        }

        // Extract frame data to avoid retaining the entire InputFrame
        let timestamp = frame.timestamp
        let hasPixelBuffer = frame.pixelBuffer != nil

        // Process pose asynchronously
        Task { [weak self, poseService, frame] in
            defer {
                // Always decrement counter when done
                self?.processingQueue.sync {
                    self?.activePoseProcessing -= 1
                }
            }

            guard let self = self else { return }

            // Extract pose keypoints using Vision
            let poseObservation = await poseService.process(frame: frame)

            // Determine tracking quality based on pose detection
            let quality: TrackingQuality = self.computeTrackingQuality(
                poseObservation: poseObservation,
                hasPixelBuffer: hasPixelBuffer
            )

            // Create pose sample (will be enhanced in Ticket 2.2 with actual pose fusion)
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
                trackingQuality: quality
            )

            // Update published properties on main thread
            await MainActor.run {
                self.latestPoseObservation = poseObservation
                self.trackingQuality = quality
                self.latestSample = sample
                self.previousTrackingQuality = quality
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

        let keypointCount = observation.keypoints.count

        // Apply hysteresis to prevent rapid state changes
        // Use different thresholds depending on current state to create "buffer zones"

        // Need at least shoulders and head for good tracking
        if hasLeftShoulder && hasRightShoulder && hasHead {
            // Determine confidence threshold based on previous state (hysteresis)
            let confidenceThreshold: Float
            switch previousTrackingQuality {
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
        switch previousTrackingQuality {
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
