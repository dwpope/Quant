import XCTest
import PostureLogic
@testable import Quant

/// Tests for `SipStore.setLabel(id:label:)` — the training-mode entry point
/// that attaches / updates / clears a label on an already-stored sip.
///
/// `SipStore` persists to today's `Documents/sips-YYYY-MM-DD.json`. Each
/// test deletes that file in `setUp`/`tearDown` so runs don't bleed into one
/// another.
@MainActor
final class SipStoreLabelTests: XCTestCase {

    override func setUpWithError() throws {
        SipStore.flushPendingWrites()   // settle async writes before cleaning
        deleteTodayFile()
    }

    override func tearDownWithError() throws {
        SipStore.flushPendingWrites()   // a late write must not outlive cleanup
        deleteTodayFile()
    }

    // MARK: - setLabel basic behaviour

    func test_setLabel_updatesMatchingRow() {
        let store = SipStore()
        let event = SipEvent(timestamp: 1_000, duration: 2.0)
        store.add(event)

        store.setLabel(id: event.id, label: .chinRest)

        XCTAssertEqual(store.sips.count, 1)
        XCTAssertEqual(store.sips.first?.label, .chinRest)
    }

    func test_setLabel_canClearExistingLabel() {
        let store = SipStore()
        let event = SipEvent(
            timestamp: 1_000,
            duration: 2.0,
            label: .confirmed
        )
        store.add(event)
        XCTAssertEqual(store.sips.first?.label, .confirmed)

        store.setLabel(id: event.id, label: nil)

        XCTAssertNil(store.sips.first?.label)
    }

    func test_setLabel_onUnknownIdIsNoOp() {
        let store = SipStore()
        let event = SipEvent(timestamp: 1_000, duration: 2.0)
        store.add(event)

        store.setLabel(id: UUID(), label: .chinRest)

        XCTAssertNil(store.sips.first?.label)
        XCTAssertEqual(store.sips.count, 1)
    }

    func test_setLabel_leavesOtherRowsUntouched() {
        let store = SipStore()
        let a = SipEvent(timestamp: 1_000, duration: 2.0)
        let b = SipEvent(timestamp: 1_100, duration: 2.0)
        let c = SipEvent(timestamp: 1_200, duration: 2.0)
        store.add(a)
        store.add(b)
        store.add(c)

        store.setLabel(id: b.id, label: .faceTouch)

        XCTAssertNil(store.sips.first { $0.id == a.id }?.label)
        XCTAssertEqual(store.sips.first { $0.id == b.id }?.label, .faceTouch)
        XCTAssertNil(store.sips.first { $0.id == c.id }?.label)
    }

    // MARK: - Persistence

    func test_setLabel_persistsAcrossStoreReload() {
        let store = SipStore()
        let event = SipEvent(timestamp: 1_000, duration: 2.0)
        store.add(event)
        store.setLabel(id: event.id, label: .phoneToFace)
        SipStore.flushPendingWrites()   // disk writes are async off the MainActor

        // A brand new SipStore reads the same Documents file on init.
        let reloaded = SipStore()
        XCTAssertEqual(reloaded.sips.count, 1)
        XCTAssertEqual(reloaded.sips.first?.label, .phoneToFace)
    }

    // MARK: - Remove still works post-label

    func test_remove_stillWorksAfterLabeling() {
        let store = SipStore()
        let event = SipEvent(timestamp: 1_000, duration: 2.0)
        store.add(event)
        store.setLabel(id: event.id, label: .confirmed)

        store.remove(id: event.id)

        XCTAssertTrue(store.sips.isEmpty)
    }

    // MARK: - Helpers

    private func deleteTodayFile() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let key = String(
            format: "%04d-%02d-%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0
        )
        let url = docs.appendingPathComponent("sips-\(key).json")
        try? fm.removeItem(at: url)
    }
}
