import XCTest
import simd
@testable import PostureLogic

final class StaleBaselineDetectorTests: XCTestCase {

    var sut: StaleBaselineDetector!

    override func setUp() {
        super.setUp()
        sut = StaleBaselineDetector()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSample(shoulderWidthRaw: Float = 0.3) -> PoseSample {
        PoseSample(
            timestamp: 1.0,
            depthMode: .twoDOnly,
            headPosition: SIMD3(0, 1, 0),
            shoulderMidpoint: SIMD3(0, 0, 0),
            leftShoulder: SIMD3(-0.5, 0, 0),
            rightShoulder: SIMD3(0.5, 0, 0),
            torsoAngle: 0,
            headForwardOffset: 0,
            shoulderTwist: 0,
            shoulderWidthRaw: shoulderWidthRaw,
            trackingQuality: .good
        )
    }

    private func makeBaseline(shoulderWidth: Float = 0.3) -> Baseline {
        Baseline(
            timestamp: Date(),
            shoulderMidpoint: SIMD3(0, 0, 0.8),
            headPosition: SIMD3(0, 1, 0.8),
            torsoAngle: 5,
            shoulderWidth: shoulderWidth,
            depthAvailable: false
        )
    }

    // MARK: - Tests

    func test_detectsStaleBaseline_afterSignificantShift() {
        // shoulderWidthRaw=0.5 vs baseline.shoulderWidth=0.3 → shift = 0.2/0.3 ≈ 0.667 > 0.30
        let sample = makeSample(shoulderWidthRaw: 0.5)
        let baseline = makeBaseline(shoulderWidth: 0.3)

        let result = sut.check(current: sample, baseline: baseline, baselineAge: 1800)

        guard case .positionShifted(let percent) = result else {
            return XCTFail("Expected .positionShifted, got \(result)")
        }
        XCTAssertGreaterThan(percent, 0.30)
    }

    func test_detectsStaleBaseline_afterTimeout() {
        let sample = makeSample(shoulderWidthRaw: 0.3)
        let baseline = makeBaseline(shoulderWidth: 0.3)

        let result = sut.check(current: sample, baseline: baseline, baselineAge: 4000)

        guard case .timeExpired(let age) = result else {
            return XCTFail("Expected .timeExpired, got \(result)")
        }
        XCTAssertEqual(age, 4000)
    }

    func test_returnsFresh_whenWithinTolerances() {
        // Small diff (0.32 vs 0.3 = 6.7% < 30%) and age within 1 hour
        let sample = makeSample(shoulderWidthRaw: 0.32)
        let baseline = makeBaseline(shoulderWidth: 0.3)

        let result = sut.check(current: sample, baseline: baseline, baselineAge: 1800)

        XCTAssertEqual(result, .fresh)
    }

    func test_detectsBothStale_whenShiftedAndExpired() {
        let sample = makeSample(shoulderWidthRaw: 0.5)
        let baseline = makeBaseline(shoulderWidth: 0.3)

        let result = sut.check(current: sample, baseline: baseline, baselineAge: 4000)

        guard case .bothStale(let percent, let age) = result else {
            return XCTFail("Expected .bothStale, got \(result)")
        }
        XCTAssertGreaterThan(percent, 0.30)
        XCTAssertEqual(age, 4000)
    }
}
