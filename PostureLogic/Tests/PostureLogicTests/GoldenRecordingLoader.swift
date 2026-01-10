import Foundation
@testable import PostureLogic

/// Utility to load golden recordings from disk for testing
struct GoldenRecordingLoader {

    enum LoadError: Error {
        case fileNotFound(String)
        case decodingFailed(String, Error)
    }

    /// Loads a golden recording from the test bundle or project root
    static func load(_ filename: String) throws -> RecordedSession {
        // Try multiple locations
        let possiblePaths = [
            // Test Resources directory
            findInTestResources(filename),
            // Project root GoldenRecordings
            findInProjectRoot(filename)
        ].compactMap { $0 }

        guard let filePath = possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw LoadError.fileNotFound("Could not find \(filename) in any expected location")
        }

        let url = URL(fileURLWithPath: filePath)
        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let session = try decoder.decode(RecordedSession.self, from: data)
            return session
        } catch {
            throw LoadError.decodingFailed(filename, error)
        }
    }

    private static func findInTestResources(_ filename: String) -> String? {
        let testBundle = Bundle(for: GoldenRecordingTests.self)
        let testDir = testBundle.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let resourcePath = testDir
            .appendingPathComponent("PostureLogicTests")
            .appendingPathComponent("Resources")
            .appendingPathComponent(filename)
            .path

        return FileManager.default.fileExists(atPath: resourcePath) ? resourcePath : nil
    }

    private static func findInProjectRoot(_ filename: String) -> String? {
        let testBundle = Bundle(for: GoldenRecordingTests.self)
        let projectRoot = testBundle.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let goldenPath = projectRoot
            .appendingPathComponent("GoldenRecordings")
            .appendingPathComponent(filename)
            .path

        return FileManager.default.fileExists(atPath: goldenPath) ? goldenPath : nil
    }

    // MARK: - Convenience Methods

    static func loadGoodPosture5Min() throws -> RecordedSession {
        try load("good_posture_5min.json")
    }

    static func loadGradualSlouch() throws -> RecordedSession {
        try load("gradual_slouch.json")
    }

    static func loadReadingVsTyping() throws -> RecordedSession {
        try load("reading_vs_typing.json")
    }

    static func loadDepthFallback() throws -> RecordedSession {
        try load("depth_fallback_scenario.json")
    }
}
