import XCTest

/// Guards the one-clock rule by reading the source (2026-10-05).
///
/// Every time the app stores or compares is seconds since 1970. Frames are converted from the
/// uptime clock once, by `FrameClock`, where they're captured. Mixing clocks compiles fine, since
/// they're all `TimeInterval`, so these checks are what stop a fourth clock bug:
/// - nothing reads the uptime clock except `FrameClock`;
/// - nothing uses the 2001 reference date (`SipInsights` and `NudgeInsights` did, against sips
///   stored on the uptime clock or since 1970);
/// - every camera service that builds frames converts their times with `FrameClock`.
final class ClockConventionTests: XCTestCase {

    /// The repository root, from this file's own path.
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PostureLogicTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // PostureLogic
            .deletingLastPathComponent()   // repository root
    }

    private var sourceFolders: [URL] {
        ["PostureLogic/Sources", "Quant", "QuantWatch Watch App"].map { root.appendingPathComponent($0) }
    }

    /// Every Swift source file, path relative to the root, with its text.
    private func sources() throws -> [(path: String, text: String)] {
        var out: [(String, String)] = []
        for folder in sourceFolders {
            let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
            while let url = files?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                let path = url.path.replacingOccurrences(of: root.path + "/", with: "")
                out.append((path, try String(contentsOf: url, encoding: .utf8)))
            }
        }
        return out
    }

    func test_theSourcesAreFound() throws {
        let files = try sources()
        XCTAssertGreaterThan(files.count, 50)
        XCTAssertTrue(files.contains { $0.path.hasSuffix("FrameClock.swift") })
    }

    func test_onlyFrameClock_readsTheUptimeClock() throws {
        let uptimeClocks = ["systemUptime", "CACurrentMediaTime", "mach_absolute_time",
                            "mach_continuous_time", "CLOCK_UPTIME_RAW", "CLOCK_MONOTONIC",
                            "uptimeNanoseconds"]
        for file in try sources() where !file.path.hasSuffix("FrameClock.swift") {
            for clock in uptimeClocks {
                XCTAssertFalse(file.text.contains(clock), "\(file.path) reads \(clock): go through FrameClock")
            }
        }
    }

    func test_nothingUsesTheReferenceDate() throws {
        for file in try sources() {
            XCTAssertFalse(file.text.contains("timeIntervalSinceReferenceDate"),
                           "\(file.path): times are seconds since 1970")
        }
    }

    /// The camera services hand the pipeline its frames. Each frame time they read (an ARFrame's
    /// `timestamp`, a sample buffer's presentation time) has to go through FrameClock on the
    /// same line.
    func test_everyCameraFrameTime_isConverted() throws {
        let frameTimes = ["frame.timestamp", "CMSampleBufferGetPresentationTimeStamp"]
        var checked = 0
        for file in try sources() where file.path.hasPrefix("Quant/Services/") {
            for line in file.text.split(separator: "\n") where frameTimes.contains(where: line.contains) {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                checked += 1
                XCTAssertTrue(line.contains("FrameClock"), "\(file.path): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertGreaterThanOrEqual(checked, 3, "the three camera services")
    }
}
