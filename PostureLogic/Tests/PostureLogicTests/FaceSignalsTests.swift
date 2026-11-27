import XCTest
@testable import PostureLogic

final class FaceSignalsTests: XCTestCase {
    private let dt = 1.0 / 60.0

    /// Samples from `start` for `seconds` at `fps`, every one built by `make`.
    private func run(from start: TimeInterval = 0, _ seconds: Double, fps: Double = 60,
                     blink: Float = 0.1, jaw: Float = 0.1, tracked: Bool = true,
                     distance: Float? = 0.6) -> [FaceSample] {
        let n = Int((seconds * fps).rounded())
        return (0..<n).map { i in
            FaceSample(t: start + Double(i) / fps, tracked: tracked, eyeBlinkLeft: blink,
                       eyeBlinkRight: blink, jawOpen: jaw, distance: distance)
        }
    }

    func test_openEyes_noClosure() throws {
        let s = try XCTUnwrap(FaceSignals.summary(run(10), from: 0, to: 10))
        XCTAssertEqual(try XCTUnwrap(s.eyesClosedShare), 0, accuracy: 0.0001)
        XCTAssertEqual(s.longBlinks, 0)
        XCTAssertNil(s.longestClosureMs)
        XCTAssertEqual(s.trackedShare, 1, accuracy: 0.001)
    }

    func test_narrowedEyes_notClosed() throws {
        let s = try XCTUnwrap(FaceSignals.summary(run(10, blink: 0.7), from: 0, to: 10))
        XCTAssertEqual(try XCTUnwrap(s.eyesClosedShare), 0, accuracy: 0.0001)
    }

    func test_shortBlink_countsInShare_notAsLong() throws {
        let samples = run(5) + run(from: 5, 0.15, blink: 0.9) + run(from: 5.15, 4.85)
        let s = try XCTUnwrap(FaceSignals.summary(samples, from: 0, to: 10))
        XCTAssertEqual(s.longBlinks, 0)
        XCTAssertEqual(Double(try XCTUnwrap(s.longestClosureMs)), 150, accuracy: 17)
        XCTAssertEqual(try XCTUnwrap(s.eyesClosedShare), 0.015, accuracy: 0.003)
    }

    func test_longBlink_counted() throws {
        let samples = run(5) + run(from: 5, 0.4, blink: 0.9) + run(from: 5.4, 4.6)
        let s = try XCTUnwrap(FaceSignals.summary(samples, from: 0, to: 10))
        XCTAssertEqual(s.longBlinks, 1)
        XCTAssertEqual(Double(try XCTUnwrap(s.longestClosureMs)), 400, accuracy: 17)
    }

    func test_unevenFrames_weighByTime() throws {
        let samples = run(1, blink: 0.9) + run(from: 1, 9, fps: 15)
        let s = try XCTUnwrap(FaceSignals.summary(samples, from: 0, to: 10))
        XCTAssertEqual(try XCTUnwrap(s.eyesClosedShare), 0.1, accuracy: 0.01)
    }

    func test_faceLostMidBlink_discarded() throws {
        let samples = run(2) + run(from: 2, 0.2, blink: 0.9)
            + run(from: 2.2, 0.3, tracked: false) + run(from: 2.5, 2.5)
        let s = try XCTUnwrap(FaceSignals.summary(samples, from: 0, to: 5))
        XCTAssertEqual(s.longBlinks, 0)
        XCTAssertNil(s.longestClosureMs)
        XCTAssertEqual(s.trackedShare, 4.7 / 5, accuracy: 0.01)
        // Closed 0.2 s of 4.7 s tracked.
        XCTAssertEqual(try XCTUnwrap(s.eyesClosedShare), 0.2 / 4.7, accuracy: 0.01)
    }

    func test_faceLostMidBlink_gapWithoutSamples_discarded() throws {
        let samples = run(2) + run(from: 2, 0.2, blink: 0.9) + run(from: 2.5, 2.5)
        let s = try XCTUnwrap(FaceSignals.summary(samples, from: 0, to: 5))
        XCTAssertEqual(s.longBlinks, 0)
    }

    func test_shortDropout_doesNotEndClosure() throws {
        let samples = run(2) + run(from: 2, 0.2, blink: 0.9) + run(from: 2.2, 0.1, tracked: false)
            + run(from: 2.3, 0.2, blink: 0.9) + run(from: 2.5, 2.5)
        let s = try XCTUnwrap(FaceSignals.summary(samples, from: 0, to: 5))
        XCTAssertEqual(s.longBlinks, 1)
    }

    func test_oneEyeClosed_isNotClosed() throws {
        let samples = (0..<600).map {
            FaceSample(t: Double($0) * dt, tracked: true, eyeBlinkLeft: 0.9, eyeBlinkRight: 0.2,
                       jawOpen: 0.1, distance: 0.6)
        }
        let s = try XCTUnwrap(FaceSignals.summary(samples, from: 0, to: 10))
        XCTAssertEqual(try XCTUnwrap(s.eyesClosedShare), 0, accuracy: 0.0001)
    }

    func test_yawn_heldTwoSeconds_countsOnce() throws {
        let long = run(1) + run(from: 1, 3, jaw: 0.7) + run(from: 4, 2)
        XCTAssertEqual(FaceSignals.summary(long, from: 0, to: 6)?.yawns, 1)
        let short = run(1) + run(from: 1, 1.5, jaw: 0.7) + run(from: 2.5, 3.5)
        XCTAssertEqual(FaceSignals.summary(short, from: 0, to: 6)?.yawns, 0)
    }

    func test_yawnInterruptedByLostFace_notCounted() throws {
        let samples = run(1) + run(from: 1, 1.5, jaw: 0.7) + run(from: 2.5, 0.5, tracked: false)
            + run(from: 3, 1.5, jaw: 0.7) + run(from: 4.5, 1.5)
        XCTAssertEqual(FaceSignals.summary(samples, from: 0, to: 6)?.yawns, 0)
    }

    func test_closureEnding_inNextWindow() throws {
        let samples = run(9.8) + run(from: 9.8, 0.5, blink: 0.9) + run(from: 10.3, 9.7)
        XCTAssertEqual(FaceSignals.summary(samples, from: 0, to: 10)?.longBlinks, 0)
        XCTAssertEqual(FaceSignals.summary(samples, from: 10, to: 20)?.longBlinks, 1)
    }

    func test_distanceSpread() throws {
        let samples = run(1, distance: 0.5) + run(from: 1, 1, distance: 0.6) + run(from: 2, 1, distance: 0.7)
        let s = try XCTUnwrap(FaceSignals.summary(samples, from: 0, to: 3))
        XCTAssertEqual(s.distanceLow, 0.5)
        XCTAssertEqual(s.distanceMedian, 0.6)
        XCTAssertEqual(s.distanceHigh, 0.7)
    }

    func test_untrackedOnly_hasNoShareOrDistance() throws {
        let s = try XCTUnwrap(FaceSignals.summary(run(2, tracked: false), from: 0, to: 2))
        XCTAssertEqual(s.trackedShare, 0)
        XCTAssertNil(s.eyesClosedShare)
        XCTAssertNil(s.distanceMedian)
    }

    func test_noSamples_nil() {
        XCTAssertNil(FaceSignals.summary([], from: 0, to: 10))
        XCTAssertNil(FaceSignals.summary(run(5), from: 10, to: 20))
    }

    // MARK: - Half-open window (from, to]

    func test_boundarySample_countsInOneWindowOnly() throws {
        // Closed eyes from 9.9 to 10.0 inclusive, one sample at exactly t = 10.
        let samples = run(9.9) + run(from: 9.9, 0.1, blink: 0.9)
            + [FaceSample(t: 10, tracked: true, eyeBlinkLeft: 0.9, eyeBlinkRight: 0.9, jawOpen: 0.1, distance: 0.6)]
            + run(from: 10 + dt, 10)
        let a = FaceSignals.summary(samples, from: 0, to: 10)
        let b = FaceSignals.summary(samples, from: 10, to: 20)
        let in10 = samples.filter { $0.t > 0 && $0.t <= 10 }.count
        let in20 = samples.filter { $0.t > 10 && $0.t <= 20 }.count
        XCTAssertEqual(in10 + in20, samples.filter { $0.t > 0 }.count)
        // The t = 10 sample is not in the second window: closure ends at 10 + dt, which is in it.
        XCTAssertEqual(try XCTUnwrap(b).longBlinks + (try XCTUnwrap(a)).longBlinks, 0)
        XCTAssertNil(try XCTUnwrap(a).longestClosureMs)  // the closure ends after 10
        XCTAssertEqual(try XCTUnwrap(b).longestClosureMs.map { Double($0) } ?? 0, 110, accuracy: 17)
        // Time share: the second window's first counted sample is the one after t = 10.
        XCTAssertEqual(try XCTUnwrap(b).trackedShare, 1, accuracy: 0.001)
        let onlyBoundary = [FaceSample(t: 10, tracked: true, eyeBlinkLeft: 0.1, eyeBlinkRight: 0.1, jawOpen: 0.1, distance: 0.6)]
        XCTAssertNil(FaceSignals.summary(onlyBoundary, from: 10, to: 20))
        XCTAssertNotNil(FaceSignals.summary(onlyBoundary, from: 0, to: 10))
    }

    func test_yawnAcrossBoundary_countedOnceInLaterWindow() throws {
        let samples = run(9.0) + run(from: 9.0, 2.5, jaw: 0.7) + run(from: 11.5, 8.5)
        let first = try XCTUnwrap(FaceSignals.summary(samples, from: 0, to: 10))
        let second = try XCTUnwrap(FaceSignals.summary(samples, from: 10, to: 20))
        XCTAssertEqual(first.yawns, 0)
        XCTAssertEqual(second.yawns, 1)
    }

    func test_samplesBeforeFrom_notInShares() throws {
        let before = run(5, blink: 0.9, tracked: false, distance: 0.3)
        let samples = before + run(from: 5, 5, distance: 0.8)
        let s = try XCTUnwrap(FaceSignals.summary(samples, from: 5, to: 10))
        XCTAssertEqual(try XCTUnwrap(s.eyesClosedShare), 0, accuracy: 0.0001)
        XCTAssertEqual(s.trackedShare, 1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.distanceLow), 0.8, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(s.distanceHigh), 0.8, accuracy: 0.0001)
    }
}
