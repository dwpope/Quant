import XCTest
import Combine
@testable import Quant

/// The Watch's session marks (2026-11-27) reach the posture log at the moment Dave tapped, by
/// message or queued. The dictionaries match the Watch's `SessionMarkTests`.
@MainActor
final class SessionMarkAppTests: XCTestCase {

    private let message: [String: Any] = ["type": "mark", "what": "craning", "at": 1_795_770_000.25]

    func test_readsAMark() throws {
        let mark = try XCTUnwrap(WatchConnectivityService.sessionMark(from: message))
        XCTAssertEqual(mark, SessionMarkReport(what: "craning", at: Date(timeIntervalSince1970: 1_795_770_000.25)))
    }

    func test_ignoresUnknownOrMalformedMarks() {
        XCTAssertNil(WatchConnectivityService.sessionMark(from: ["type": "mark", "what": "dancing", "at": 1.0]))
        XCTAssertNil(WatchConnectivityService.sessionMark(from: ["type": "mark", "what": "craning"]))
        XCTAssertNil(WatchConnectivityService.sessionMark(from: ["type": "calibrate", "what": "craning", "at": 1.0]))
    }

    func test_everyWatchMarkIsKnown() {
        for what in ["lookingDown", "craning", "movedSeat", "yawning", "sluggish", "sittingWell"] {
            XCTAssertNotNil(WatchConnectivityService.sessionMark(from: ["type": "mark", "what": what, "at": 1.0]), what)
        }
    }

    func test_byMessageOrQueued_bothArrive() {
        let service = WatchConnectivityService()
        var received: [SessionMarkReport] = []
        let subscription = service.markReceived.sink { received.append($0) }
        defer { subscription.cancel() }
        service.handleReceivedMessage(message)
        service.handleQueued(message)
        XCTAssertEqual(received.count, 2)
    }

    func test_logLine_isDatedAtTheTap() {
        let event = PostureLogRecorder.markEvent(
            SessionMarkReport(what: "yawning", at: Date(timeIntervalSince1970: 1_795_770_123)))
        XCTAssertEqual(event.kind, "mark")
        XCTAssertEqual(event.value, "yawning")
        XCTAssertEqual(event.t, 1_795_770_123)
    }
}
