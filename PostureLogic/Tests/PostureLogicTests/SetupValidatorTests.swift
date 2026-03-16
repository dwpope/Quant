import XCTest
import simd
@testable import PostureLogic

final class SetupValidatorTests: XCTestCase {

    var sut: SetupValidator!

    override func setUp() {
        super.setUp()
        sut = SetupValidator()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSample(
        depthMode: DepthMode = .depthFusion,
        shoulderMidpoint: SIMD3<Float> = SIMD3(0, 0, 0.8),
        shoulderWidthRaw: Float = 0.3,
        torsoAngle: Float = 5,
        headPosition: SIMD3<Float> = SIMD3(0, 1, 0.8),
        leftShoulder: SIMD3<Float> = SIMD3(-0.5, 0, 0.8),
        rightShoulder: SIMD3<Float> = SIMD3(0.5, 0, 0.8),
        trackingQuality: TrackingQuality = .good,
        timestamp: TimeInterval = 1.0,
        headForwardOffset: Float = 0,
        shoulderTwist: Float = 0
    ) -> PoseSample {
        PoseSample(
            timestamp: timestamp,
            depthMode: depthMode,
            headPosition: headPosition,
            shoulderMidpoint: shoulderMidpoint,
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            torsoAngle: torsoAngle,
            headForwardOffset: headForwardOffset,
            shoulderTwist: shoulderTwist,
            shoulderWidthRaw: shoulderWidthRaw,
            trackingQuality: trackingQuality
        )
    }

    // MARK: - Depth Mode Distance Tests

    func test_failsTooClose_depthMode() {
        let sample = makeSample(shoulderMidpoint: SIMD3(0, 0, 0.3))
        let result = sut.validate(sample: sample, baseline: nil)

        guard case .tooClose(let detail) = result else {
            return XCTFail("Expected .tooClose, got \(result)")
        }
        XCTAssertTrue(detail.contains("0.30"), "Detail should contain distance: \(detail)")
    }

    func test_failsTooFar_depthMode() {
        let sample = makeSample(shoulderMidpoint: SIMD3(0, 0, 2.0))
        let result = sut.validate(sample: sample, baseline: nil)

        guard case .tooFar(let detail) = result else {
            return XCTFail("Expected .tooFar, got \(result)")
        }
        XCTAssertTrue(detail.contains("2.00"), "Detail should contain distance: \(detail)")
    }

    // MARK: - 2D Mode Distance Tests

    func test_failsTooClose_2DMode() {
        let sample = makeSample(depthMode: .twoDOnly, shoulderWidthRaw: 0.6)
        let result = sut.validate(sample: sample, baseline: nil)

        guard case .tooClose(let detail) = result else {
            return XCTFail("Expected .tooClose, got \(result)")
        }
        XCTAssertTrue(detail.contains("0.60"), "Detail should contain width ratio: \(detail)")
    }

    func test_failsTooFar_2DMode() {
        let sample = makeSample(depthMode: .twoDOnly, shoulderWidthRaw: 0.1)
        let result = sut.validate(sample: sample, baseline: nil)

        guard case .tooFar(let detail) = result else {
            return XCTFail("Expected .tooFar, got \(result)")
        }
        XCTAssertTrue(detail.contains("0.10"), "Detail should contain width ratio: \(detail)")
    }

    // MARK: - Valid Range

    func test_passesValidRange() {
        let sample = makeSample(shoulderMidpoint: SIMD3(0, 0, 0.8))
        let result = sut.validate(sample: sample, baseline: nil)

        XCTAssertEqual(result, .valid)
    }

    // MARK: - Angle Check

    func test_failsBadAngle() {
        let sample = makeSample(torsoAngle: 35)
        let result = sut.validate(sample: sample, baseline: nil)

        guard case .badAngle(let detail) = result else {
            return XCTFail("Expected .badAngle, got \(result)")
        }
        XCTAssertTrue(detail.contains("35"), "Detail should contain angle: \(detail)")
    }

    // MARK: - Body Visibility

    func test_failsMissingUpperBody() {
        let sample = makeSample(trackingQuality: .lost)
        let result = sut.validate(sample: sample, baseline: nil)

        guard case .bodyNotFullyVisible = result else {
            return XCTFail("Expected .bodyNotFullyVisible, got \(result)")
        }
    }
}
