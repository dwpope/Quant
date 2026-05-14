import XCTest
import simd
import PostureLogic
@testable import Quant

/// Tests for `PostureSessionSummary` — pure computation over PoseSample arrays.
///
/// Follows the same pattern as `SipInsightsTests`: deterministic inputs,
/// no side effects, no file system or clock dependencies.
final class PostureSessionSummaryTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a PoseSample with configurable properties and sensible defaults.
    private func sample(
        timestamp: TimeInterval = 1.0,
        depthMode: DepthMode = .twoDOnly,
        headForwardOffset: Float = 0.02,
        torsoAngle: Float = 5.0,
        shoulderTwist: Float = 3.0,
        shoulderWidthRaw: Float = 0.3,
        trackingQuality: TrackingQuality = .good
    ) -> PoseSample {
        PoseSample(
            timestamp: timestamp,
            depthMode: depthMode,
            headPosition: SIMD3(0, 1, 0),
            shoulderMidpoint: SIMD3(0, 0, 0),
            leftShoulder: SIMD3(-0.15, 0, 0),
            rightShoulder: SIMD3(0.15, 0, 0),
            torsoAngle: torsoAngle,
            headForwardOffset: headForwardOffset,
            shoulderTwist: shoulderTwist,
            shoulderWidthRaw: shoulderWidthRaw,
            trackingQuality: trackingQuality
        )
    }

    // MARK: - Empty

    func test_empty_sampleCountIsZero() {
        let summary = PostureSessionSummary(samples: [])
        XCTAssertEqual(summary.sampleCount, 0)
    }

    func test_empty_allOptionalsNil() {
        let summary = PostureSessionSummary(samples: [])
        XCTAssertNil(summary.sessionDuration)
        XCTAssertNil(summary.firstTimestamp)
        XCTAssertNil(summary.lastTimestamp)
        XCTAssertNil(summary.goodTrackingPercent)
        XCTAssertNil(summary.depthFusionPercent)
        XCTAssertNil(summary.averageHeadForward)
        XCTAssertNil(summary.peakHeadForward)
        XCTAssertNil(summary.averageTorsoAngle)
        XCTAssertNil(summary.peakTorsoAngle)
        XCTAssertNil(summary.averageShoulderTwist)
        XCTAssertNil(summary.peakShoulderTwist)
    }

    func test_empty_allCountsZero() {
        let summary = PostureSessionSummary(samples: [])
        XCTAssertEqual(summary.goodTrackingCount, 0)
        XCTAssertEqual(summary.degradedTrackingCount, 0)
        XCTAssertEqual(summary.lostTrackingCount, 0)
        XCTAssertEqual(summary.depthFusionCount, 0)
        XCTAssertEqual(summary.twoDOnlyCount, 0)
        XCTAssertEqual(summary.goodSampleCount, 0)
    }

    // MARK: - Single Sample

    func test_singleSample_sampleCountIsOne() {
        let summary = PostureSessionSummary(samples: [sample()])
        XCTAssertEqual(summary.sampleCount, 1)
    }

    func test_singleSample_durationIsNil() {
        let summary = PostureSessionSummary(samples: [sample(timestamp: 10.0)])
        XCTAssertNil(summary.sessionDuration)
    }

    func test_singleSample_timestampsPresent() {
        let s = sample(timestamp: 42.0)
        let summary = PostureSessionSummary(samples: [s])
        XCTAssertEqual(summary.firstTimestamp, 42.0)
        XCTAssertEqual(summary.lastTimestamp, 42.0)
    }

    func test_singleSample_trackingQualityCountAndPercent() {
        let summary = PostureSessionSummary(samples: [sample(trackingQuality: .good)])
        XCTAssertEqual(summary.goodTrackingCount, 1)
        XCTAssertEqual(summary.degradedTrackingCount, 0)
        XCTAssertEqual(summary.lostTrackingCount, 0)
        XCTAssertEqual(summary.goodTrackingPercent!, 100.0, accuracy: 0.01)
    }

    func test_singleSample_depthModeCount() {
        let summary = PostureSessionSummary(samples: [sample(depthMode: .depthFusion)])
        XCTAssertEqual(summary.depthFusionCount, 1)
        XCTAssertEqual(summary.twoDOnlyCount, 0)
        XCTAssertEqual(summary.depthFusionPercent!, 100.0, accuracy: 0.01)
    }

    func test_singleSample_metricsEqualInputValues() {
        let summary = PostureSessionSummary(samples: [
            sample(headForwardOffset: 0.05, torsoAngle: 8.0, shoulderTwist: 4.0)
        ])
        XCTAssertEqual(summary.averageHeadForward!, 0.05, accuracy: 0.001)
        XCTAssertEqual(summary.peakHeadForward!, 0.05, accuracy: 0.001)
        XCTAssertEqual(summary.averageTorsoAngle!, 8.0, accuracy: 0.01)
        XCTAssertEqual(summary.peakTorsoAngle!, 8.0, accuracy: 0.01)
        XCTAssertEqual(summary.averageShoulderTwist!, 4.0, accuracy: 0.01)
        XCTAssertEqual(summary.peakShoulderTwist!, 4.0, accuracy: 0.01)
    }

    // MARK: - Multiple Samples — Session Duration

    func test_multipleSamples_sessionDuration() {
        let samples = [
            sample(timestamp: 100.0),
            sample(timestamp: 200.0),
            sample(timestamp: 400.0)
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.sessionDuration!, 300.0, accuracy: 0.1)
        XCTAssertEqual(summary.firstTimestamp, 100.0)
        XCTAssertEqual(summary.lastTimestamp, 400.0)
    }

    func test_unsortedInput_producesCorrectTimestamps() {
        // Pass samples out of order — summary should sort internally
        let samples = [
            sample(timestamp: 300.0),
            sample(timestamp: 100.0),
            sample(timestamp: 200.0)
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.firstTimestamp, 100.0)
        XCTAssertEqual(summary.lastTimestamp, 300.0)
        XCTAssertEqual(summary.sessionDuration!, 200.0, accuracy: 0.1)
    }

    // MARK: - Tracking Quality Breakdown

    func test_trackingQuality_mixedQualities() {
        let samples = [
            sample(timestamp: 1, trackingQuality: .good),
            sample(timestamp: 2, trackingQuality: .good),
            sample(timestamp: 3, trackingQuality: .good),
            sample(timestamp: 4, trackingQuality: .degraded),
            sample(timestamp: 5, trackingQuality: .lost)
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.goodTrackingCount, 3)
        XCTAssertEqual(summary.degradedTrackingCount, 1)
        XCTAssertEqual(summary.lostTrackingCount, 1)
        XCTAssertEqual(summary.goodTrackingPercent!, 60.0, accuracy: 0.01)
    }

    func test_trackingQuality_allDegraded() {
        let samples = [
            sample(timestamp: 1, trackingQuality: .degraded),
            sample(timestamp: 2, trackingQuality: .degraded)
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.goodTrackingCount, 0)
        XCTAssertEqual(summary.degradedTrackingCount, 2)
        XCTAssertEqual(summary.goodTrackingPercent!, 0.0, accuracy: 0.01)
    }

    func test_trackingQuality_allGood() {
        let samples = [
            sample(timestamp: 1, trackingQuality: .good),
            sample(timestamp: 2, trackingQuality: .good),
            sample(timestamp: 3, trackingQuality: .good)
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.goodTrackingPercent!, 100.0, accuracy: 0.01)
    }

    // MARK: - Depth Mode Breakdown

    func test_depthMode_mixedModes() {
        let samples = [
            sample(timestamp: 1, depthMode: .depthFusion),
            sample(timestamp: 2, depthMode: .depthFusion),
            sample(timestamp: 3, depthMode: .twoDOnly),
            sample(timestamp: 4, depthMode: .twoDOnly),
            sample(timestamp: 5, depthMode: .twoDOnly)
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.depthFusionCount, 2)
        XCTAssertEqual(summary.twoDOnlyCount, 3)
        XCTAssertEqual(summary.depthFusionPercent!, 40.0, accuracy: 0.01)
    }

    func test_depthMode_allDepthFusion() {
        let samples = [
            sample(timestamp: 1, depthMode: .depthFusion),
            sample(timestamp: 2, depthMode: .depthFusion)
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.depthFusionPercent!, 100.0, accuracy: 0.01)
    }

    func test_depthMode_allTwoDOnly() {
        let samples = [
            sample(timestamp: 1, depthMode: .twoDOnly),
            sample(timestamp: 2, depthMode: .twoDOnly)
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.depthFusionPercent!, 0.0, accuracy: 0.01)
    }

    // MARK: - Geometric Metric Averages

    func test_metrics_averageOfMultipleSamples() {
        let samples = [
            sample(timestamp: 1, headForwardOffset: 0.02, torsoAngle: 4.0, shoulderTwist: 2.0),
            sample(timestamp: 2, headForwardOffset: 0.04, torsoAngle: 8.0, shoulderTwist: 6.0),
            sample(timestamp: 3, headForwardOffset: 0.06, torsoAngle: 12.0, shoulderTwist: 4.0)
        ]
        let summary = PostureSessionSummary(samples: samples)
        // averages: headForward = (0.02+0.04+0.06)/3 = 0.04
        // torsoAngle = (4+8+12)/3 = 8.0
        // shoulderTwist = (2+6+4)/3 = 4.0
        XCTAssertEqual(summary.averageHeadForward!, 0.04, accuracy: 0.001)
        XCTAssertEqual(summary.averageTorsoAngle!, 8.0, accuracy: 0.01)
        XCTAssertEqual(summary.averageShoulderTwist!, 4.0, accuracy: 0.01)
    }

    func test_metrics_peakValues() {
        let samples = [
            sample(timestamp: 1, headForwardOffset: 0.02, torsoAngle: 4.0, shoulderTwist: 2.0),
            sample(timestamp: 2, headForwardOffset: 0.08, torsoAngle: 15.0, shoulderTwist: 10.0),
            sample(timestamp: 3, headForwardOffset: 0.03, torsoAngle: 6.0, shoulderTwist: 3.0)
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.peakHeadForward!, 0.08, accuracy: 0.001)
        XCTAssertEqual(summary.peakTorsoAngle!, 15.0, accuracy: 0.01)
        XCTAssertEqual(summary.peakShoulderTwist!, 10.0, accuracy: 0.01)
    }

    // MARK: - Metrics Use Absolute Values

    func test_metrics_negativeValuesUseAbsolute() {
        // Negative offsets should be treated as absolute magnitude
        let samples = [
            sample(timestamp: 1, headForwardOffset: -0.05, torsoAngle: -10.0, shoulderTwist: -7.0)
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.averageHeadForward!, 0.05, accuracy: 0.001)
        XCTAssertEqual(summary.peakHeadForward!, 0.05, accuracy: 0.001)
        XCTAssertEqual(summary.averageTorsoAngle!, 10.0, accuracy: 0.01)
        XCTAssertEqual(summary.peakTorsoAngle!, 10.0, accuracy: 0.01)
        XCTAssertEqual(summary.averageShoulderTwist!, 7.0, accuracy: 0.01)
        XCTAssertEqual(summary.peakShoulderTwist!, 7.0, accuracy: 0.01)
    }

    // MARK: - Metrics Exclude Non-Good Tracking

    func test_metrics_excludeDegradedAndLostSamples() {
        let samples = [
            sample(timestamp: 1, headForwardOffset: 0.02, torsoAngle: 4.0, shoulderTwist: 2.0, trackingQuality: .good),
            sample(timestamp: 2, headForwardOffset: 0.99, torsoAngle: 99.0, shoulderTwist: 99.0, trackingQuality: .degraded),
            sample(timestamp: 3, headForwardOffset: 0.99, torsoAngle: 99.0, shoulderTwist: 99.0, trackingQuality: .lost),
            sample(timestamp: 4, headForwardOffset: 0.06, torsoAngle: 8.0, shoulderTwist: 6.0, trackingQuality: .good)
        ]
        let summary = PostureSessionSummary(samples: samples)
        // Only the two good samples should contribute to metrics
        XCTAssertEqual(summary.goodSampleCount, 2)
        XCTAssertEqual(summary.averageHeadForward!, 0.04, accuracy: 0.001)
        XCTAssertEqual(summary.peakHeadForward!, 0.06, accuracy: 0.001)
        XCTAssertEqual(summary.averageTorsoAngle!, 6.0, accuracy: 0.01)
        XCTAssertEqual(summary.peakTorsoAngle!, 8.0, accuracy: 0.01)
        XCTAssertEqual(summary.averageShoulderTwist!, 4.0, accuracy: 0.01)
        XCTAssertEqual(summary.peakShoulderTwist!, 6.0, accuracy: 0.01)
    }

    func test_metrics_nilWhenAllSamplesAreDegraded() {
        let samples = [
            sample(timestamp: 1, trackingQuality: .degraded),
            sample(timestamp: 2, trackingQuality: .lost)
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.sampleCount, 2)
        XCTAssertEqual(summary.goodSampleCount, 0)
        XCTAssertNil(summary.averageHeadForward)
        XCTAssertNil(summary.peakHeadForward)
        XCTAssertNil(summary.averageTorsoAngle)
        XCTAssertNil(summary.peakTorsoAngle)
        XCTAssertNil(summary.averageShoulderTwist)
        XCTAssertNil(summary.peakShoulderTwist)
    }

    // MARK: - Description Helpers

    func test_durationDescription_minutes() {
        let samples = [
            sample(timestamp: 0),
            sample(timestamp: 1920) // 32 minutes
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.durationDescription, "32 min")
    }

    func test_durationDescription_hoursAndMinutes() {
        let samples = [
            sample(timestamp: 0),
            sample(timestamp: 4980) // 1 hr 23 min
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.durationDescription, "1 hr 23 min")
    }

    func test_durationDescription_exactHour() {
        let samples = [
            sample(timestamp: 0),
            sample(timestamp: 7200) // 2 hr
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.durationDescription, "2 hr")
    }

    func test_durationDescription_lessThanOneMinute() {
        let samples = [
            sample(timestamp: 0),
            sample(timestamp: 30) // 30 seconds
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.durationDescription, "<1 min")
    }

    func test_durationDescription_nilWhenEmpty() {
        let summary = PostureSessionSummary(samples: [])
        XCTAssertNil(summary.durationDescription)
    }

    func test_trackingQualityDescription_value() {
        let samples = [
            sample(timestamp: 1, trackingQuality: .good),
            sample(timestamp: 2, trackingQuality: .good),
            sample(timestamp: 3, trackingQuality: .degraded),
            sample(timestamp: 4, trackingQuality: .good)
        ]
        let summary = PostureSessionSummary(samples: samples)
        XCTAssertEqual(summary.trackingQualityDescription, "75% good tracking")
    }

    func test_trackingQualityDescription_nilWhenEmpty() {
        let summary = PostureSessionSummary(samples: [])
        XCTAssertNil(summary.trackingQualityDescription)
    }

    // MARK: - Equatable

    func test_equatable_sameInputsAreEqual() {
        let samples = [
            sample(timestamp: 1, headForwardOffset: 0.02),
            sample(timestamp: 2, headForwardOffset: 0.04)
        ]
        let a = PostureSessionSummary(samples: samples)
        let b = PostureSessionSummary(samples: samples)
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentInputsAreNotEqual() {
        let a = PostureSessionSummary(samples: [sample(timestamp: 1, headForwardOffset: 0.02)])
        let b = PostureSessionSummary(samples: [sample(timestamp: 1, headForwardOffset: 0.08)])
        XCTAssertNotEqual(a, b)
    }
}
