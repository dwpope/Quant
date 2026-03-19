#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Utility Functions

/// Simple hash-based noise for procedural effects
static float hash(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

/// Smooth noise using bilinear interpolation of hashed grid values
static float smoothNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // smoothstep

    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

/// Fractional Brownian Motion — layered noise for organic patterns
static float fbm(float2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float2 shift = float2(100.0);

    for (int i = 0; i < octaves; i++) {
        value += amplitude * smoothNoise(p);
        p = p * 2.0 + shift;
        amplitude *= 0.5;
    }
    return value;
}

// MARK: - Wave Distortion (used by Variant 43: Water Surface)

/// Displaces UV coordinates using layered sine waves driven by five metric ratios.
/// Each metric contributes a wave with distinct frequency, direction, and amplitude.
/// Returns the source coordinate to sample for a given destination pixel.
[[ stitchable ]] float2 waveDistortion(
    float2 position,
    float time,
    float forwardCreep,
    float headDrop,
    float shoulderRounding,
    float lateralLean,
    float twist
) {
    float2 offset = float2(0.0);

    // Forward creep: longitudinal waves (top-to-bottom surge)
    offset.y += forwardCreep * 8.0 * sin(position.x * 0.02 + time * 1.5);
    offset.y += forwardCreep * 4.0 * sin(position.x * 0.035 + time * 2.3);

    // Head drop: irregular ripples from center
    float distFromCenter = length(position - float2(position.x, position.y)) * 0.01;
    offset.y += headDrop * 5.0 * sin(position.y * 0.04 + time * 1.8);
    offset.x += headDrop * 3.0 * cos(position.y * 0.03 + time * 1.2);

    // Shoulder rounding: pressure waves from left and right
    offset.x += shoulderRounding * 6.0 * sin(position.y * 0.025 + time * 2.0);
    offset.x += shoulderRounding * 3.0 * sin(position.y * 0.05 + time * 3.1);

    // Lateral lean: tilt effect (gradient shift)
    offset.x += lateralLean * 10.0 * sin(position.y * 0.015 + time * 0.8);

    // Twist: vortex/spiral distortion from center
    float angle = twist * 0.3 * sin(time * 0.7);
    float2 centered = position - float2(200.0, 400.0);
    float r = length(centered);
    float vortexStrength = twist * 15.0 / max(r * 0.05, 1.0);
    offset.x += vortexStrength * sin(r * 0.02 - time * 1.5);
    offset.y += vortexStrength * cos(r * 0.02 - time * 1.5);

    return position + offset;
}

// MARK: - Noise Color Effect (used by ambient glow variants)

/// Applies a domain-warped noise field to the current pixel color,
/// blending in a tinted noise at the given intensity.
[[ stitchable ]] half4 noiseColorEffect(
    float2 position,
    half4 currentColor,
    float time,
    float intensity,
    float hue
) {
    // Scale position for noise sampling
    float2 uv = position * 0.005;

    // Domain warping: distort UV with noise before sampling
    float warp = fbm(uv + float2(time * 0.1), 3);
    float2 warpedUV = uv + float2(warp * 0.5, warp * 0.3);

    // Sample noise at warped coordinates
    float n = fbm(warpedUV + float2(time * 0.05, time * 0.08), 4);

    // Convert hue to RGB (simplified HSV to RGB)
    float h = hue * 6.0;
    float c = 0.8; // saturation * value
    float x = c * (1.0 - abs(fmod(h, 2.0) - 1.0));
    float3 rgb;
    if (h < 1.0) rgb = float3(c, x, 0.0);
    else if (h < 2.0) rgb = float3(x, c, 0.0);
    else if (h < 3.0) rgb = float3(0.0, c, x);
    else if (h < 4.0) rgb = float3(0.0, x, c);
    else if (h < 5.0) rgb = float3(x, 0.0, c);
    else rgb = float3(c, 0.0, x);
    rgb += 0.2; // boost brightness

    // Blend noise color with the current pixel color
    half3 noiseColor = half3(rgb.x * n, rgb.y * n, rgb.z * n);
    half blendAmount = half(intensity * n);

    half4 result;
    result.rgb = mix(currentColor.rgb, noiseColor * currentColor.a, blendAmount);
    result.a = currentColor.a;

    return result;
}

// MARK: - Aurora Color Effect (used by Variant 47: Aurora Borealis)

/// Generates aurora borealis curtain effects with posture-driven parameters.
[[ stitchable ]] half4 auroraColorEffect(
    float2 position,
    half4 currentColor,
    float time,
    float2 size,
    float hueShift,
    float amplitude,
    float verticalPos,
    float horizontalCluster,
    float lateralOffset,
    float twistFactor
) {
    // Normalize coordinates
    float2 uv = position / size;

    // Curtain base positions (3 curtains)
    float curtainY = 0.2 + verticalPos * 0.3; // curtains move down with headDrop

    // Lateral offset shifts curtains to one side
    float xOffset = lateralOffset * 0.2;

    // Generate curtain shapes using layered sine waves
    float curtainIntensity = 0.0;
    for (int i = 0; i < 3; i++) {
        float freq = 2.0 + float(i) * 1.5;
        float phase = time * (0.3 + float(i) * 0.15);
        float twist = twistFactor * uv.y * 2.0;

        float curtainX = sin(uv.y * freq + phase + twist) * (0.15 - horizontalCluster * 0.1) + 0.5 + xOffset;
        float dist = abs(uv.x - curtainX);
        float width = 0.08 + amplitude * 0.06;
        float band = smoothstep(width, 0.0, dist);

        // Vertical fade (stronger at bottom of curtain, fading at top)
        float vertFade = smoothstep(curtainY - 0.3, curtainY, uv.y) * smoothstep(1.0, curtainY + 0.1, uv.y);
        curtainIntensity += band * vertFade * (0.5 + amplitude * 0.5);
    }

    curtainIntensity = min(curtainIntensity, 1.5);

    // Color: green (good) to purple to red (bad) based on hueShift
    float h = mix(0.35, 0.0, hueShift) * 6.0;
    float c = 0.9;
    float x = c * (1.0 - abs(fmod(h, 2.0) - 1.0));
    float3 rgb;
    if (h < 1.0) rgb = float3(c, x, 0.0);
    else if (h < 2.0) rgb = float3(x, c, 0.0);
    else if (h < 3.0) rgb = float3(0.0, c, x);
    else if (h < 4.0) rgb = float3(0.0, x, c);
    else if (h < 5.0) rgb = float3(x, 0.0, c);
    else rgb = float3(c, 0.0, x);

    // Add subtle noise to break up banding
    float noise = smoothNoise(position * 0.02 + float2(time * 0.3));
    curtainIntensity *= (0.8 + noise * 0.4);

    half3 auroraColor = half3(rgb) * half(curtainIntensity);
    half4 result;
    result.rgb = currentColor.rgb + auroraColor * currentColor.a;
    result.a = currentColor.a;

    return result;
}

// MARK: - Chromatic Aberration (used by Variant 50: Chromatic Split)

/// Splits RGB channels based on five metric-driven distortion modes.
[[ stitchable ]] half4 chromaticAberration(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float forwardCreep,
    float headDrop,
    float shoulderRounding,
    float lateralLean,
    float twist
) {
    float2 center = size * 0.5;
    float2 fromCenter = position - center;
    float dist = length(fromCenter);
    float angle = atan2(fromCenter.y, fromCenter.x);

    // Compute per-channel UV offsets
    float2 redOffset = float2(0.0);
    float2 blueOffset = float2(0.0);

    // Forward creep: radial chromatic aberration
    float radialStrength = forwardCreep * 8.0;
    float2 radialDir = normalize(fromCenter + float2(0.001));
    redOffset += radialDir * radialStrength;
    blueOffset -= radialDir * radialStrength;

    // Head drop: vertical channel separation
    redOffset.y += headDrop * 6.0;
    blueOffset.y -= headDrop * 6.0;

    // Shoulder rounding: barrel distortion (approximate)
    float barrelStrength = shoulderRounding * 0.0001;
    float2 barrelOffset = fromCenter * dist * barrelStrength;
    redOffset += barrelOffset;
    blueOffset -= barrelOffset * 0.5;

    // Lateral lean: horizontal channel separation
    redOffset.x += lateralLean * 7.0;
    blueOffset.x -= lateralLean * 7.0;

    // Twist: rotational channel separation
    float twistAngle = twist * 0.015;
    float cosT = cos(twistAngle);
    float sinT = sin(twistAngle);
    float2 rotatedR = float2(fromCenter.x * cosT - fromCenter.y * sinT,
                              fromCenter.x * sinT + fromCenter.y * cosT) + center;
    float2 rotatedB = float2(fromCenter.x * cos(-twistAngle) - fromCenter.y * sin(-twistAngle),
                              fromCenter.x * sin(-twistAngle) + fromCenter.y * cos(-twistAngle)) + center;

    // Sample each channel at its offset position
    half4 redSample = layer.sample(position + redOffset + (rotatedR - position) * twist);
    half4 greenSample = layer.sample(position);
    half4 blueSample = layer.sample(position + blueOffset + (rotatedB - position) * twist);

    half4 result;
    result.r = redSample.r;
    result.g = greenSample.g;
    result.b = blueSample.b;
    result.a = max(max(redSample.a, greenSample.a), blueSample.a);

    return result;
}

// MARK: - Glitch Block Displacement (used by Variant 51: Glitch Matrix)

/// Applies horizontal block displacement to simulate digital glitch/screen tearing.
[[ stitchable ]] float2 glitchDisplacement(
    float2 position,
    float time,
    float intensity,
    float tearSpeed
) {
    // Create block-based displacement
    float blockHeight = 8.0 + hash(float2(floor(time * 3.0), 0.0)) * 16.0;
    float blockIndex = floor(position.y / blockHeight);

    // Random displacement per block, modulated by intensity
    float displacement = hash(float2(blockIndex, floor(time * 5.0))) * 2.0 - 1.0;
    displacement *= intensity * 20.0;

    // Only displace some blocks (sparse glitch)
    float probability = hash(float2(blockIndex + 100.0, floor(time * 4.0)));
    displacement *= step(1.0 - intensity * 0.5, probability);

    // Vertical tear line
    float tearY = fmod(time * tearSpeed * 100.0, position.y + 500.0);
    float tearEffect = smoothstep(0.0, 30.0, abs(position.y - tearY));
    float tearDisplacement = (1.0 - tearEffect) * intensity * 15.0;

    return position + float2(displacement + tearDisplacement, 0.0);
}
