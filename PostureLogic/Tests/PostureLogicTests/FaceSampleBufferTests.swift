import XCTest
@testable import PostureLogic

final class FaceSampleBufferTests: XCTestCase {
    private func sample(_ t: TimeInterval, blink: Float = 0.1) -> FaceSample {
        FaceSample(t: t, tracked: true, eyeBlinkLeft: blink, eyeBlinkRight: blink,
                   jawOpen: 0.1, distance: 0.6)
    }

    func test_keepsOnlyThirtySeconds() {
        let buffer = FaceSampleBuffer()
        for i in 0..<400 { buffer.append(sample(Double(i) / 10)) }  // 40 s at 10 fps
        XCTAssertNil(buffer.summary(from: 0, to: 9))
        XCTAssertNotNil(buffer.summary(from: 20, to: 39.9))
    }

    func test_summaryMatchesPureFunction() {
        let buffer = FaceSampleBuffer()
        var all: [FaceSample] = []
        for i in 0..<300 {
            let t = Double(i) / 30
            let s = sample(t, blink: (120..<150).contains(i) ? 0.9 : 0.1)
            all.append(s)
            buffer.append(s)
        }
        XCTAssertEqual(buffer.summary(from: 0, to: 10), FaceSignals.summary(all, from: 0, to: 10))
    }

    func test_clear_empties() {
        let buffer = FaceSampleBuffer()
        buffer.append(sample(1))
        buffer.clear()
        XCTAssertNil(buffer.summary(from: 0, to: 10))
    }

    func test_concurrentAppendAndRead() {
        let buffer = FaceSampleBuffer()
        DispatchQueue.concurrentPerform(iterations: 1000) { i in
            buffer.append(sample(Double(i) / 100))
            _ = buffer.summary(from: 0, to: 10)
            if i % 250 == 0 { buffer.clear() }
        }
    }
}
