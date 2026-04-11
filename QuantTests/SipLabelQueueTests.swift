import XCTest
import PostureLogic
@testable import Quant

/// Tests for `SipLabelQueue` — the training-mode label prompt FIFO
/// that `AppModel` owns. Exercised in isolation (no `AppModel`, no
/// real timer) because the queue is pure state plus a synchronous
/// `fireActiveTimeout` hook that production code calls from a
/// `Timer` callback and tests call directly.
@MainActor
final class SipLabelQueueTests: XCTestCase {

    // MARK: - Helpers

    /// Captures the `(id, label)` arguments passed to `onResolved` so
    /// tests can assert what the queue emitted in what order.
    private final class Recorder {
        var resolved: [(UUID, SipEvent.Label)] = []
    }

    private func attach(to queue: SipLabelQueue) -> Recorder {
        let recorder = Recorder()
        queue.onResolved = { id, label in
            recorder.resolved.append((id, label))
        }
        return recorder
    }

    private func makePending(id: UUID = UUID()) -> PendingSipLabel {
        PendingSipLabel(
            id: id,
            sipStartTimestamp: 1_000,
            sipDuration: 2.0,
            scores: SipDetector.Scores(
                proximity: 0.5,
                velocity: 0.3,
                duration: 1.2,
                activeWrist: "leftWrist"
            )
        )
    }

    // MARK: - FIFO

    func test_enqueue_whenEmpty_promotesImmediately() {
        let queue = SipLabelQueue()
        let item = makePending()

        queue.enqueue(item)

        XCTAssertEqual(queue.active?.id, item.id)
    }

    func test_enqueue_whileBusy_queuesBehindActive() {
        let queue = SipLabelQueue()
        let a = makePending()
        let b = makePending()
        let c = makePending()

        queue.enqueue(a)
        queue.enqueue(b)
        queue.enqueue(c)

        XCTAssertEqual(queue.active?.id, a.id)
        XCTAssertEqual(queue.pending.map(\.id), [b.id, c.id])
    }

    func test_applyLabel_promotesNextInOrder() {
        let queue = SipLabelQueue()
        let recorder = attach(to: queue)
        let a = makePending()
        let b = makePending()
        let c = makePending()

        queue.enqueue(a)
        queue.enqueue(b)
        queue.enqueue(c)

        queue.applyLabel(.confirmed, to: a.id)
        XCTAssertEqual(queue.active?.id, b.id)

        queue.applyLabel(.chinRest, to: b.id)
        XCTAssertEqual(queue.active?.id, c.id)

        queue.applyLabel(.faceTouch, to: c.id)
        XCTAssertNil(queue.active)
        XCTAssertTrue(queue.pending.isEmpty)

        XCTAssertEqual(recorder.resolved.map(\.0), [a.id, b.id, c.id])
        XCTAssertEqual(recorder.resolved.map(\.1),
                       [.confirmed, .chinRest, .faceTouch])
    }

    func test_applyLabel_withStaleIdIsNoOp() {
        let queue = SipLabelQueue()
        let recorder = attach(to: queue)
        let a = makePending()
        let b = makePending()
        queue.enqueue(a)
        queue.enqueue(b)

        // Applying a label to something that isn't the active item
        // must not resolve anything.
        queue.applyLabel(.confirmed, to: b.id)

        XCTAssertEqual(queue.active?.id, a.id)
        XCTAssertEqual(queue.pending.map(\.id), [b.id])
        XCTAssertTrue(recorder.resolved.isEmpty)
    }

    // MARK: - Timeout

    func test_fireActiveTimeout_marksActiveUnconfirmedAndPromotes() {
        let queue = SipLabelQueue()
        let recorder = attach(to: queue)
        let a = makePending()
        let b = makePending()
        queue.enqueue(a)
        queue.enqueue(b)

        queue.fireActiveTimeout()

        XCTAssertEqual(recorder.resolved.count, 1)
        XCTAssertEqual(recorder.resolved[0].0, a.id)
        XCTAssertEqual(recorder.resolved[0].1, .unconfirmed)
        XCTAssertEqual(queue.active?.id, b.id)
    }

    func test_fireActiveTimeout_onEmptyQueueIsNoOp() {
        let queue = SipLabelQueue()
        let recorder = attach(to: queue)

        queue.fireActiveTimeout()

        XCTAssertNil(queue.active)
        XCTAssertTrue(recorder.resolved.isEmpty)
    }

    func test_dismissAsUnconfirmed_withStaleIdIsNoOp() {
        let queue = SipLabelQueue()
        let recorder = attach(to: queue)
        let a = makePending()
        queue.enqueue(a)

        queue.dismissAsUnconfirmed(id: UUID())

        XCTAssertEqual(queue.active?.id, a.id)
        XCTAssertTrue(recorder.resolved.isEmpty)
    }

    func test_timeoutConfig_defaultsTo15Seconds() {
        XCTAssertEqual(SipLabelQueue().timeoutSeconds, 15)
    }

    // MARK: - Background drain

    func test_drainAsUnconfirmed_writesUnconfirmedForEveryItem() {
        let queue = SipLabelQueue()
        let recorder = attach(to: queue)
        let a = makePending()
        let b = makePending()
        let c = makePending()
        queue.enqueue(a)
        queue.enqueue(b)
        queue.enqueue(c)

        queue.drainAsUnconfirmed()

        // Active + pending all resolved as .unconfirmed, in order.
        XCTAssertEqual(recorder.resolved.map(\.0), [a.id, b.id, c.id])
        XCTAssertTrue(recorder.resolved.allSatisfy { $0.1 == .unconfirmed })

        // Queue is empty after drain.
        XCTAssertNil(queue.active)
        XCTAssertTrue(queue.pending.isEmpty)
    }

    func test_drainAsUnconfirmed_whenEmpty_emitsNothing() {
        let queue = SipLabelQueue()
        let recorder = attach(to: queue)

        queue.drainAsUnconfirmed()

        XCTAssertTrue(recorder.resolved.isEmpty)
        XCTAssertNil(queue.active)
    }

    func test_drainAsUnconfirmed_allowsReuseAfterward() {
        let queue = SipLabelQueue()
        let recorder = attach(to: queue)

        queue.enqueue(makePending())
        queue.enqueue(makePending())
        queue.drainAsUnconfirmed()

        // Queue is ready to accept new items after a drain.
        let fresh = makePending()
        queue.enqueue(fresh)
        XCTAssertEqual(queue.active?.id, fresh.id)

        // And resolving new items still fires onResolved correctly.
        queue.applyLabel(.confirmed, to: fresh.id)
        XCTAssertEqual(recorder.resolved.last?.0, fresh.id)
        XCTAssertEqual(recorder.resolved.last?.1, .confirmed)
    }

    // MARK: - Mixed flow

    func test_mixedFlow_manualLabelThenTimeoutThenDrain() {
        let queue = SipLabelQueue()
        let recorder = attach(to: queue)
        let a = makePending()
        let b = makePending()
        let c = makePending()
        let d = makePending()

        queue.enqueue(a)
        queue.enqueue(b)
        queue.enqueue(c)
        queue.enqueue(d)

        // A → explicitly labeled confirmed.
        queue.applyLabel(.confirmed, to: a.id)

        // B → timeout fires, recorded unconfirmed.
        queue.fireActiveTimeout()

        // C + D are then drained by the app going to background.
        queue.drainAsUnconfirmed()

        XCTAssertEqual(recorder.resolved.map(\.0), [a.id, b.id, c.id, d.id])
        XCTAssertEqual(recorder.resolved.map(\.1),
                       [.confirmed, .unconfirmed, .unconfirmed, .unconfirmed])
        XCTAssertNil(queue.active)
        XCTAssertTrue(queue.pending.isEmpty)
    }
}
