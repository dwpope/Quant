import SwiftUI

// MARK: - Shader Availability

enum PostureShaderSupport {
    /// Whether Metal shader effects are available on this platform/device.
    static var isAvailable: Bool {
        if #available(iOS 17, *) {
            return true
        }
        return false
    }
}

// MARK: - View Extensions for Posture Shader Effects

@available(iOS 17, *)
extension View {
    /// Applies a wave distortion effect driven by posture metrics.
    /// Used by Variant 43 (Water Surface) for real-time water simulation.
    func postureWaveEffect(data: PostureDisplayData, time: TimeInterval) -> some View {
        self.distortionEffect(
            ShaderLibrary.waveDistortion(
                .float(Float(time)),
                .float(data.metric(for: .forwardCreep).clampedRatio),
                .float(data.metric(for: .headDrop).clampedRatio),
                .float(data.metric(for: .shoulderRounding).clampedRatio),
                .float(data.metric(for: .lateralLean).clampedRatio),
                .float(data.metric(for: .twist).clampedRatio)
            ),
            maxSampleOffset: CGSize(width: 30, height: 30)
        )
    }

    /// Applies a domain-warped noise color overlay driven by intensity and hue.
    /// Used by ambient variants for atmospheric glow effects.
    func postureNoiseEffect(intensity: Float, hue: Float, time: TimeInterval) -> some View {
        self.colorEffect(
            ShaderLibrary.noiseColorEffect(
                .float(Float(time)),
                .float(intensity),
                .float(hue)
            )
        )
    }

    /// Applies an aurora borealis color effect driven by posture metrics.
    /// Used by Variant 47 (Aurora Borealis).
    func postureAuroraEffect(data: PostureDisplayData, time: TimeInterval, size: CGSize) -> some View {
        let score = 1.0 - data.aggregateScore // 0 = good, 1 = bad
        return self.colorEffect(
            ShaderLibrary.auroraColorEffect(
                .float(Float(time)),
                .float2(Float(size.width), Float(size.height)),
                .float(score), // hue shift
                .float(data.metric(for: .forwardCreep).clampedRatio), // amplitude
                .float(data.metric(for: .headDrop).clampedRatio), // vertical position
                .float(data.metric(for: .shoulderRounding).clampedRatio), // horizontal clustering
                .float(data.metric(for: .lateralLean).clampedRatio), // lateral offset
                .float(data.metric(for: .twist).clampedRatio) // twist factor
            )
        )
    }

    /// Applies chromatic aberration driven by posture metrics.
    /// Used by Variant 50 (Chromatic Split).
    func postureChromaticEffect(data: PostureDisplayData, size: CGSize) -> some View {
        self.layerEffect(
            ShaderLibrary.chromaticAberration(
                .float2(Float(size.width), Float(size.height)),
                .float(data.metric(for: .forwardCreep).clampedRatio),
                .float(data.metric(for: .headDrop).clampedRatio),
                .float(data.metric(for: .shoulderRounding).clampedRatio),
                .float(data.metric(for: .lateralLean).clampedRatio),
                .float(data.metric(for: .twist).clampedRatio)
            ),
            maxSampleOffset: CGSize(width: 20, height: 20)
        )
    }

    /// Applies digital glitch displacement driven by intensity.
    /// Used by Variant 51 (Glitch Matrix).
    func postureGlitchEffect(intensity: Float, time: TimeInterval) -> some View {
        self.distortionEffect(
            ShaderLibrary.glitchDisplacement(
                .float(Float(time)),
                .float(intensity),
                .float(intensity * 0.5)
            ),
            maxSampleOffset: CGSize(width: 40, height: 0)
        )
    }
}

// MARK: - Fallback View Modifier

/// A view modifier that applies a shader effect when available,
/// or falls back to a simpler visual treatment on unsupported devices.
struct PostureShaderFallback<ShaderContent: View, FallbackContent: View>: View {
    let shaderContent: () -> ShaderContent
    let fallbackContent: () -> FallbackContent

    var body: some View {
        if PostureShaderSupport.isAvailable {
            shaderContent()
        } else {
            fallbackContent()
        }
    }
}
