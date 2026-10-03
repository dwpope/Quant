import XCTest
import PostureLogic
import simd
@testable import Quant

/// "Start fresh": set every Jev record so far aside, so the next export holds only what comes
/// after. Asked for on 2026-10-03, when 49 practice and test records sat ahead of a real session
/// in the same export and nothing on the phone could remove them.
///
/// Set aside, not deleted: the day files move into `Documents/jev-archive/<timestamp>/`, which
/// the export never reads. Nothing is lost, and they stay reachable with Xcode's container
/// download.
@MainActor
final class JevStartFreshTests: XCTestCase {

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var archive: URL { documents.appendingPathComponent("jev-archive") }

    private func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func clean() {
        JevComparisonStore.flushPendingWrites()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []
        for name in names where name.hasPrefix("jev-comparisons-") {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent(name))
        }
        try? FileManager.default.removeItem(at: archive)
    }

    override func setUpWithError() throws { clean() }
    override func tearDownWithError() throws { clean() }

    private func makeRecord(at date: Date = Date()) -> JevComparisonRecord {
        let baseline = Baseline(
            timestamp: Date(), shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
            headPosition: SIMD3<Float>(0.5, 0.8, 0), torsoAngle: 3, shoulderTwist: 1,
            shoulderWidth: 0.2, depthAvailable: false, neckHeight: 0.35)
        let features = JevFeatures.make(
            sample: PoseSample(
                timestamp: 0, depthMode: .twoDOnly,
                headPosition: SIMD3<Float>(0.5, 0.8, 0), shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
                leftShoulder: SIMD3<Float>(0.4, 0.6, 0), rightShoulder: SIMD3<Float>(0.6, 0.6, 0),
                torsoAngle: 5, headForwardOffset: 0, shoulderTwist: 0,
                shoulderWidthRaw: 0.3, trackingQuality: .good),
            metrics: RawMetrics(
                timestamp: 0, forwardCreep: 0.1, headDrop: 0.01, shoulderRounding: 1,
                lateralLean: 0.05, twist: 1, movementLevel: 0, headMovementPattern: .still,
                lateralLeanSigned: 0.05, twistSigned: 1),
            baseline: baseline)!
        return JevComparisonRecord(
            id: UUID(), capturedAt: date, features: features, baseline: baseline,
            thresholdState: .good,
            jev: JevVerdict(posture: "slouch", confidence: 0.6, probabilities: ["slouch": 0.6],
                            model: "jev-test"),
            jevError: nil)
    }

    private func archivedFiles() -> [String] {
        let enumerator = FileManager.default.enumerator(atPath: archive.path)
        return (enumerator?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".json") }
    }

    // MARK: -

    func test_startFresh_leavesNothingToExport() throws {
        let yesterday = Date().addingTimeInterval(-86_400)
        try JSONSerialization.data(withJSONObject: [
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(makeRecord(at: yesterday)))
        ]).write(to: documents.appendingPathComponent("jev-comparisons-\(dayKey(yesterday)).json"))
        let store = JevComparisonStore()
        store.add(makeRecord())
        XCTAssertEqual(store.exportableCount, 2)

        try store.startFresh()

        XCTAssertEqual(store.exportableCount, 0)
        XCTAssertTrue(store.comparisons.isEmpty)
        XCTAssertEqual(try String(contentsOf: store.exportJSONL(), encoding: .utf8), "")
    }

    /// Set aside, not deleted: every file is in the archive, intact.
    func test_startFresh_movesEveryDayFile_intoTheArchive_intact() throws {
        let yesterday = Date().addingTimeInterval(-86_400)
        let old = makeRecord(at: yesterday)
        try JSONSerialization.data(withJSONObject: [
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(old))
        ]).write(to: documents.appendingPathComponent("jev-comparisons-\(dayKey(yesterday)).json"))
        let unparseable = "jev-comparisons-\(dayKey(yesterday)).unreadable-1.json"
        try Data("not json".utf8).write(to: documents.appendingPathComponent(unparseable))
        let store = JevComparisonStore()
        store.add(makeRecord())

        try store.startFresh()

        let names = (try FileManager.default.contentsOfDirectory(atPath: documents.path))
            .filter { $0.hasPrefix("jev-comparisons-") }
        XCTAssertEqual(names, [], "no day files left beside the store")
        let archived = archivedFiles()
        XCTAssertEqual(archived.count, 3, "yesterday's, today's and the set-aside file")
        let yesterdayCopy = try XCTUnwrap(archived.first { $0.hasSuffix("\(dayKey(yesterday)).json") })
        let data = try Data(contentsOf: archive.appendingPathComponent(yesterdayCopy))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(old.id.uuidString))
    }

    /// The next capture starts a new file, and nothing comes back from the archive.
    func test_afterStartFresh_onlyNewCapturesAreExported_evenAfterRelaunch() throws {
        let store = JevComparisonStore()
        store.add(makeRecord())
        try store.startFresh()
        let new = makeRecord()
        store.add(new)
        JevComparisonStore.flushPendingWrites()

        let relaunched = JevComparisonStore()

        XCTAssertEqual(relaunched.exportableRecords.map(\.id), [new.id])
    }

    /// Starting fresh twice keeps both sets apart rather than overwriting the first.
    func test_startingFreshTwice_keepsBothSets() throws {
        let store = JevComparisonStore()
        store.add(makeRecord())
        try store.startFresh()
        store.add(makeRecord())
        try store.startFresh()

        let folders = try FileManager.default.contentsOfDirectory(atPath: archive.path)
        XCTAssertEqual(folders.count, 2)
        XCTAssertEqual(archivedFiles().count, 2)
    }
}
