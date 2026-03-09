import Foundation

/// Records posture samples into a ``RecordedSession``.
///
/// Thread-safety: designed for single-threaded use (call from main actor or a single task).
/// JSON export target: <5 MB for 5 minutes at 10 FPS (~3 000 samples).
public final class RecorderService: RecorderServiceProtocol {

    // MARK: - State

    private var sessionID: UUID?
    private var sessionStartTime: Date?
    private var sessionMetadata: SessionMetadata?
    private var samples: [PoseSample] = []
    private var tags: [Tag] = []

    // MARK: - Public read-only

    public private(set) var isRecording: Bool = false

    public var sampleCount: Int { samples.count }

    // MARK: - DebugDumpable

    public var debugState: [String: Any] {
        var state: [String: Any] = [
            "isRecording": isRecording,
            "sampleCount": samples.count
        ]
        if let id = sessionID {
            state["sessionID"] = id.uuidString
        }
        return state
    }

    // MARK: - Init

    public init() {}

    // MARK: - Lifecycle

    @discardableResult
    public func startRecording(metadata: SessionMetadata) -> Bool {
        guard !isRecording else { return false }

        sessionID = UUID()
        sessionStartTime = Date()
        sessionMetadata = metadata
        samples = []
        tags = []
        isRecording = true
        return true
    }

    public func record(sample: PoseSample) {
        guard isRecording else { return }
        samples.append(sample)
    }

    public func addTag(_ tag: Tag) {
        guard isRecording else { return }
        tags.append(tag)
    }

    public func stopRecording() -> RecordedSession? {
        guard isRecording,
              let id = sessionID,
              let startTime = sessionStartTime,
              let metadata = sessionMetadata else {
            return nil
        }

        let session = RecordedSession(
            id: id,
            startTime: startTime,
            endTime: Date(),
            samples: samples,
            tags: tags,
            metadata: metadata
        )

        // Reset state
        isRecording = false
        sessionID = nil
        sessionStartTime = nil
        sessionMetadata = nil
        samples = []
        tags = []

        return session
    }
}
