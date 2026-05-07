import XCTest
@testable import PostureLogic

/// Tests for `PostureState` — the core enum that drives the posture
/// monitoring UI. Covers the `isBad` and `durationInCurrentState`
/// computed properties, plus Codable round-tripping for all cases.
final class PostureStateTests: XCTestCase {

    // MARK: - isBad

    func test_isBad_trueOnlyForBadState() {
        let now = Date().timeIntervalSince1970

        XCTAssertTrue(PostureState.bad(since: now).isBad)
        XCTAssertFalse(PostureState.good.isBad)
        XCTAssertFalse(PostureState.absent.isBad)
        XCTAssertFalse(PostureState.calibrating.isBad)
        XCTAssertFalse(PostureState.drifting(since: now).isBad)
    }

    // MARK: - durationInCurrentState

    func test_durationInCurrentState_nilForGoodAbsentCalibrating() {
        XCTAssertNil(PostureState.good.durationInCurrentState)
        XCTAssertNil(PostureState.absent.durationInCurrentState)
        XCTAssertNil(PostureState.calibrating.durationInCurrentState)
    }

    func test_durationInCurrentState_returnsPositiveForDrifting() {
        // Use a timestamp 5 seconds in the past.
        let fiveSecondsAgo = Date().timeIntervalSince1970 - 5
        let state = PostureState.drifting(since: fiveSecondsAgo)
        let duration = state.durationInCurrentState

        XCTAssertNotNil(duration)
        // Allow generous tolerance — wall-clock comparisons are inherently
        // imprecise in test runners. We just verify it's in a reasonable range.
        XCTAssertGreaterThanOrEqual(duration!, 4.0)
        XCTAssertLessThan(duration!, 10.0)
    }

    func test_durationInCurrentState_returnsPositiveForBad() {
        let tenSecondsAgo = Date().timeIntervalSince1970 - 10
        let state = PostureState.bad(since: tenSecondsAgo)
        let duration = state.durationInCurrentState

        XCTAssertNotNil(duration)
        XCTAssertGreaterThanOrEqual(duration!, 9.0)
        XCTAssertLessThan(duration!, 15.0)
    }

    func test_durationInCurrentState_recentTimestampIsNearZero() {
        let justNow = Date().timeIntervalSince1970
        let state = PostureState.bad(since: justNow)
        let duration = state.durationInCurrentState

        XCTAssertNotNil(duration)
        XCTAssertGreaterThanOrEqual(duration!, 0)
        XCTAssertLessThan(duration!, 2.0)
    }

    // MARK: - Equatable

    func test_equatable_sameCase_equal() {
        XCTAssertEqual(PostureState.good, PostureState.good)
        XCTAssertEqual(PostureState.absent, PostureState.absent)
        XCTAssertEqual(PostureState.calibrating, PostureState.calibrating)
        XCTAssertEqual(PostureState.bad(since: 1000), PostureState.bad(since: 1000))
        XCTAssertEqual(PostureState.drifting(since: 2000), PostureState.drifting(since: 2000))
    }

    func test_equatable_differentCase_notEqual() {
        XCTAssertNotEqual(PostureState.good, PostureState.absent)
        XCTAssertNotEqual(PostureState.good, PostureState.calibrating)
        XCTAssertNotEqual(PostureState.good, PostureState.bad(since: 0))
        XCTAssertNotEqual(PostureState.bad(since: 100), PostureState.drifting(since: 100))
    }

    func test_equatable_sameCaseDifferentTimestamp_notEqual() {
        XCTAssertNotEqual(PostureState.bad(since: 100), PostureState.bad(since: 200))
        XCTAssertNotEqual(PostureState.drifting(since: 100), PostureState.drifting(since: 200))
    }

    // MARK: - Codable round-trip

    func test_codable_allCasesRoundTrip() throws {
        let cases: [PostureState] = [
            .absent,
            .calibrating,
            .good,
            .drifting(since: 1712345678.5),
            .bad(since: 1712345999.0),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for original in cases {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(PostureState.self, from: data)
            XCTAssertEqual(decoded, original, "Round-trip failed for \(original)")
        }
    }
}
