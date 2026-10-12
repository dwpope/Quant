import XCTest
@testable import Quant

/// What the app keeps in Documents, scanned at launch, and deleting the older part of it
/// (2026-10-11, Dave: "Scan at the start of the app and allow me to delete older data").
@MainActor
final class StoredDataTests: XCTestCase {

    private var folder: URL!
    private let calendar = Calendar(identifier: .gregorian)
    /// 2026-10-11 at noon, local.
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12))!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("stored-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    @discardableResult
    private func file(_ name: String, bytes: Int = 100, modified: Date? = nil) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(repeating: 1, count: bytes).write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    private func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: now)! }

    // MARK: - The scan

    func test_theScan_sortsEachFileByKind_andDay() throws {
        try file("posture-log-2026-10-11.jsonl", bytes: 10)
        try file("posture-log-2026-08-01.jsonl", bytes: 20)
        try file("jev-comparisons-2026-09-01.json", bytes: 30)
        try file("sips-2026-07-01.json", bytes: 40)
        try file("sip-training-2026-07-01.json", bytes: 50)
        try file("posture-session-0D574D64.json", bytes: 60, modified: daysAgo(40))
        try file("Baseline.json")  // not the app's daily data: left alone

        let items = StoredData.scan(folder: folder, calendar: calendar)

        XCTAssertEqual(items.count, 6)
        let log = try XCTUnwrap(items.first { $0.url.lastPathComponent == "posture-log-2026-08-01.jsonl" })
        XCTAssertEqual(log.kind, .postureLog)
        XCTAssertEqual(log.bytes, 20)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: log.day),
                       DateComponents(year: 2026, month: 8, day: 1))
        let recording = try XCTUnwrap(items.first { $0.kind == .recording })
        XCTAssertEqual(calendar.startOfDay(for: recording.day), calendar.startOfDay(for: daysAgo(40)),
                       "a recording's day is when it was written")
    }

    /// A Jev export folder counts as one item, its whole size.
    func test_aJevExportFolder_isOneItem() throws {
        let export = folder.appendingPathComponent("jev-archive/2026-08-01-1")
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        try Data(count: 70).write(to: export.appendingPathComponent("a.json"))
        try Data(count: 30).write(to: export.appendingPathComponent("b.csv"))
        try FileManager.default.setAttributes([.modificationDate: daysAgo(70)], ofItemAtPath: export.path)

        let items = StoredData.scan(folder: folder, calendar: calendar)

        XCTAssertEqual(items.map(\.kind), [.jevExport])
        XCTAssertEqual(items.first?.bytes, 100)
    }

    // MARK: - Older than

    func test_olderThan_countsWholeDaysBeforeToday() throws {
        try file("posture-log-2026-10-11.jsonl")   // today
        try file("posture-log-2026-09-11.jsonl")   // 30 days ago: kept by "older than 30 days"
        try file("posture-log-2026-09-10.jsonl")   // 31 days ago
        let items = StoredData.scan(folder: folder, calendar: calendar)

        let old = StoredData.olderThan(days: 30, in: items, now: now, calendar: calendar)

        XCTAssertEqual(old.map(\.url.lastPathComponent), ["posture-log-2026-09-10.jsonl"])
    }

    /// Today's files are never offered, whatever the cut-off: they're being written.
    func test_today_isNeverOlder() throws {
        try file("posture-log-2026-10-11.jsonl")
        let items = StoredData.scan(folder: folder, calendar: calendar)
        XCTAssertTrue(StoredData.olderThan(days: 0, in: items, now: now, calendar: calendar).isEmpty)
    }

    // MARK: - Deleting

    func test_delete_removesOnlyWhatItsGiven() throws {
        try file("posture-log-2026-08-01.jsonl")
        try file("posture-log-2026-10-11.jsonl")
        let items = StoredData.scan(folder: folder, calendar: calendar)
        let old = StoredData.olderThan(days: 30, in: items, now: now, calendar: calendar)

        let freed = StoredData.delete(old)

        XCTAssertEqual(freed, 100)
        let left = StoredData.scan(folder: folder, calendar: calendar).map(\.url.lastPathComponent)
        XCTAssertEqual(left, ["posture-log-2026-10-11.jsonl"])
    }

    // MARK: - The summary

    func test_theSummary_addsUpByKind() throws {
        try file("posture-log-2026-08-01.jsonl", bytes: 1000)
        try file("posture-log-2026-08-02.jsonl", bytes: 500)
        try file("sips-2026-08-01.json", bytes: 250)
        let summary = StoredData.Summary(items: StoredData.scan(folder: folder, calendar: calendar))

        XCTAssertEqual(summary.totalBytes, 1750)
        XCTAssertEqual(summary.byKind.first?.kind, .postureLog, "biggest first")
        XCTAssertEqual(summary.byKind.first?.count, 2)
        XCTAssertEqual(summary.byKind.first?.bytes, 1500)
    }
}
