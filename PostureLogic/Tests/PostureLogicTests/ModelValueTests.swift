import simd
import XCTest
@testable import PostureLogic

/// Dedicated tests for small model types that carry computed logic:
/// `TrackingQuality`, `DepthConfidence`, and `Baseline`.
///
/// These models are used throughout the pipeline but previously only had
/// indirect coverage via engine/service tests. This file pins their
/// Comparable ordering, computed properties, and Codable round-trips.
final class ModelValueTests: XCTestCase {

    // MARK: - TrackingQuality

    func testTrackingQuality_allowsPostureJudgement_onlyForGood() {
        XCTAssertFalse(TrackingQuality.lost.allowsPostureJudgement)
        XCTAssertFalse(TrackingQuality.degraded.allowsPostureJudgement)
        XCTAssertTrue(TrackingQuality.good.allowsPostureJudgement)
    }

    func testTrackingQuality_comparableOrdering() {
        XCTAssertTrue(TrackingQuality.lost < .degraded)
        XCTAssertTrue(TrackingQuality.degraded < .good)
        XCTAssertTrue(TrackingQuality.lost < .good)
        XCTAssertFalse(TrackingQuality.good < .lost)
        XCTAssertFalse(TrackingQuality.good < .good) // same value is not less-than
    }

    func testTrackingQuality_sortOrder() {
        let shuffled: [TrackingQuality] = [.good, .lost, .degraded]
        let sorted = shuffled.sorted()
        XCTAssertEqual(sorted, [.lost, .degraded, .good])
    }

    func testTrackingQuality_codableRoundTrip() throws {
        let original = TrackingQuality.degraded
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrackingQuality.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testTrackingQuality_codableRoundTrip_allCases() throws {
        let allCases: [TrackingQuality] = [.lost, .degraded, .good]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for quality in allCases {
            let data = try encoder.encode(quality)
            let decoded = try decoder.decode(TrackingQuality.self, from: data)
            XCTAssertEqual(decoded, quality, "Round-trip failed for \(quality)")
        }
    }

    // MARK: - DepthConfidence

    func testDepthConfidence_numericValues() {
        XCTAssertEqual(DepthConfidence.unavailable.numericValue, 0.0)
        XCTAssertEqual(DepthConfidence.low.numericValue, 0.3)
        XCTAssertEqual(DepthConfidence.medium.numericValue, 0.6)
        XCTAssertEqual(DepthConfidence.high.numericValue, 0.9)
    }

    func testDepthConfidence_comparableOrdering() {
        XCTAssertTrue(DepthConfidence.unavailable < .low)
        XCTAssertTrue(DepthConfidence.low < .medium)
        XCTAssertTrue(DepthConfidence.medium < .high)
        XCTAssertFalse(DepthConfidence.high < .unavailable)
        XCTAssertFalse(DepthConfidence.medium < .medium)
    }

    func testDepthConfidence_sortOrder() {
        let shuffled: [DepthConfidence] = [.high, .unavailable, .medium, .low]
        let sorted = shuffled.sorted()
        XCTAssertEqual(sorted, [.unavailable, .low, .medium, .high])
    }

    func testDepthConfidence_numericValuesMonotonicallyIncrease() {
        let ordered: [DepthConfidence] = [.unavailable, .low, .medium, .high]
        for i in 0..<(ordered.count - 1) {
            XCTAssertTrue(
                ordered[i].numericValue < ordered[i + 1].numericValue,
                "\(ordered[i]) should have a lower numericValue than \(ordered[i + 1])"
            )
        }
    }

    // MARK: - Baseline

    func testBaseline_isStale_returnsFalseForFreshBaseline() {
        let baseline = makeBaseline(timestamp: Date())
        XCTAssertFalse(baseline.isStale())
    }

    func testBaseline_isStale_returnsTrueAfterDefaultInterval() {
        // Default stale interval is 3600 seconds (1 hour)
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        let baseline = makeBaseline(timestamp: twoHoursAgo)
        XCTAssertTrue(baseline.isStale())
    }

    func testBaseline_isStale_respectsCustomInterval() {
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        let baseline = makeBaseline(timestamp: fiveMinutesAgo)

        // With default 1-hour window: not stale
        XCTAssertFalse(baseline.isStale())

        // With custom 2-minute window: stale
        XCTAssertTrue(baseline.isStale(after: 120))
    }

    func testBaseline_isStale_boundaryBehavior() {
        // Exactly at the boundary — just barely past the interval
        let justOver = Date().addingTimeInterval(-3601)
        XCTAssertTrue(makeBaseline(timestamp: justOver).isStale())

        // Just under the boundary
        let justUnder = Date().addingTimeInterval(-3599)
        XCTAssertFalse(makeBaseline(timestamp: justUnder).isStale())
    }

    func testBaseline_codableRoundTrip() throws {
        let original = makeBaseline(timestamp: Date(timeIntervalSince1970: 1700000000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Baseline.self, from: data)

        XCTAssertEqual(decoded.timestamp, original.timestamp)
        XCTAssertEqual(decoded.torsoAngle, original.torsoAngle)
        XCTAssertEqual(decoded.shoulderTwist, original.shoulderTwist)
        XCTAssertEqual(decoded.shoulderWidth, original.shoulderWidth)
        XCTAssertEqual(decoded.depthAvailable, original.depthAvailable)
    }

    // MARK: - Helpers

    private func makeBaseline(timestamp: Date) -> Baseline {
        Baseline(
            timestamp: timestamp,
            shoulderMidpoint: .init(x: 0.5, y: 0.5, z: 0.8),
            headPosition: .init(x: 0.5, y: 0.3, z: 0.75),
            torsoAngle: 5.0,
            shoulderTwist: 2.0,
            shoulderWidth: 0.3,
            depthAvailable: true
        )
    }
}
