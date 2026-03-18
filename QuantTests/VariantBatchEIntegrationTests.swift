import XCTest
@testable import Quant

final class VariantBatchEIntegrationTests: XCTestCase {

    private var batchEVariants: [VariantDescriptor] {
        VariantRegistry.allVariants.filter { (29...40).contains($0.id) }
    }

    // MARK: - Count

    func test_batchE_has12Variants() {
        XCTAssertEqual(batchEVariants.count, 12)
    }

    // MARK: - IDs and Names

    func test_variant29_isSceneKitMannequin() {
        let v = batchEVariants.first { $0.id == 29 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "SceneKit Mannequin")
    }

    func test_variant30_isWireSkeleton() {
        let v = batchEVariants.first { $0.id == 30 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Wire Skeleton")
    }

    func test_variant31_isBodySilhouette() {
        let v = batchEVariants.first { $0.id == 31 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Body Silhouette")
    }

    func test_variant32_isMuscleHeatmap() {
        let v = batchEVariants.first { $0.id == 32 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Muscle Heatmap")
    }

    func test_variant33_isSpineColumn() {
        let v = batchEVariants.first { $0.id == 33 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Spine Column")
    }

    func test_variant34_isMirrorAvatar() {
        let v = batchEVariants.first { $0.id == 34 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Mirror Avatar")
    }

    func test_variant35_isAttitudeIndicator() {
        let v = batchEVariants.first { $0.id == 35 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Attitude Indicator")
    }

    func test_variant36_isSpiritLevel() {
        let v = batchEVariants.first { $0.id == 36 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Spirit Level")
    }

    func test_variant37_isGyroscopeRings() {
        let v = batchEVariants.first { $0.id == 37 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Gyroscope Rings")
    }

    func test_variant38_isCompassRose() {
        let v = batchEVariants.first { $0.id == 38 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Compass Rose")
    }

    func test_variant39_isOscilloscope() {
        let v = batchEVariants.first { $0.id == 39 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Oscilloscope")
    }

    func test_variant40_isLoadDiagram() {
        let v = batchEVariants.first { $0.id == 40 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Load Diagram")
    }

    // MARK: - Categories

    func test_variants29to34_areAnatomical() {
        let anatomical = batchEVariants.filter { (29...34).contains($0.id) }
        for v in anatomical {
            XCTAssertEqual(v.category, .anatomical,
                           "Variant \(v.id) (\(v.name)) should be anatomical")
        }
    }

    func test_variants35to40_areExperimental() {
        let experimental = batchEVariants.filter { (35...40).contains($0.id) }
        for v in experimental {
            XCTAssertEqual(v.category, .experimental,
                           "Variant \(v.id) (\(v.name)) should be experimental")
        }
    }

    // MARK: - makeView

    @MainActor
    func test_allBatchE_makeViewReturnsNonNil() {
        for variant in batchEVariants {
            let view = variant.makeView()
            XCTAssertNotNil(view, "Variant \(variant.id) (\(variant.name)) makeView() returned nil")
        }
    }

    // MARK: - Mannequin Joint Computation

    func test_mannequinJoints_headAboveShoulders_atZero() {
        let center = CGPoint(x: 200, y: 200)
        let joints = MannequinJoints.compute(
            center: center, scale: 1.0,
            fc: 0, hd: 0, sr: 0, ll: 0, tw: 0,
            isLandscape: false
        )
        // Head should be above shoulder midpoint
        let shoulderMidY = (joints.leftShoulder.y + joints.rightShoulder.y) / 2
        XCTAssertLessThan(joints.head.y, shoulderMidY,
                          "Head should be above shoulder midpoint when all metrics are zero")

        // Head should be roughly centered horizontally
        let shoulderMidX = (joints.leftShoulder.x + joints.rightShoulder.x) / 2
        XCTAssertEqual(joints.head.x, shoulderMidX, accuracy: 2.0,
                       "Head should be horizontally centered above shoulders when all metrics are zero")
    }

    func test_mannequinJoints_forwardCreep_displaces() {
        let center = CGPoint(x: 200, y: 200)
        let zeroJoints = MannequinJoints.compute(
            center: center, scale: 1.0,
            fc: 0, hd: 0, sr: 0, ll: 0, tw: 0,
            isLandscape: false
        )
        let forwardJoints = MannequinJoints.compute(
            center: center, scale: 1.0,
            fc: 1.0, hd: 0, sr: 0, ll: 0, tw: 0,
            isLandscape: false
        )
        // Head should be displaced forward (positive X) with forward creep
        XCTAssertGreaterThan(forwardJoints.head.x, zeroJoints.head.x,
                             "Head should move forward (positive X) with forward creep")
    }

    // MARK: - Oscilloscope Buffer

    func test_oscilloscopeBuffer_writesAndReads() {
        var buffer = OscilloscopeBuffer(capacity: 10)
        buffer.write(0.5)
        buffer.write(0.8)
        // Most recent write at offset capacity-1, second most recent at capacity-2
        XCTAssertEqual(buffer.read(offset: buffer.capacity - 1), 0.8, accuracy: 0.001)
    }

    func test_oscilloscopeBuffer_wrapsWithoutCrash() {
        var buffer = OscilloscopeBuffer(capacity: 5)
        // Write more than capacity
        for i in 0..<20 {
            buffer.write(Float(i))
        }
        // Should not crash and write head should wrap correctly
        XCTAssertEqual(buffer.writeHead, 0, "Write head should wrap to 0 after 20 writes to capacity-5 buffer")
        // Last 5 values should be 15,16,17,18,19
        XCTAssertEqual(buffer.data[4], 19, accuracy: 0.001)
        XCTAssertEqual(buffer.data[3], 18, accuracy: 0.001)
    }
}
