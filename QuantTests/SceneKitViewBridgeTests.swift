import XCTest
import SceneKit
import PostureLogic
@testable import Quant

final class SceneKitViewBridgeTests: XCTestCase {

    // MARK: - PostureSceneBuilder: Body Scene Creation

    func test_makeBodyScene_returnsNonNilScene() {
        let scene = PostureSceneBuilder.makeBodyScene()
        XCTAssertNotNil(scene, "makeBodyScene should return a non-nil scene")
    }

    func test_makeBodyScene_hasExpectedNamedNodes() {
        let scene = PostureSceneBuilder.makeBodyScene()
        let expectedNames = ["head", "neck", "spine", "chest", "leftShoulder", "rightShoulder", "pelvis"]
        for name in expectedNames {
            let node = scene.rootNode.childNode(withName: name, recursively: true)
            XCTAssertNotNil(node, "Scene should contain a node named '\(name)'")
        }
    }

    // MARK: - PostureSceneBuilder: Deformation

    func test_applyPostureDeformation_doesNotThrow_allZero() {
        let scene = PostureSceneBuilder.makeBodyScene()
        let data = makeTestData(fc: 0, hd: 0, sr: 0, ll: 0, tw: 0)
        PostureSceneBuilder.applyPostureDeformation(to: scene, data: data)
        // Simply verifying no crash
    }

    func test_applyPostureDeformation_doesNotThrow_allMax() {
        let scene = PostureSceneBuilder.makeBodyScene()
        let data = makeTestData(fc: 2.0, hd: 2.0, sr: 2.0, ll: 2.0, tw: 2.0)
        PostureSceneBuilder.applyPostureDeformation(to: scene, data: data)
        // Simply verifying no crash at extreme values
    }

    func test_forwardCreep_rotatesSpine() {
        let scene = PostureSceneBuilder.makeBodyScene()

        // Apply zero deformation and capture spine rotation
        let zeroData = makeTestData(fc: 0, hd: 0, sr: 0, ll: 0, tw: 0)
        PostureSceneBuilder.applyPostureDeformation(to: scene, data: zeroData)
        let zeroAngle = scene.rootNode.childNode(withName: "spine", recursively: true)!.eulerAngles.x

        // Apply forwardCreep deformation
        let fcData = makeTestData(fc: 1.0, hd: 0, sr: 0, ll: 0, tw: 0)
        PostureSceneBuilder.applyPostureDeformation(to: scene, data: fcData)
        let fcAngle = scene.rootNode.childNode(withName: "spine", recursively: true)!.eulerAngles.x

        XCTAssertNotEqual(fcAngle, zeroAngle,
                          "Spine should have a non-zero eulerAngles.x after applying forwardCreep.ratio = 1.0")
    }

    func test_headDrop_rotatesHead() {
        let scene = PostureSceneBuilder.makeBodyScene()
        let data = makeTestData(fc: 0, hd: 1.0, sr: 0, ll: 0, tw: 0)
        PostureSceneBuilder.applyPostureDeformation(to: scene, data: data)
        let headAngle = scene.rootNode.childNode(withName: "head", recursively: true)!.eulerAngles.x
        XCTAssertNotEqual(headAngle, 0,
                          "Head should have non-zero rotation with headDrop.ratio = 1.0")
    }

    func test_shoulderRounding_movesShoulders() {
        let scene = PostureSceneBuilder.makeBodyScene()

        // Capture zero positions
        let zeroData = makeTestData(fc: 0, hd: 0, sr: 0, ll: 0, tw: 0)
        PostureSceneBuilder.applyPostureDeformation(to: scene, data: zeroData)
        let leftZero = scene.rootNode.childNode(withName: "leftShoulder", recursively: true)!.position.x
        let rightZero = scene.rootNode.childNode(withName: "rightShoulder", recursively: true)!.position.x
        let zeroWidth = abs(rightZero - leftZero)

        // Apply shoulder rounding
        let srData = makeTestData(fc: 0, hd: 0, sr: 1.0, ll: 0, tw: 0)
        PostureSceneBuilder.applyPostureDeformation(to: scene, data: srData)
        let leftSR = scene.rootNode.childNode(withName: "leftShoulder", recursively: true)!.position.x
        let rightSR = scene.rootNode.childNode(withName: "rightShoulder", recursively: true)!.position.x
        let srWidth = abs(rightSR - leftSR)

        XCTAssertLessThan(srWidth, zeroWidth,
                          "Shoulder width should decrease with shoulderRounding.ratio = 1.0")
    }

    // MARK: - Variant Registry Integration

    func test_variant32_hasTechTag() {
        let v32 = VariantRegistry.allVariants.first { $0.id == 32 }
        XCTAssertNotNil(v32)
        XCTAssertTrue(v32!.technologies.contains(.sceneKit),
                      "Variant 32 should have .sceneKit technology tag")
    }

    @MainActor
    func test_variant32_makeViewReturnsNonNil() {
        let v32 = VariantRegistry.allVariants.first { $0.id == 32 }
        XCTAssertNotNil(v32)
        let view = v32!.makeView()
        XCTAssertNotNil(view, "Variant 32 makeView() should return non-nil")
    }

    // MARK: - Helpers

    private func makeTestData(fc: Float, hd: Float, sr: Float, ll: Float, tw: Float) -> PostureDisplayData {
        let thresholds = PostureThresholds()
        let metrics = MetricKey.allCases.map { key -> MetricInfo in
            let value: Float
            let threshold: Float
            switch key {
            case .forwardCreep:
                value = fc * thresholds.forwardCreepThreshold
                threshold = thresholds.forwardCreepThreshold
            case .headDrop:
                value = hd * thresholds.headDropThreshold
                threshold = thresholds.headDropThreshold
            case .shoulderRounding:
                value = sr * thresholds.shoulderRoundingThreshold
                threshold = thresholds.shoulderRoundingThreshold
            case .lateralLean:
                value = ll * thresholds.sideLeanThreshold
                threshold = thresholds.sideLeanThreshold
            case .twist:
                value = tw * thresholds.twistThreshold
                threshold = thresholds.twistThreshold
            }
            let ratio = threshold > 0 ? abs(value) / threshold : 0
            return MetricInfo(
                key: key,
                value: value,
                ratio: ratio,
                threshold: threshold,
                isWorstOffender: false
            )
        }
        return PostureDisplayData(
            metrics: metrics,
            postureState: .good,
            nudgeDecision: .none,
            trackingQuality: .good,
            worstOffender: nil,
            timeInCurrentState: nil,
            nudgeCountdownSeconds: nil,
            thresholds: thresholds
        )
    }
}
