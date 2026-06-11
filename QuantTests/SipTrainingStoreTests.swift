import XCTest
import PostureLogic
@testable import Quant

/// Tests for `SipTrainingStore` — sidecar persistence and JSONL export
/// for training-mode feature records.
@MainActor
final class SipTrainingStoreTests: XCTestCase {

    override func setUpWithError() throws {
        SipTrainingStore.flushPendingWrites()   // settle async writes before cleaning
        deleteTodayFiles()
    }

    override func tearDownWithError() throws {
        SipTrainingStore.flushPendingWrites()   // a late write must not outlive cleanup
        deleteTodayFiles()
    }

    // MARK: - Helpers

    private func makeRecord(
        id: UUID = UUID(),
        capturedAt: TimeInterval = 1_000
    ) -> SipTrainingRecord {
        SipTrainingRecord(
            id: id,
            capturedAt: capturedAt,
            scores: SipDetector.Scores(
                proximity: 1.0,
                velocity: 1.0,
                duration: 1.0,
                activeWrist: "leftWrist"
            ),
            thresholds: SipThresholds(),
            bufferFrames: [
                SipTrainingBuffer.Frame(timestamp: capturedAt - 0.1, keypoints: []),
                SipTrainingBuffer.Frame(timestamp: capturedAt, keypoints: []),
            ]
        )
    }

    // MARK: - Save / lookup

    func test_save_storesRecordForLookup() {
        let store = SipTrainingStore()
        let record = makeRecord()

        store.save(record)

        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.record(for: record.id)?.id, record.id)
    }

    func test_recordForUnknownId_returnsNil() {
        let store = SipTrainingStore()
        XCTAssertNil(store.record(for: UUID()))
    }

    func test_save_overwritesSameId() {
        let store = SipTrainingStore()
        let id = UUID()
        store.save(makeRecord(id: id, capturedAt: 1_000))
        store.save(makeRecord(id: id, capturedAt: 2_000))

        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.record(for: id)?.capturedAt, 2_000)
    }

    // MARK: - Remove

    func test_remove_deletesRecord() {
        let store = SipTrainingStore()
        let record = makeRecord()
        store.save(record)

        store.remove(id: record.id)

        XCTAssertTrue(store.records.isEmpty)
        XCTAssertNil(store.record(for: record.id))
    }

    func test_remove_unknownIdIsNoOp() {
        let store = SipTrainingStore()
        store.save(makeRecord())
        store.remove(id: UUID())
        XCTAssertEqual(store.records.count, 1)
    }

    // MARK: - Persistence

    func test_save_persistsAcrossStoreReload() {
        let first = SipTrainingStore()
        let record = makeRecord()
        first.save(record)
        SipTrainingStore.flushPendingWrites()   // disk writes are async off the MainActor

        let reloaded = SipTrainingStore()

        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.record(for: record.id)?.id, record.id)
    }

    // MARK: - JSONL export

    func test_exportJSONL_joinsSipsAndFeaturesById() throws {
        let store = SipTrainingStore()

        let idA = UUID()
        let idB = UUID()
        store.save(makeRecord(id: idA, capturedAt: 1_000))
        store.save(makeRecord(id: idB, capturedAt: 2_000))

        let sipA = SipEvent(id: idA, timestamp: 1_000, duration: 2.0, label: .confirmed)
        let sipB = SipEvent(id: idB, timestamp: 2_000, duration: 2.0, label: .chinRest)

        let url = try store.exportJSONL(for: [sipA, sipB])
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? ""

        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)

        // Each line must be a standalone JSON object.
        for line in lines {
            let lineData = Data(line.utf8)
            let obj = try JSONSerialization.jsonObject(with: lineData)
            XCTAssertNotNil(obj as? [String: Any])
        }
    }

    func test_exportJSONL_skipsUnconfirmedRows() throws {
        let store = SipTrainingStore()

        let confirmedId = UUID()
        let unconfirmedId = UUID()
        store.save(makeRecord(id: confirmedId, capturedAt: 1_000))
        store.save(makeRecord(id: unconfirmedId, capturedAt: 2_000))

        let confirmed = SipEvent(id: confirmedId, timestamp: 1_000, duration: 2.0, label: .confirmed)
        let unconfirmed = SipEvent(id: unconfirmedId, timestamp: 2_000, duration: 2.0, label: .unconfirmed)

        let url = try store.exportJSONL(for: [confirmed, unconfirmed])
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n")

        XCTAssertEqual(lines.count, 1, "unconfirmed rows must be filtered out")
        XCTAssertTrue(
            lines.first?.contains(confirmedId.uuidString) ?? false,
            "exported line should reference the confirmed sip id"
        )
    }

    func test_exportJSONL_skipsSipsWithoutMatchingRecord() throws {
        let store = SipTrainingStore()

        let haveRecord = UUID()
        let noRecord = UUID()
        store.save(makeRecord(id: haveRecord, capturedAt: 1_000))

        let withRecord = SipEvent(id: haveRecord, timestamp: 1_000, duration: 2.0, label: .confirmed)
        let withoutRecord = SipEvent(id: noRecord, timestamp: 2_000, duration: 2.0, label: .confirmed)

        let url = try store.exportJSONL(for: [withRecord, withoutRecord])
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n")

        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines.first?.contains(haveRecord.uuidString) ?? false)
    }

    func test_exportJSONL_emptyInputProducesEmptyFile() throws {
        let store = SipTrainingStore()
        let url = try store.exportJSONL(for: [])
        let data = try Data(contentsOf: url)
        XCTAssertTrue(data.isEmpty)
    }

    // MARK: - Helpers

    private func deleteTodayFiles() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let key = String(
            format: "%04d-%02d-%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0
        )
        try? fm.removeItem(at: docs.appendingPathComponent("sip-training-\(key).json"))
        try? fm.removeItem(at: caches.appendingPathComponent("sip-training-\(key).jsonl"))
    }
}
