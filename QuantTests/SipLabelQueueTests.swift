import XCTest
import PostureLogic
@testable import Quant

/// Tests for `SipLabelQueue` — FIFO ordering, label application,
/// timeout behaviour, and background drain.
///
/// These tests deliberately avoid AppModel so they remain fast and
/// deterministic. The queue is exercised through its public API and
/// observed through its `onLabel` / `onActiveItemChanged` callbacks.
@MainActor
final class SipLabelQueueTests: XCTestCase {

    // MARK: - Helpers

    private func makePendingItem(timestamp: TimeInterval = 1_000) -> PendingSipLabel {
        let event = SipEvent(timestamp: timestamp, duration: 2.0)
        return PendingSipLabel(event: event)
    }

    /// Returns a queue wired up to capture labels and activation events.
    private func makeQueue(
        timeoutInterval: TimeInterval = 999,
        onLabel: @escaping (UUID, SipEvent.Label) -> Void = { _, _ in },
        onActiveItemChanged: @escaping (PendingSipLabel?) -> Void = { _ in }
    ) -> SipLabelQueue {
        let q = SipLabelQueue(timeoutInterval: timeoutInterval)
        q.onLabel = onLabel
        q.onActiveItemChanged = onActiveItemChanged
        return q
    }

    // MARK: - FIFO ordering

    func test_firstEnqueuedBecomesActive() {
        var activated: [UUID] = []
        let q = makeQueue(onActiveItemChanged: { if let i = $0 { activated.append(i.id) } })

        let a = makePendingItem(timestamp: 1_000)
        let b = makePendingItem(timestamp: 2_000)
        q.enqueue(a)
        q.enqueue(b)

        XCTAssertEqual(q.activeItem?.id, a.id)
        XCTAssertEqual(activated.first, a.id)
    }

    func test_finishingActivePromotesNext() {
        let q = makeQueue(onLabel: { _, _ in })

        let a = makePendingItem(timestamp: 1_000)
        let b = makePendingItem(timestamp: 2_000)
        let c = makePendingItem(timestamp: 3_000)
        q.enqueue(a)
        q.enqueue(b)
        q.enqueue(c)

        q.applyLabel(.confirmed, toID: a.id)
        XCTAssertEqual(q.activeItem?.id, b.id)

        q.applyLabel(.confirmed, toID: b.id)
        XCTAssertEqual(q.activeItem?.id, c.id)

        q.applyLabel(.confirmed, toID: c.id)
        XCTAssertNil(q.activeItem)
    }

    func test_activeItemBecomesNilWhenQueueDrainsByApplication() {
        var lastActive: PendingSipLabel? = PendingSipLabel(event: SipEvent(timestamp: 0, duration: 0))
        let q = makeQueue(onLabel: { _, _ in }, onActiveItemChanged: { lastActive = $0 })

        let a = makePendingItem()
        q.enqueue(a)
        q.applyLabel(.confirmed, toID: a.id)

        XCTAssertNil(q.activeItem)
        XCTAssertNil(lastActive)
    }

    // MARK: - Label application

    func test_applyLabel_firesCallbackWithCorrectPair() {
        var received: [(UUID, SipEvent.Label)] = []
        let q = makeQueue(onLabel: { received.append(($0, $1)) })

        let item = makePendingItem()
        q.enqueue(item)
        q.applyLabel(.chinRest, toID: item.id)

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].0, item.id)
        XCTAssertEqual(received[0].1, .chinRest)
    }

    func test_applyLabel_wrongID_isNoOp() {
        var count = 0
        let q = makeQueue(onLabel: { _, _ in count += 1 })

        let item = makePendingItem()
        q.enqueue(item)
        q.applyLabel(.confirmed, toID: UUID())   // wrong id

        XCTAssertEqual(count, 0)
        XCTAssertEqual(q.activeItem?.id, item.id)
    }

    func test_dismissActiveAsUnconfirmed_labelsFired() {
        var label: SipEvent.Label?
        let q = makeQueue(onLabel: { _, l in label = l })

        let item = makePendingItem()
        q.enqueue(item)
        q.dismissActiveAsUnconfirmed()

        XCTAssertEqual(label, .unconfirmed)
        XCTAssertNil(q.activeItem)
    }

    func test_dismissActiveAsUnconfirmed_emptyQueue_isNoOp() {
        var count = 0
        let q = makeQueue(onLabel: { _, _ in count += 1 })
        q.dismissActiveAsUnconfirmed()
        XCTAssertEqual(count, 0)
    }

    // MARK: - Timeout

    func test_timeout_dismissesActiveAsUnconfirmed() async {
        var labeled: SipEvent.Label?
        let q = makeQueue(timeoutInterval: 0.05, onLabel: { _, l in labeled = l })

        q.enqueue(makePendingItem())

        // 0.2s > 0.05s timeout — enough headroom even on a loaded CI machine.
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(labeled, .unconfirmed)
        XCTAssertNil(q.activeItem)
    }

    func test_timeout_promotesNextItemAfterExpiry() async {
        var labels: [(UUID, SipEvent.Label)] = []
        let q = makeQueue(timeoutInterval: 0.05, onLabel: { labels.append(($0, $1)) })

        let a = makePendingItem(timestamp: 1_000)
        let b = makePendingItem(timestamp: 2_000)
        q.enqueue(a)
        q.enqueue(b)

        // Wait for A to time out (0.2s), then B to time out (another 0.2s).
        try? await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertEqual(labels.count, 2)
        XCTAssertEqual(labels[0].0, a.id)
        XCTAssertEqual(labels[1].0, b.id)
        XCTAssertTrue(labels.allSatisfy { $0.1 == .unconfirmed })
        XCTAssertNil(q.activeItem)
    }

    func test_applyLabelBeforeTimeout_cancelsTimer() async {
        var labels: [(UUID, SipEvent.Label)] = []
        let q = makeQueue(timeoutInterval: 0.1, onLabel: { labels.append(($0, $1)) })

        let item = makePendingItem()
        q.enqueue(item)

        // Apply immediately — well before the 0.1s timeout.
        q.applyLabel(.confirmed, toID: item.id)

        // Wait past the original timeout window.
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Only one label should have fired (the explicit apply), not two.
        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(labels[0].1, .confirmed)
    }

    // MARK: - Background drain

    func test_drainAsUnconfirmed_labelsActiveAndAllPending() {
        var labels: [(UUID, SipEvent.Label)] = []
        let q = makeQueue(onLabel: { labels.append(($0, $1)) })

        let a = makePendingItem(timestamp: 1_000)
        let b = makePendingItem(timestamp: 2_000)
        let c = makePendingItem(timestamp: 3_000)
        q.enqueue(a)
        q.enqueue(b)
        q.enqueue(c)

        q.drainAsUnconfirmed()

        XCTAssertEqual(labels.count, 3)
        XCTAssertTrue(labels.allSatisfy { $0.1 == .unconfirmed })
        // Order: active first, then pending in FIFO.
        XCTAssertEqual(labels.map(\.0), [a.id, b.id, c.id])
        XCTAssertNil(q.activeItem)
    }

    func test_drainAsUnconfirmed_emptyQueue_isNoOp() {
        var count = 0
        let q = makeQueue(onLabel: { _, _ in count += 1 })
        q.drainAsUnconfirmed()
        XCTAssertEqual(count, 0)
        XCTAssertNil(q.activeItem)
    }

    func test_drainAsUnconfirmed_onlyActiveItem() {
        var labeled: (UUID, SipEvent.Label)?
        let q = makeQueue(onLabel: { labeled = ($0, $1) })

        let item = makePendingItem()
        q.enqueue(item)
        q.drainAsUnconfirmed()

        XCTAssertEqual(labeled?.0, item.id)
        XCTAssertEqual(labeled?.1, .unconfirmed)
        XCTAssertNil(q.activeItem)
    }

    func test_drainAsUnconfirmed_cancelsRunningTimeout() async {
        var labels: [(UUID, SipEvent.Label)] = []
        let q = makeQueue(timeoutInterval: 0.1, onLabel: { labels.append(($0, $1)) })

        q.enqueue(makePendingItem())

        // Drain immediately — before the 0.1s timeout would fire.
        q.drainAsUnconfirmed()

        // Wait past the original timeout window.
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Only one label from drain, not a second from the timer.
        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(labels[0].1, .unconfirmed)
    }
}
