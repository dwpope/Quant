import XCTest
import PostureLogic
import simd
@testable import Quant

/// "Both wrong" used to record a recording tag (reading, typing, stretching…) as the true class.
/// It now records one of Jev's five classes. Records already on a phone still hold the old
/// strings, and they must keep loading.
///
/// The trap this guards, found 2026-09-29: the store decoded a whole day with one `try?`. After a
/// naive type change, one record holding `"reading"` would make the day load empty, and the next
/// capture's write would replace the file with just itself. A day of captures gone, silently.
@MainActor
final class JevComparisonLegacyDecodeTests: XCTestCase {

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var todayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private var fileURL: URL { documents.appendingPathComponent("jev-comparisons-\(todayKey).json") }

    /// Files a corrupt day was moved to, so a test can find and remove them.
    private func setAsideFiles() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []
        return names
            .filter { $0.hasPrefix("jev-comparisons-\(todayKey).unreadable-") }
            .map { documents.appendingPathComponent($0) }
    }

    override func setUpWithError() throws {
        JevComparisonStore.flushPendingWrites()
        try? FileManager.default.removeItem(at: fileURL)
        setAsideFiles().forEach { try? FileManager.default.removeItem(at: $0) }
    }

    override func tearDownWithError() throws {
        JevComparisonStore.flushPendingWrites()
        try? FileManager.default.removeItem(at: fileURL)
        setAsideFiles().forEach { try? FileManager.default.removeItem(at: $0) }
    }

    // MARK: - Fixtures

    private func makeRecord(trueClass: JevClass? = nil) -> JevComparisonRecord {
        let baseline = Baseline(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0), headPosition: SIMD3<Float>(0.5, 0.8, 0),
            torsoAngle: 3, shoulderTwist: 1, shoulderWidth: 0.2, depthAvailable: false,
            neckHeight: 0.35)
        let features = JevFeatures.make(
            sample: PoseSample(
                timestamp: 0, depthMode: .twoDOnly,
                headPosition: SIMD3<Float>(0.5, 0.8, 0), shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
                leftShoulder: SIMD3<Float>(0.4, 0.6, 0), rightShoulder: SIMD3<Float>(0.6, 0.6, 0),
                torsoAngle: 5, headForwardOffset: 0, shoulderTwist: 0,
                shoulderWidthRaw: 0.3, trackingQuality: .good),
            metrics: RawMetrics(
                timestamp: 0, forwardCreep: -0.09, headDrop: 0.01, shoulderRounding: 1,
                lateralLean: 0.05, twist: 1, movementLevel: 0, headMovementPattern: .still,
                lateralLeanSigned: 0.05, twistSigned: 1),
            baseline: baseline)!
        return JevComparisonRecord(
            id: UUID(), capturedAt: Date(), features: features, baseline: baseline,
            thresholdState: .drifting(since: 100),
            jev: JevVerdict(posture: "lean", confidence: 0.6, probabilities: ["lean": 0.6],
                            model: "jev-1.13.0"),
            jevError: nil,
            userVerdict: trueClass == nil ? nil : .bothWrong,
            trueClass: trueClass)
    }

    /// A record exactly as an older build wrote it: the current encoding, with `trueClass` set
    /// to one of the old recording-tag strings.
    private func legacyRecordObject(trueClass legacy: String) throws -> [String: Any] {
        let data = try JSONEncoder().encode(makeRecord())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["userVerdict"] = "bothWrong"
        object["trueClass"] = legacy
        return object
    }

    private func writeToday(_ array: [Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: array)
        try data.write(to: fileURL, options: .atomic)
    }

    private func onDiskArray() throws -> [Any] {
        let data = try Data(contentsOf: fileURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])
    }

    // MARK: - One record

    /// Every string the old "both wrong" menu could have saved. None is a Jev class, including
    /// the two that look like one: "goodPosture" and "slouching" were often the nearest pick for
    /// a lean or a swivel, so translating them would launder a guess into a label.
    func test_legacyTrueClass_decodesAsNil_andTheRestOfTheRecordSurvives() throws {
        let legacy = ["goodPosture", "slouching", "reading", "typing", "stretching", "absent"]
        for value in legacy {
            let object = try legacyRecordObject(trueClass: value)
            let data = try JSONSerialization.data(withJSONObject: object)

            let record = try JSONDecoder().decode(JevComparisonRecord.self, from: data)

            XCTAssertNil(record.trueClass, "legacy \"\(value)\" should decode as nil")
            XCTAssertEqual(record.userVerdict, .bothWrong,
                           "the judgement stays, flagging the record for re-labelling")
            XCTAssertEqual(record.jev?.posture, "lean")
            XCTAssertEqual(record.id.uuidString, object["id"] as? String)
        }
    }

    func test_jevClassTrueClass_roundTrips_asTheProxysName() throws {
        let data = try JSONEncoder().encode(makeRecord(trueClass: .chairSwivel))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["trueClass"] as? String, "chair_swivel")

        let decoded = try JSONDecoder().decode(JevComparisonRecord.self, from: data)
        XCTAssertEqual(decoded.trueClass, .chairSwivel)
    }

    // MARK: - A whole day on disk

    func test_aDayWithALegacyRecord_loadsEveryRecord() throws {
        let current = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(makeRecord(trueClass: .slouch)))
        try writeToday([try legacyRecordObject(trueClass: "reading"), current])

        let store = JevComparisonStore()

        XCTAssertEqual(store.comparisons.count, 2)
        XCTAssertEqual(store.comparisons.filter { $0.trueClass == nil }.count, 1)
        XCTAssertEqual(store.comparisons.filter { $0.trueClass == .slouch }.count, 1)
    }

    /// Not only legacy labels: any record this build can't read is kept, byte for byte in
    /// meaning, and written back alongside the rest.
    func test_oneUnreadableRecord_neverEmptiesTheFile() throws {
        let good = try JSONSerialization.jsonObject(with: JSONEncoder().encode(makeRecord()))
        let unreadable: [String: Any] = ["id": "not-a-uuid", "from": "a future build"]
        try writeToday([good, unreadable])

        let store = JevComparisonStore()
        XCTAssertEqual(store.comparisons.count, 1, "the readable record loads")

        store.add(makeRecord())
        JevComparisonStore.flushPendingWrites()

        let onDisk = try onDiskArray()
        XCTAssertEqual(onDisk.count, 3, "both originals and the new capture")
        XCTAssertTrue(onDisk.contains { ($0 as? [String: Any])?["from"] as? String == "a future build" },
                      "the unreadable record is written back untouched")
    }

    /// If the file isn't even a JSON array, it is moved aside before anything is written, so the
    /// next capture can't replace it.
    func test_anUnparseableFile_isSetAside_notOverwritten() throws {
        let garbage = Data("not json at all".utf8)
        try garbage.write(to: fileURL, options: .atomic)

        let store = JevComparisonStore()
        XCTAssertTrue(store.comparisons.isEmpty)

        store.add(makeRecord())
        JevComparisonStore.flushPendingWrites()

        let setAside = setAsideFiles()
        XCTAssertEqual(setAside.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(setAside.first)), garbage)
        XCTAssertEqual(try onDiskArray().count, 1, "today's file now holds only the new capture")
    }

    // MARK: - The vocabulary

    /// The five classes are the proxy's rubric keys. Read from the rubric itself, so renaming a
    /// class on one side and not the other fails here rather than in the dataset.
    func test_jevClasses_matchTheProxysRubric() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repo.appendingPathComponent("jev-proxy/src/classify.ts"),
                                encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "export const POSTURE_CRITERIA"))
        let end = try XCTUnwrap(source.range(of: "\n};", range: start.upperBound..<source.endIndex))
        let block = source[start.upperBound..<end.lowerBound]

        let keys = block.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("  "), !line.hasPrefix("   "), trimmed.hasSuffix(":") else { return nil }
            return String(trimmed.dropLast())
        }

        XCTAssertEqual(keys, JevClass.allCases.map(\.rawValue))
    }
}
