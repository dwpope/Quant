import XCTest
@testable import Quant

final class VariantBatchFIntegrationTests: XCTestCase {

    private var batchFVariants: [VariantDescriptor] {
        VariantRegistry.allVariants.filter { (41...46).contains($0.id) }
    }

    // MARK: - Count

    func test_batchF_has6Variants() {
        XCTAssertEqual(batchFVariants.count, 6)
    }

    // MARK: - IDs and Names

    func test_variant41_isWiltingPlant() {
        let v = batchFVariants.first { $0.id == 41 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Wilting Plant")
    }

    func test_variant42_isTreeOfLife() {
        let v = batchFVariants.first { $0.id == 42 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Tree of Life")
    }

    func test_variant43_isWaterSurface() {
        let v = batchFVariants.first { $0.id == 43 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Water Surface")
    }

    func test_variant44_isTerrainMap() {
        let v = batchFVariants.first { $0.id == 44 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Terrain Map")
    }

    func test_variant45_isWeatherSystem() {
        let v = batchFVariants.first { $0.id == 45 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Weather System")
    }

    func test_variant46_isCoralReef() {
        let v = batchFVariants.first { $0.id == 46 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Coral Reef")
    }

    // MARK: - Categories

    func test_variants41to46_areAmbient() {
        for v in batchFVariants {
            XCTAssertEqual(v.category, .ambient,
                           "Variant \(v.id) (\(v.name)) should be ambient")
        }
    }

    // MARK: - makeView

    @MainActor
    func test_allBatchF_makeViewReturnsNonNil() {
        for variant in batchFVariants {
            let view = variant.makeView()
            XCTAssertNotNil(view, "Variant \(variant.id) (\(variant.name)) makeView() returned nil")
        }
    }

    // MARK: - PlantGeometry

    func test_plantGeometry_atZero_stemMidOffsetIsZero() {
        let geo = PlantGeometry.from(fc: 0, hd: 0, sr: 0, ll: 0, tw: 0)
        XCTAssertEqual(geo.stemMidOffset(maxOffset: 100), 0,
                       "Stem should be straight (zero horizontal offset) when all metrics are zero")
    }

    func test_plantGeometry_forwardCreep_displacesStem() {
        let geo = PlantGeometry.from(fc: 1.0, hd: 0, sr: 0, ll: 0, tw: 0)
        let offset = geo.stemMidOffset(maxOffset: 100)
        XCTAssertGreaterThanOrEqual(offset, 90,
                                     "Stem mid offset should be >= 90% of maxOffset when forwardCreep is 1.0")
    }

    func test_plantGeometry_halfForwardCreep_displacesStemProportionally() {
        let geo = PlantGeometry.from(fc: 0.5, hd: 0, sr: 0, ll: 0, tw: 0)
        let offset = geo.stemMidOffset(maxOffset: 100)
        XCTAssertEqual(offset, 50, accuracy: 1,
                       "Stem mid offset should be ~50 when forwardCreep is 0.5 with maxOffset 100")
    }

    // MARK: - WeatherSystem RainDrop

    func test_rainDrop_staysInBounds_after10Seconds() {
        let viewHeight: CGFloat = 800
        var drops = (0..<30).map { i in
            RainDrop(
                id: i,
                x: CGFloat.random(in: 0...400),
                y: CGFloat.random(in: -40...viewHeight),
                speed: CGFloat.random(in: 3...8),
                length: CGFloat.random(in: 5...15)
            )
        }

        // Simulate 10 seconds at 30fps
        let dt: CGFloat = 1.0 / 30.0 * 60 // scaled dt matching the view
        let frames = 300 // 10 seconds * 30fps
        for _ in 0..<frames {
            for i in 0..<drops.count {
                drops[i].update(dt: dt, viewHeight: viewHeight, windAngle: 0.2)
            }
        }

        // All drops should be in valid range
        for drop in drops {
            XCTAssertGreaterThanOrEqual(drop.y, -40,
                                         "RainDrop y should not be below -40")
            XCTAssertLessThanOrEqual(drop.y, viewHeight + 20,
                                      "RainDrop y should not exceed viewHeight + 20")
        }
    }
}
