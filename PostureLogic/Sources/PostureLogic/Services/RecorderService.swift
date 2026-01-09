import Foundation

/// Records streams of PoseSample to memory for later analysis, testing, and golden recording creation
public struct RecorderService: RecorderServiceProtocol {
    public var debugState: [String: Any] {
        [
            "isRecording": _isRecording,
            "sampleCount": samples.count,
            "tagCount": tags.count,
            "duration": recordingDuration,
            "estimatedSizeBytes": estimatedMemorySize
        ]
    }

    public var isRecording: Bool {
        return _isRecording
    }

    private var _isRecording = false
    private var startTime: Date?
    private var samples: [PoseSample] = []
    private var tags: [Tag] = []
    private var sessionId: UUID = UUID()

    // Configuration
    private let thresholds: PostureThresholds

    public init(thresholds: PostureThresholds = PostureThresholds()) {
        self.thresholds = thresholds
    }

    // MARK: - Recording Control

    public mutating func startRecording() {
        guard !_isRecording else {
            // Already recording, ignore
            return
        }

        _isRecording = true
        startTime = Date()
        sessionId = UUID()
        samples = []
        tags = []
    }

    public mutating func stopRecording() -> RecordedSession {
        _isRecording = false

        let endTime = Date()
        let actualStartTime = startTime ?? endTime

        // Create session metadata
        let metadata = SessionMetadata(
            deviceModel: getDeviceModel(),
            depthAvailable: hasDepthData(),
            thresholds: thresholds
        )

        let session = RecordedSession(
            id: sessionId,
            startTime: actualStartTime,
            endTime: endTime,
            samples: samples,
            tags: tags,
            metadata: metadata
        )

        // Clear state
        startTime = nil
        samples = []
        tags = []

        return session
    }

    // MARK: - Recording Data

    public mutating func record(sample: PoseSample) {
        guard _isRecording else { return }
        samples.append(sample)
    }

    public mutating func addTag(_ tag: Tag) {
        guard _isRecording else { return }
        tags.append(tag)
    }

    // MARK: - Helpers

    private var recordingDuration: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    /// Estimate memory size for current recording
    /// Used to warn if approaching memory limits
    private var estimatedMemorySize: Int {
        // Rough estimate: ~200 bytes per sample (conservative)
        // Each PoseSample has:
        // - timestamp: 8 bytes
        // - 4x SIMD3<Float>: 4 * 12 = 48 bytes
        // - 3x Float: 12 bytes
        // - enums: ~8 bytes
        // Total: ~76 bytes raw data + overhead
        let bytesPerSample = 200
        let bytesPerTag = 100

        return (samples.count * bytesPerSample) + (tags.count * bytesPerTag)
    }

    private func hasDepthData() -> Bool {
        // Check if any samples used depth fusion mode
        return samples.contains { $0.depthMode == .depthFusion }
    }

    private func getDeviceModel() -> String {
        #if os(iOS)
        // On iOS, try to get actual device model
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? "Unknown iOS Device" : identifier
        #elseif os(macOS)
        return "macOS"
        #else
        return "Unknown"
        #endif
    }
}

// MARK: - JSON Export Extension

extension RecordedSession {
    /// Export session to JSON data
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(self)
    }

    /// Export session to JSON file
    public func exportToFile(url: URL) throws {
        let data = try exportJSON()
        try data.write(to: url)
    }

    /// Load session from JSON data
    public static func loadJSON(from data: Data) throws -> RecordedSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(RecordedSession.self, from: data)
    }

    /// Load session from JSON file
    public static func loadFromFile(url: URL) throws -> RecordedSession {
        let data = try Data(contentsOf: url)
        return try loadJSON(from: data)
    }

    /// Estimate JSON file size in bytes
    public var estimatedJSONSize: Int {
        guard let data = try? exportJSON() else { return 0 }
        return data.count
    }

    /// Estimate JSON file size in megabytes
    public var estimatedJSONSizeMB: Double {
        Double(estimatedJSONSize) / 1_048_576.0  // 1024 * 1024
    }
}
