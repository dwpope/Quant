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

    // Recording state
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var tagCount: Int = 0

    // MARK: - Private Properties

    private let arService = ARSessionService()
    private lazy var pipeline: Pipeline = {
        Pipeline(provider: arService)
    }()
    private var recorder = RecorderService()
    private var recordingStartTime: Date?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupPipeline()
    }

    // MARK: - Private Methods

    private func setupPipeline() {
        // Subscribe to pipeline updates
        pipeline.$latestSample
            .sink { [weak self] sample in
                if let sample = sample {
                    print("Sample processed: \(sample.timestamp)")

                    // Record sample if recording
                    self?.recordSampleIfNeeded(sample)
                }
            }
            .store(in: &cancellables)

        // Bind pipeline properties to published properties for UI
        pipeline.$currentMode
            .assign(to: &$currentMode)

        pipeline.$depthConfidence
            .assign(to: &$depthConfidence)

        pipeline.$trackingQuality
            .assign(to: &$trackingQuality)

        pipeline.$fps
            .assign(to: &$fps)
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

    // MARK: - Recording Methods

    func startRecording() {
        recorder.startRecording()
        recordingStartTime = Date()
        isRecording = true
        tagCount = 0
        print("📹 Started recording session")
    }

    func stopRecording() -> RecordedSession {
        let session = recorder.stopRecording()
        isRecording = false
        recordingDuration = 0
        recordingStartTime = nil
        print("📹 Stopped recording. Captured \(session.samples.count) samples, \(session.tags.count) tags")
        return session
    }

    func addRecordingTag(_ tag: Tag) {
        recorder.addTag(tag)
        tagCount = recorder.debugState["tagCount"] as? Int ?? 0
        print("🏷️ Added tag: \(tag.label.rawValue) (\(tag.source.rawValue))")
    }

    func exportRecording(to url: URL) throws {
        let session = stopRecording()
        try session.exportToFile(url: url)
        print("💾 Exported recording to \(url.lastPathComponent)")
    }

    private func recordSampleIfNeeded(_ sample: PoseSample) {
        guard isRecording else { return }

        recorder.record(sample: sample)

        // Update recording duration
        if let startTime = recordingStartTime {
            recordingDuration = Date().timeIntervalSince(startTime)
        }
    }
}
