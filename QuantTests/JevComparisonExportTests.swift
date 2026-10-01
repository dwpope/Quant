import XCTest
import PostureLogic
import simd
@testable import Quant

/// Getting the dataset off the phone.
///
/// Without this the records accumulate in the app's private container and step 3c cannot
/// measure anything while Dave is testing remotely — the sip training path has had a ShareLink
/// export for months and the Jev path had none.
@MainActor
final class JevComparisonExportTests: XCTestCase {

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private var yesterday: Date { Date().addingTimeInterval(-86_400) }

    /// Every day's file, not just today's: the export now reads them all, so a file left by any
    /// other test or day would leak into these counts.
    private func removeAllDayFiles() {
        JevComparisonStore.flushPendingWrites()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []
        for name in names where name.hasPrefix("jev-comparisons-") {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent(name))
        }
    }

    override func setUpWithError() throws { removeAllDayFiles() }
    override func tearDownWithError() throws { removeAllDayFiles() }

    /// Writes a day file the way the store does: a JSON array of records.
    private func writeDayFile(_ name: String, _ objects: [Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: objects)
        try data.write(to: documents.appendingPathComponent(name), options: .atomic)
    }

    private func object(_ record: JevComparisonRecord) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
    }

    private func exportedIDs(_ store: JevComparisonStore) throws -> [String] {
        let url = try store.exportJSONL()
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                let json = try XCTUnwrap(
                    try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
                return try XCTUnwrap(json["id"] as? String)
            }
    }

    private func makeRecord(adjudicated: Bool, at capturedAt: Date = Date()) -> JevComparisonRecord {
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
            id: UUID(), capturedAt: capturedAt, features: features, baseline: baseline,
            thresholdState: .bad(since: 12),
            jev: JevVerdict(posture: "chair_swivel", confidence: 0.81,
                            probabilities: ["chair_swivel": 0.81], model: "jev-1.13.0"),
            jevError: nil,
            userVerdict: adjudicated ? .jevWasRight : nil)
    }

    func test_export_writesOneLinePerRecord() throws {
        let store = JevComparisonStore()
        store.add(makeRecord(adjudicated: true))
        store.add(makeRecord(adjudicated: false))

        let url = try store.exportJSONL()
        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)

        XCTAssertEqual(lines.count, 2)
        for line in lines {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8)),
                             "every line must be independently parseable")
        }
    }

    /// Unadjudicated records are exported too. They lack ground truth, but they still record
    /// what both sides answered at the same moment, which measures agreement — and filtering
    /// them out here would silently discard evidence 3c might want.
    func test_export_includesRecordsWithNoAdjudication() throws {
        let store = JevComparisonStore()
        store.add(makeRecord(adjudicated: false))

        let url = try store.exportJSONL()
        let line = try XCTUnwrap(try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n").first)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])

        XCTAssertNil(json["userVerdict"])
        XCTAssertNotNil(json["jev"])
    }

    /// The payload and the baseline must survive the round trip, or the export is unusable:
    /// every metric is a delta from that baseline.
    func test_export_carriesTheFeaturesAndTheBaseline() throws {
        let store = JevComparisonStore()
        store.add(makeRecord(adjudicated: true))

        let url = try store.exportJSONL()
        let line = try XCTUnwrap(try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n").first)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])

        let features = try XCTUnwrap(json["features"] as? [String: Any])
        XCTAssertNotNil(features["lateral_lean_in_shoulder_widths"])
        XCTAssertNotNil(json["baseline"])
        XCTAssertEqual(json["userVerdict"] as? String, "jevWasRight")
    }

    func test_export_namesTheFileByDate() throws {
        let store = JevComparisonStore()
        store.add(makeRecord(adjudicated: true))

        let name = try store.exportJSONL().lastPathComponent

        XCTAssertTrue(name.hasPrefix("jev-comparisons-"), name)
        XCTAssertTrue(name.hasSuffix(".jsonl"), name)
    }

    func test_export_ofAnEmptyStoreProducesAnEmptyFile() throws {
        let url = try JevComparisonStore().exportJSONL()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "")
    }

    // MARK: - Every day, not just today (2026-10-01)
    //
    // The export used to hold only today's records, so a session that ran past midnight could
    // not leave the phone: Documents has no file sharing, and the only way out was Xcode's
    // container download on a Mac.

    func test_export_includesYesterdaysRecords_andTodays() throws {
        let old = makeRecord(adjudicated: true, at: yesterday)
        try writeDayFile("jev-comparisons-\(dayKey(yesterday)).json", [try object(old)])
        let store = JevComparisonStore()
        let new = makeRecord(adjudicated: false)
        store.add(new)

        XCTAssertEqual(try exportedIDs(store), [old.id.uuidString, new.id.uuidString],
                       "both days, oldest first")
    }

    /// The same tolerant rules as loading today: one bad record costs only itself.
    func test_export_skipsAnUnreadableRecordInAnOldFile() throws {
        let good = makeRecord(adjudicated: true, at: yesterday)
        try writeDayFile("jev-comparisons-\(dayKey(yesterday)).json",
                         [["id": "not-a-uuid", "from": "a future build"], try object(good)])
        let store = JevComparisonStore()

        XCTAssertEqual(try exportedIDs(store), [good.id.uuidString])
    }

    /// A file set aside as unparseable is evidence for a human, not data for the export.
    func test_export_skipsSetAsideFiles() throws {
        let asideRecord = makeRecord(adjudicated: true, at: yesterday)
        try writeDayFile("jev-comparisons-\(dayKey(yesterday)).unreadable-1727740800.json",
                         [try object(asideRecord)])
        let store = JevComparisonStore()

        XCTAssertEqual(try exportedIDs(store), [])
    }

    /// A session that runs past midnight holds yesterday's records in memory and saves them to
    /// today's file too. Each record is exported once, in its newest form.
    func test_export_hasNoDuplicates_andKeepsTheNewestJudgement() throws {
        let carried = makeRecord(adjudicated: false, at: yesterday)
        let onlyYesterday = makeRecord(adjudicated: true, at: yesterday.addingTimeInterval(60))
        try writeDayFile("jev-comparisons-\(dayKey(yesterday)).json",
                         [try object(carried), try object(onlyYesterday)])
        // Today's file already holds the carried record, now judged.
        var judged = carried
        judged.userVerdict = .bothWrong
        judged.trueClass = .slouch
        try writeDayFile("jev-comparisons-\(dayKey(Date())).json", [try object(judged)])
        let store = JevComparisonStore()
        let new = makeRecord(adjudicated: false)
        store.add(new)

        let url = try store.exportJSONL()
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(try exportedIDs(store),
                       [carried.id.uuidString, onlyYesterday.id.uuidString, new.id.uuidString])
        let first = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        XCTAssertEqual(first["userVerdict"] as? String, "bothWrong", "today's copy wins")
    }

    /// The panel's "prepare export (N)" promises N records. It must be what the file holds.
    func test_thePanelsCount_matchesWhatIsExported() throws {
        try writeDayFile("jev-comparisons-\(dayKey(yesterday)).json",
                         [try object(makeRecord(adjudicated: true, at: yesterday))])
        let store = JevComparisonStore()
        store.add(makeRecord(adjudicated: false))

        XCTAssertEqual(store.exportableCount, try exportedIDs(store).count)
        XCTAssertEqual(store.exportableCount, 2)
    }
}
