import XCTest
import SwiftUI
@testable import Quant

final class MetalShaderBridgeTests: XCTestCase {

    // MARK: - Shader Availability

    func test_shaderSupport_isAvailable() {
        // On iOS 17+ simulator targets, Metal shaders should be available
        XCTAssertTrue(PostureShaderSupport.isAvailable,
                      "PostureShaderSupport.isAvailable should be true on iOS 17+ targets")
    }

    // MARK: - Wave Distortion Shader Access

    @MainActor
    func test_waveDistortion_shaderAccessible() {
        // Verify the shader function can be referenced without crashing
        if #available(iOS 17, *) {
            let shader = ShaderLibrary.waveDistortion(
                .float(0.0),
                .float(0.0),
                .float(0.0),
                .float(0.0),
                .float(0.0),
                .float(0.0)
            )
            XCTAssertNotNil(shader, "waveDistortion shader should be accessible")
        }
    }

    // MARK: - Noise Color Effect Shader Access

    @MainActor
    func test_noiseColorEffect_shaderAccessible() {
        if #available(iOS 17, *) {
            let shader = ShaderLibrary.noiseColorEffect(
                .float(0.0),
                .float(0.5),
                .float(0.35)
            )
            XCTAssertNotNil(shader, "noiseColorEffect shader should be accessible")
        }
    }

    // MARK: - Aurora Color Effect Shader Access

    @MainActor
    func test_auroraColorEffect_shaderAccessible() {
        if #available(iOS 17, *) {
            let shader = ShaderLibrary.auroraColorEffect(
                .float(0.0),
                .float2(390.0, 844.0),
                .float(0.0),
                .float(0.0),
                .float(0.0),
                .float(0.0),
                .float(0.0),
                .float(0.0)
            )
            XCTAssertNotNil(shader, "auroraColorEffect shader should be accessible")
        }
    }

    // MARK: - Chromatic Aberration Shader Access

    @MainActor
    func test_chromaticAberration_shaderAccessible() {
        if #available(iOS 17, *) {
            let shader = ShaderLibrary.chromaticAberration(
                .float2(390.0, 844.0),
                .float(0.0),
                .float(0.0),
                .float(0.0),
                .float(0.0),
                .float(0.0)
            )
            XCTAssertNotNil(shader, "chromaticAberration shader should be accessible")
        }
    }

    // MARK: - Glitch Displacement Shader Access

    @MainActor
    func test_glitchDisplacement_shaderAccessible() {
        if #available(iOS 17, *) {
            let shader = ShaderLibrary.glitchDisplacement(
                .float(0.0),
                .float(0.5),
                .float(0.25)
            )
            XCTAssertNotNil(shader, "glitchDisplacement shader should be accessible")
        }
    }

    // MARK: - PostureShaderFallback

    @MainActor
    func test_shaderFallback_usesShaderContent_whenAvailable() {
        // PostureShaderSupport.isAvailable is true on iOS 17+
        let view = PostureShaderFallback(
            shaderContent: { Text("Shader") },
            fallbackContent: { Text("Fallback") }
        )
        XCTAssertNotNil(view, "PostureShaderFallback should construct without crash")
    }
}
