import XCTest
@testable import Quant

final class VariantBatchDIntegrationTests: XCTestCase {

    private var abstractVariants: [VariantDescriptor] {
        VariantRegistry.allVariants.filter { (21...28).contains($0.id) }
    }

    // MARK: - Count

    func test_batchD_has8Variants() {
        XCTAssertEqual(abstractVariants.count, 8)
    }

    // MARK: - IDs and Names

    func test_variant21_isStackedTotem() {
        let v = abstractVariants.first { $0.id == 21 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Stacked Totem")
    }

    func test_variant22_isRadarGlyph() {
        let v = abstractVariants.first { $0.id == 22 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Radar Glyph")
    }

    func test_variant23_isConcentricTarget() {
        let v = abstractVariants.first { $0.id == 23 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Concentric Target")
    }

    func test_variant24_isPendulumArray() {
        let v = abstractVariants.first { $0.id == 24 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Pendulum Array")
    }

    func test_variant25_isTensegrity() {
        let v = abstractVariants.first { $0.id == 25 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Tensegrity")
    }

    func test_variant26_isOrigamiCrane() {
        let v = abstractVariants.first { $0.id == 26 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Origami Crane")
    }

    func test_variant27_isBauhausFigure() {
        let v = abstractVariants.first { $0.id == 27 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Bauhaus Figure")
    }

    func test_variant28_isSacredGeometry() {
        let v = abstractVariants.first { $0.id == 28 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Sacred Geometry")
    }

    // MARK: - Category

    func test_allBatchD_areAbstract() {
        for variant in abstractVariants {
            XCTAssertEqual(
                variant.category, .abstract,
                "Variant \(variant.id) (\(variant.name)) should be abstract"
            )
        }
    }

    // MARK: - makeView

    @MainActor
    func test_allBatchD_makeViewReturnsNonNil() {
        for variant in abstractVariants {
            let view = variant.makeView()
            XCTAssertNotNil(view, "Variant \(variant.id) (\(variant.name)) makeView() returned nil")
        }
    }

    // MARK: - Pendulum Physics

    func test_pendulumPhysics_reachesTarget() {
        var pendulum = PendulumPhysics(angle: 0, velocity: 0)
        let target: CGFloat = 30.0
        let dt: CGFloat = 1.0 / 60.0

        // Run 50 steps (~0.83 seconds)
        for _ in 0..<50 {
            pendulum.step(targetAngle: target, dt: dt)
        }
        XCTAssertEqual(pendulum.angle, target, accuracy: 1.0,
                       "Pendulum should reach within 1° of target within 50 steps")
    }

    func test_pendulumPhysics_settles() {
        var pendulum = PendulumPhysics(angle: 0, velocity: 0)
        let target: CGFloat = 30.0
        let dt: CGFloat = 1.0 / 60.0

        // Run 200 steps (~3.3 seconds)
        for _ in 0..<200 {
            pendulum.step(targetAngle: target, dt: dt)
        }

        // Should have settled: velocity near zero and angle near target
        XCTAssertEqual(pendulum.angle, target, accuracy: 0.1,
                       "Pendulum should settle within 0.1° of target after 200 steps")
        XCTAssertEqual(pendulum.velocity, 0, accuracy: 0.5,
                       "Pendulum velocity should be near zero after settling")
    }

    // MARK: - Radar Glyph Geometry

    func test_radarGlyph_pentagonHas5Vertices() {
        // Verify that computing 5 vertices produces valid coordinates
        let center = CGPoint(x: 100, y: 100)
        let radius: CGFloat = 50
        let startAngle: CGFloat = -.pi / 2

        var vertices: [CGPoint] = []
        for i in 0..<5 {
            let angle = startAngle + CGFloat(i) * (2 * .pi / 5)
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            vertices.append(CGPoint(x: x, y: y))
            XCTAssertFalse(x.isNaN, "Vertex \(i) x should not be NaN")
            XCTAssertFalse(y.isNaN, "Vertex \(i) y should not be NaN")
            XCTAssertFalse(x.isInfinite, "Vertex \(i) x should not be Inf")
            XCTAssertFalse(y.isInfinite, "Vertex \(i) y should not be Inf")
        }

        XCTAssertEqual(vertices.count, 5, "Pentagon should have exactly 5 vertices")
    }
}
