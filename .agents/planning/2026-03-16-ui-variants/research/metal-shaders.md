# Metal Shaders for SwiftUI: Comprehensive Research for Posture Visualization

## Table of Contents

1. [SwiftUI Shader Modifiers (iOS 17+)](#1-swiftui-shader-modifiers-ios-17)
2. [Metal Shading Language (MSL) Fundamentals](#2-metal-shading-language-msl-fundamentals)
3. [The Inferno Library](#3-the-inferno-library)
4. [Creative Shader Effects Catalog](#4-creative-shader-effects-catalog)
5. [Combining Shaders with SwiftUI Views](#5-combining-shaders-with-swiftui-views)
6. [Performance Characteristics](#6-performance-characteristics)
7. [WWDC Sessions on SwiftUI Shaders](#7-wwdc-sessions-on-swiftui-shaders)
8. [Posture Visualization Shader Concepts](#8-posture-visualization-shader-concepts)
9. [Implementation Patterns](#9-implementation-patterns)

---

## 1. SwiftUI Shader Modifiers (iOS 17+)

iOS 17 introduced three shader modifier types that bring GPU-powered visual effects directly into SwiftUI's declarative view system. These run on the device GPU using Metal Shading Language (MSL), enabling per-pixel manipulation at frame rate.

### 1.1 `.colorEffect()` -- Per-Pixel Color Transformation

**What it does:** Processes every visible pixel, receiving its position and current color, and returns a new color. Cannot read neighboring pixels.

**MSL function signature:**
```metal
[[ stitchable ]] half4 myColorEffect(float2 position, half4 color, args...)
```

**SwiftUI usage:**
```swift
Text("Posture Score: 87")
    .font(.title)
    .colorEffect(ShaderLibrary.myColorEffect(.float(intensity)))
```

**Parameters provided automatically:**
- `float2 position` -- pixel coordinate in user-space (points, not pixels)
- `half4 color` -- current RGBA color of the pixel (premultiplied alpha)

**Best for:** Color grading, tinting, noise overlays, infrared/thermal views, gradient fills, interlacing. Any effect that transforms color without needing to sample neighbors.

**Limitations:** Cannot read adjacent pixels. Cannot create blur, emboss, or displacement effects.

### 1.2 `.distortionEffect()` -- Per-Pixel Position Displacement

**What it does:** For each destination pixel on screen, returns which source pixel coordinate should be rendered there. This warps/distorts the view geometry.

**MSL function signature:**
```metal
[[ stitchable ]] float2 myDistortion(float2 position, args...)
```

**SwiftUI usage:**
```swift
Text("Lean: 12 degrees")
    .distortionEffect(
        ShaderLibrary.wave(.float(time), .float(amplitude)),
        maxSampleOffset: CGSize(width: 0, height: 20)
    )
```

**Parameters provided automatically:**
- `float2 position` -- the destination pixel in user-space

**Returns:** `float2` -- the source pixel coordinate to sample from

**Important:** `maxSampleOffset` tells SwiftUI how far pixels can be displaced. Setting this too small clips the effect; too large wastes memory.

**Best for:** Waves, ripples, barrel distortion, swirl, wobble, water surfaces, heat haze.

### 1.3 `.layerEffect()` -- Full Layer Texture Access

**What it does:** Provides access to the entire rendered layer as a texture, allowing sampling of any pixel at any position. This is the most powerful modifier type.

**MSL function signature:**
```metal
#include <SwiftUI/SwiftUI_Metal.h>

[[ stitchable ]] half4 myLayerEffect(
    float2 position,
    SwiftUI::Layer layer,
    args...
)
```

**SwiftUI usage:**
```swift
VStack { /* posture dashboard content */ }
    .drawingGroup()
    .layerEffect(
        ShaderLibrary.pixellate(.float(pixelSize)),
        maxSampleOffset: .zero
    )
```

**Parameters provided automatically:**
- `float2 position` -- current pixel in user-space
- `SwiftUI::Layer layer` -- texture of the rendered view, sampled with `layer.sample(float2)`

**Best for:** Blur, emboss, pixellation, chromatic aberration (color planes), edge detection, frosted glass, any multi-sample effect.

---

## 2. Metal Shading Language (MSL) Fundamentals

### 2.1 Required File Structure

Every `.metal` file used with SwiftUI needs:

```metal
#include <metal_stdlib>
using namespace metal;

// For layerEffect shaders, also include:
#include <SwiftUI/SwiftUI_Metal.h>
```

The `[[ stitchable ]]` attribute marks functions as callable from SwiftUI. This tells the Metal compiler to make the function available for runtime stitching (composition).

### 2.2 Data Types

| Type | Description | Usage |
|------|-------------|-------|
| `float` | 32-bit float | Positions, time, math |
| `half` | 16-bit float | Colors, performance-critical math |
| `float2` | 2D vector (x, y) | Positions, UV coordinates |
| `float4` | 4D vector (x, y, z, w) | Bounding rects, extended coords |
| `half4` | 4D half-precision (r, g, b, a) | Colors |
| `uint2` | 2D unsigned integer | Grid positions |

**Swizzling:** Access components via `.x`, `.y`, `.z`, `.w` or `.r`, `.g`, `.b`, `.a`:
```metal
half4 color = half4(1.0, 0.5, 0.2, 1.0);
color.rgb;  // half3(1.0, 0.5, 0.2)
color.a;    // 1.0
color.rg;   // half2(1.0, 0.5)
```

### 2.3 Built-in Functions

**Trigonometric:**
- `sin(x)`, `cos(x)`, `tan(x)` -- wave generation, rotation
- `atan2(y, x)` -- angle from coordinates (useful for radial effects)

**Interpolation & Clamping:**
- `mix(a, b, t)` -- linear interpolation: `a * (1-t) + b * t`
- `smoothstep(edge0, edge1, x)` -- smooth Hermite interpolation
- `clamp(x, min, max)` -- constrain value to range
- `step(edge, x)` -- returns 0 if x < edge, else 1

**Math:**
- `fract(x)` -- fractional part (essential for noise)
- `floor(x)`, `ceil(x)`, `round(x)` -- rounding
- `fmod(x, y)` -- modulo (for wrapping time values)
- `abs(x)` -- absolute value
- `pow(x, y)` -- power function (contrast curves)
- `sqrt(x)` -- square root

**Vector:**
- `dot(a, b)` -- dot product (used in noise generation)
- `length(v)` -- vector magnitude
- `normalize(v)` -- unit vector
- `distance(a, b)` -- distance between two points
- `reflect(I, N)` -- reflection vector
- `refract(I, N, eta)` -- refraction vector

**Fast Math:**
- `fast::sin(x)`, `fast::cos(x)` -- reduced precision, higher throughput

**Constants:**
- `M_PI_F` -- pi (float)
- `M_PI_H` -- pi (half)
- `M_PI_2_F` -- pi/2

### 2.4 Passing Parameters from SwiftUI

SwiftUI uses dynamic member lookup on `ShaderLibrary`:

```swift
ShaderLibrary.myShader(
    .float(timeValue),           // float
    .float2(viewSize),           // float2 (from CGSize)
    .float2(CGPoint(x: 10, y: 20)),  // float2 (from CGPoint)
    .color(.red),                // half4 (converted from SwiftUI Color)
    .boundingRect,               // float4 (view's bounding rect: x, y, w, h)
    .image(myImage)              // texture2d (from Image)
)
```

**Parameter order must match the MSL function signature** (after the automatic parameters like position and color).

### 2.5 UV Coordinate Normalization

A standard first step in most shaders is normalizing pixel coordinates to 0...1 range:

```metal
// Using size parameter
float2 uv = position / size;

// Using bounding rect
float2 uv = position / bounds.zw;  // bounds = float4(x, y, width, height)

// Centered coordinates (-1 to 1, with 0 at center)
float2 centered = uv * 2.0 - 1.0;
```

### 2.6 Common Pseudo-Random Function

The workhorse of procedural effects -- a hash function producing seemingly random values:

```metal
float random(float2 st) {
    return fract(sin(dot(st, float2(12.9898, 78.233))) * 43758.5453);
}
```

---

## 3. The Inferno Library

[Inferno](https://github.com/twostraws/Inferno) by Paul Hudson (Hacking with Swift) is an MIT-licensed open-source collection of Metal shaders designed specifically for SwiftUI. It requires iOS 17+ / macOS 14+ and MSL 3.1.

### 3.1 Complete Shader Inventory

#### Transformation Shaders (Applied to Existing Views)

| Shader | Type | Parameters | Visual Effect | Posture Use |
|--------|------|-----------|---------------|-------------|
| **Animated Gradient Fill** | colorEffect | size, time | Constantly cycling color gradient centered on view | Ambient background mood indicator |
| **Bubble** | layerEffect | size, position, radius | Soap bubble with refraction and specular highlights | Focus/magnification on problem areas |
| **Checkerboard** | colorEffect | size, color | Alternating grid of original and replacement color | Grid-based posture zone map |
| **Circle Wave** | colorEffect | size, time, brightness, speed, strength, density, center, color | Circular waves radiating from a point | Ripples emanating from pain points |
| **Color Planes** | layerEffect | offset (float2) | RGB channel separation (chromatic aberration) | Glitch effect on bad posture metrics |
| **Emboss** | layerEffect | strength | 3D embossing via directional brightness | Textural depth for posture silhouette |
| **Gradient Fill** | colorEffect | (none) | Static gradient | Baseline gradient overlay |
| **Infrared** | colorEffect | (none) | Thermal camera simulation (bright=red, dark=blue) | Heat-map style posture stress view |
| **Interlace** | colorEffect | width, color, strength | Horizontal interlacing lines (CRT-like) | Retro display for metrics |
| **Invert Alpha** | colorEffect | replacement color | Inverts alpha channel with replacement color | Mask-based visualizations |
| **Passthrough** | colorEffect | (none) | No change (identity shader) | Testing/debugging |
| **Rainbow Noise** | colorEffect | time | Dynamic multi-colored noise | Severe posture degradation indicator |
| **Recolor** | colorEffect | replacement color | Solid color fill respecting alpha | Simple status coloring |
| **Relative Wave** | distortionEffect | size, time, speed, smoothing, strength | Wave that intensifies from left to right | Progressive distortion based on metric severity |
| **Shimmer** | colorEffect | size, time, duration, width, lightness | Diagonal shimmer sweep across view | Achievement/good-posture celebration |
| **Simple Loupe** | layerEffect | size, touch, distance, zoom | Circular magnification at touch point | Detail zoom on body region |
| **Warping Loupe** | layerEffect | size, touch, distance, zoom | Glass orb magnification with warping | Organic magnification effect |
| **Water** | distortionEffect | size, time, speed, strength, frequency | Sine/cosine rippling distortion | Calm water (good) to choppy (bad) |
| **Wave** | distortionEffect | time, speed, smoothing, strength | Uniform sine wave distortion | Wobble on degraded metrics |
| **White Noise** | colorEffect | time | Dynamic grayscale noise (TV static) | Signal degradation metaphor |

#### Generation Shaders (Create New Visuals)

| Shader | Type | Parameters | Visual Effect |
|--------|------|-----------|---------------|
| **Light Grid** | colorEffect | size, time, density, speed, groupSize, brightness | Grid of flashing, color-cycling lights |
| **Sinebow** | colorEffect | size, time | 10 twisting sine-wave lines cycling through rainbow colors |

#### Blur Shaders

| Shader | Type | Parameters | Visual Effect |
|--------|------|-----------|---------------|
| **Variable Gaussian Blur** | layerEffect | bounds, radius, maxSamples, mask texture, axis, normalizeEdges | Per-pixel variable radius Gaussian blur using mask texture |

#### Transition Shaders (View Transitions)

| Shader | Parameters | Visual Effect |
|--------|-----------|---------------|
| **Circle** | -- | Circular wipe transition |
| **Circle Wave** | -- | Circular wipe with wave distortion |
| **Crosswarp** | -- | Cross-warping morph |
| **Diamond** | -- | Diamond-shaped wipe |
| **Diamond Wave** | -- | Diamond wipe with wave |
| **Genie** | -- | macOS-style genie suck effect |
| **Pixellate** | -- | Pixellation transition |
| **Radial** | -- | Radial sweep transition |
| **Swirl** | -- | Spiral swirl transition |
| **Wind** | -- | Horizontal wind sweep |

### 3.2 Key Implementation Patterns from Inferno

**Water Shader (distortionEffect):**
```metal
[[ stitchable ]] float2 water(
    float2 position, float2 size, float time,
    float speed, float strength, float frequency
) {
    float2 uv = position / size;
    float adjustedSpeed = time * speed * 0.05;
    float adjustedStrength = strength / 100.0;

    // Wrap phase to prevent numerical instability
    const float TWO_PI = 6.28318530718;
    float phase = fmod(adjustedSpeed * frequency, TWO_PI);

    float argX = frequency * uv.x + phase;
    float argY = frequency * uv.y + phase;
    uv.x += fast::sin(argX) * adjustedStrength;
    uv.y += fast::cos(argY) * adjustedStrength;

    return uv * size;
}
```

**Color Planes / Chromatic Aberration (layerEffect):**
```metal
[[ stitchable ]] half4 colorPlanes(
    float2 position, SwiftUI::Layer layer, float2 offset
) {
    float2 red = position - (offset * 2.0);
    float2 blue = position - offset;
    half4 color = layer.sample(position);
    color.r = layer.sample(red).r;
    color.b = layer.sample(blue).b;
    return color * color.a;
}
```

**Infrared / Thermal View (colorEffect):**
```metal
[[ stitchable ]] half4 infrared(float2 position, half4 color) {
    if (color.a > 0) {
        half3 cold = half3(0.0, 0.0, 1.0);    // Blue
        half3 medium = half3(1.0, 1.0, 0.0);  // Yellow
        half3 hot = half3(1.0, 0.0, 0.0);     // Red

        half3 grayValues = half3(0.2125, 0.7154, 0.0721);
        half luma = dot(color.rgb, grayValues);

        half3 newColor;
        if (luma < 0.5) {
            newColor = mix(cold, medium, luma / 0.5);
        } else {
            newColor = mix(medium, hot, (luma - 0.5) / 0.5);
        }
        return half4(newColor, 1.0) * color.a;
    }
    return color;
}
```

---

## 4. Creative Shader Effects Catalog

### 4.1 Ripple / Wave Distortions

**Complexity:** Easy | **Visual Impact:** Moderate-Dramatic

Sine-based displacement is the simplest distortion effect and one of the most versatile for data-driven visualization.

```metal
// Simple wave: intensity driven by posture score
[[ stitchable ]] float2 postureWave(
    float2 position, float time, float intensity
) {
    // intensity: 0.0 (perfect posture) to 1.0 (terrible posture)
    float amplitude = intensity * 15.0;
    float frequency = mix(30.0, 8.0, intensity); // tighter waves when worse
    float speed = mix(2.0, 6.0, intensity);      // faster when worse

    position.y += sin(time * speed + position.x / frequency) * amplitude;
    position.x += cos(time * speed * 0.7 + position.y / frequency) * amplitude * 0.5;
    return position;
}
```

**SwiftUI Integration:**
```swift
TimelineView(.animation) { context in
    PostureDashboard()
        .drawingGroup()
        .distortionEffect(
            ShaderLibrary.postureWave(
                .float(elapsed),
                .float(postureIntensity) // 0.0 = calm, 1.0 = chaotic
            ),
            maxSampleOffset: CGSize(width: 15, height: 15)
        )
}
```

### 4.2 Chromatic Aberration

**Complexity:** Easy | **Visual Impact:** Moderate

Separates RGB channels, creating a "broken display" or "glitch" look that intensifies with data deviation.

```metal
#include <SwiftUI/SwiftUI_Metal.h>

[[ stitchable ]] half4 chromaticAberration(
    float2 position, SwiftUI::Layer layer,
    float intensity  // 0.0 to 1.0
) {
    // Scale offset by intensity -- more deviation = more separation
    float offset = intensity * 8.0;

    // Offset direction based on position relative to center
    float2 dir = normalize(position - float2(200.0, 200.0));

    half4 color = layer.sample(position);
    color.r = layer.sample(position + dir * offset * 2.0).r;
    color.b = layer.sample(position - dir * offset).b;

    return color * color.a;
}
```

### 4.3 Glitch / Digital Noise Effects

**Complexity:** Easy-Medium | **Visual Impact:** Dramatic

Combines noise with block-based displacement for a "corrupted signal" aesthetic.

```metal
[[ stitchable ]] half4 glitchNoise(
    float2 position, half4 color,
    float time, float intensity
) {
    if (color.a == 0.0h) return color;

    // Block-based noise that changes per frame
    float blockY = floor(position.y / 8.0);
    float noise = fract(sin(dot(float2(blockY, floor(time * 20.0)),
                   float2(12.9898, 78.233))) * 43758.5453);

    // Only glitch some blocks, more often at higher intensity
    if (noise > (1.0 - intensity * 0.3)) {
        // RGB shift within the block
        float shift = (noise - 0.5) * intensity * 40.0;
        half r = fract(sin(dot(position + shift, float2(12.9898, 78.233))) * 43758.5453);
        half g = fract(sin(dot(position, float2(12.9898, 78.233))) * 43758.5453);
        half b = fract(sin(dot(position - shift, float2(12.9898, 78.233))) * 43758.5453);

        return mix(color, half4(r, g, b, 1.0h), half(intensity * 0.6)) * color.a;
    }

    return color;
}
```

### 4.4 Organic Flowing Patterns (Aurora / Lava Lamp)

**Complexity:** Medium | **Visual Impact:** Dramatic

Uses layered simplex noise with time-varying colors to create organic, flowing patterns.

```metal
// Simplex noise helper (simplified 2D)
float simplexNoise2D(float2 st) {
    const float F2 = 0.366025404;
    const float G2 = 0.211324865;

    float s = (st.x + st.y) * F2;
    float2 i = floor(st + s);
    float t = (i.x + i.y) * G2;
    float2 x0 = st - (i - t);

    float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float2 x1 = x0 - i1 + G2;
    float2 x2 = x0 - 1.0 + 2.0 * G2;

    // Gradient contributions
    auto grad = [](float2 p) -> float2 {
        float angle = fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453) * 6.28318;
        return float2(cos(angle), sin(angle));
    };

    float n0 = max(0.0, 0.5 - dot(x0, x0));
    n0 = n0 * n0 * n0 * n0 * dot(grad(i), x0);

    float n1 = max(0.0, 0.5 - dot(x1, x1));
    n1 = n1 * n1 * n1 * n1 * dot(grad(i + i1), x1);

    float n2 = max(0.0, 0.5 - dot(x2, x2));
    n2 = n2 * n2 * n2 * n2 * dot(grad(i + 1.0), x2);

    return 70.0 * (n0 + n1 + n2) * 0.5 + 0.5;
}

// Aurora / flowing pattern driven by posture state
[[ stitchable ]] half4 auroraFlow(
    float2 position, half4 color, float2 size,
    float time, float postureScore  // 0.0 = bad, 1.0 = good
) {
    if (color.a == 0.0h) return color;

    float2 uv = position / size;

    // Multiple noise octaves for organic flow
    float n1 = simplexNoise2D(uv * 3.0 + float2(time * 0.1, 0.0));
    float n2 = simplexNoise2D(uv * 5.0 + float2(0.0, time * 0.15));
    float n3 = simplexNoise2D(uv * 8.0 + float2(time * 0.08, time * 0.12));

    float combined = (n1 * 0.5 + n2 * 0.3 + n3 * 0.2);

    // Color palette shifts with posture score
    // Good posture: calm teals and greens
    // Bad posture: aggressive reds and oranges
    half3 goodColor1 = half3(0.1, 0.8, 0.6);  // Teal
    half3 goodColor2 = half3(0.2, 0.6, 0.9);  // Sky blue
    half3 badColor1 = half3(0.9, 0.2, 0.1);   // Red
    half3 badColor2 = half3(1.0, 0.6, 0.0);   // Orange

    half3 color1 = mix(badColor1, goodColor1, half(postureScore));
    half3 color2 = mix(badColor2, goodColor2, half(postureScore));

    half3 aurora = mix(color1, color2, half(combined));

    // Add brightness variation
    float brightness = 0.7 + 0.3 * sin(combined * 3.14159 + time);
    aurora *= half(brightness);

    return half4(aurora, 1.0h) * color.a;
}
```

### 4.5 Heat Distortion / Mirage Effect

**Complexity:** Easy-Medium | **Visual Impact:** Moderate

Simulates heat rising from a surface, creating wavy distortion that gets stronger with "heat" (bad posture).

```metal
[[ stitchable ]] float2 heatDistortion(
    float2 position, float2 size, float time,
    float intensity  // 0.0 to 1.0
) {
    float2 uv = position / size;

    // Heat rises, so distortion is stronger at the top
    float verticalFactor = 1.0 - uv.y;

    // Multiple sine waves at different frequencies for organic feel
    float distX = sin(uv.y * 20.0 + time * 3.0) * 0.5
                + sin(uv.y * 35.0 + time * 4.5) * 0.3
                + sin(uv.y * 50.0 + time * 2.0) * 0.2;

    float distY = cos(uv.x * 15.0 + time * 2.5) * 0.3;

    float strength = intensity * verticalFactor * 4.0;

    position.x += distX * strength;
    position.y += distY * strength * 0.3;

    return position;
}
```

### 4.6 CRT Scanline / Retro Display Effect

**Complexity:** Medium | **Visual Impact:** Moderate-Dramatic

Complete CRT monitor simulation with scanlines, barrel distortion, phosphor mask, and flicker.

```metal
#include <SwiftUI/SwiftUI_Metal.h>

float2 crtDistort(float2 uv, float strength) {
    float2 dist = 0.5 - uv;
    uv.x -= dist.y * dist.y * dist.x * strength;
    uv.y -= dist.x * dist.x * dist.y * strength;
    return uv;
}

[[ stitchable ]] half4 crtEffect(
    float2 position, SwiftUI::Layer layer,
    float time, float2 size
) {
    float2 uv = position / size;

    // Barrel distortion
    uv = crtDistort(uv, 0.3);
    float2 samplePos = uv * size;

    // Sample RGB channels with slight offset (phosphor simulation)
    half r = layer.sample(samplePos - float2(0.5, 0.0)).r;
    half g = layer.sample(samplePos).g;
    half b = layer.sample(samplePos + float2(0.5, 0.0)).b;

    half4 color = half4(r, g, b, 1.0h);

    // Boost brightness
    color.rgb *= half3(0.95, 1.05, 0.95) * 2.8h;

    // Animated scanlines
    half scanline = half(sin(3.5 * time + uv.y * size.y * 1.5));
    scanline = pow(scanline, 17.0h) * 0.15h;
    color.rgb -= scanline;

    // Subtle flicker
    color.rgb *= half(1.0 + 0.01 * sin(110.0 * time));

    // Phosphor mask (vertical RGB stripes)
    int pixelX = int(position.x) % 3;
    if (pixelX == 0) color.r *= 0.85h;
    if (pixelX == 2) color.b *= 0.85h;

    // Vignette (darken edges)
    float2 vigUV = uv * (1.0 - uv);
    float vig = vigUV.x * vigUV.y * 15.0;
    color.rgb *= half(pow(vig, 0.15));

    return color;
}
```

### 4.7 Voronoi / Cellular Patterns

**Complexity:** Medium-Hard | **Visual Impact:** Dramatic

Creates organic cell-like patterns useful for biological/health data visualization.

```metal
// Voronoi distance field
float2 voronoiCell(float2 p) {
    return fract(sin(float2(
        dot(p, float2(127.1, 311.7)),
        dot(p, float2(269.5, 183.3))
    )) * 43758.5453);
}

[[ stitchable ]] half4 voronoi(
    float2 position, half4 color, float2 size,
    float time, float scale, float postureScore
) {
    if (color.a == 0.0h) return color;

    float2 uv = position / size * scale;
    float2 cellPos = floor(uv);
    float2 localPos = fract(uv);

    float minDist = 1.0;
    float2 closestCell;

    // Check 3x3 neighborhood
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 neighbor = float2(x, y);
            float2 point = voronoiCell(cellPos + neighbor);

            // Animate cell centers
            point = 0.5 + 0.5 * sin(time * 0.5 + 6.2831 * point);

            float dist = length(neighbor + point - localPos);
            if (dist < minDist) {
                minDist = dist;
                closestCell = cellPos + neighbor;
            }
        }
    }

    // Color based on posture score
    half3 goodColor = half3(0.2, 0.8, 0.5);
    half3 badColor = half3(0.9, 0.15, 0.1);
    half3 cellColor = mix(badColor, goodColor, half(postureScore));

    // Edge highlight
    float edge = smoothstep(0.0, 0.05, minDist);
    cellColor *= half(edge);

    // Cell brightness variation
    float cellNoise = fract(sin(dot(closestCell, float2(12.9898, 78.233))) * 43758.5453);
    cellColor *= half(0.7 + 0.3 * cellNoise);

    return half4(cellColor, 1.0h) * color.a;
}
```

### 4.8 Fractal Noise (Perlin / Simplex / FBM)

**Complexity:** Medium | **Visual Impact:** Moderate-Dramatic

Fractal Brownian Motion creates layered noise for clouds, terrain, organic textures.

```metal
float valueNoise(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);

    float a = fract(sin(dot(i, float2(12.9898, 78.233))) * 43758.5453);
    float b = fract(sin(dot(i + float2(1.0, 0.0), float2(12.9898, 78.233))) * 43758.5453);
    float c = fract(sin(dot(i + float2(0.0, 1.0), float2(12.9898, 78.233))) * 43758.5453);
    float d = fract(sin(dot(i + float2(1.0, 1.0), float2(12.9898, 78.233))) * 43758.5453);

    float2 u = f * f * (3.0 - 2.0 * f); // smoothstep

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

[[ stitchable ]] half4 fbmTurbulence(
    float2 position, half4 color, float2 size,
    float time, float turbulence  // 0.0 = calm, 1.0 = chaotic
) {
    if (color.a == 0.0h) return color;

    float2 uv = position / size;

    float value = 0.0;
    float amplitude = 1.0;
    float frequency = 1.0;

    // More octaves = more detail/turbulence
    int octaves = int(mix(3.0, 8.0, turbulence));

    for (int i = 0; i < octaves; i++) {
        value += amplitude * valueNoise(
            uv * frequency * 4.0 + time * mix(0.05, 0.3, turbulence)
        );
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    value /= 2.0;

    // Map to color -- calm blues to angry reds
    half3 calmColor = half3(0.2, 0.4, 0.8);
    half3 angryColor = half3(0.9, 0.2, 0.05);
    half3 result = mix(calmColor, angryColor, half(turbulence));
    result *= half(value * (1.0 + turbulence));

    return half4(result, 1.0h) * color.a;
}
```

### 4.9 Variable Blur / Focus Effect

**Complexity:** Medium-Hard | **Visual Impact:** Moderate

Uses Gaussian blur with per-pixel radius control, driven by a mask texture.

```metal
// Simplified variable blur (for posture state)
[[ stitchable ]] half4 postureBlur(
    float2 position, SwiftUI::Layer layer,
    float4 bounds, float blurRadius
) {
    if (blurRadius < 1.0) return layer.sample(position);

    half4 sum = half4(0.0);
    half totalWeight = 0.0;
    int samples = int(min(blurRadius, 16.0));

    for (int x = -samples; x <= samples; x++) {
        for (int y = -samples; y <= samples; y++) {
            float2 offset = float2(x, y) * (blurRadius / float(samples));
            half weight = half(1.0 / (1.0 + length(offset)));
            sum += layer.sample(position + offset) * weight;
            totalWeight += weight;
        }
    }

    return sum / totalWeight;
}
```

A more performant approach: use Inferno's `variableBlur` shader with a mask texture that represents posture quality across the screen.

### 4.10 Color Grading / Mood Shift

**Complexity:** Easy | **Visual Impact:** Subtle-Moderate

Shift the entire color temperature of a view based on posture state.

```metal
// RGB to HSV conversion
float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

[[ stitchable ]] half4 postureMood(
    float2 position, half4 color,
    float warmth,     // -1.0 (cool/blue) to 1.0 (warm/red)
    float saturation, // 0.0 (desaturated) to 2.0 (vivid)
    float brightness  // 0.5 (dim) to 1.5 (bright)
) {
    if (color.a == 0.0h) return color;

    float3 hsv = rgb2hsv(float3(color.rgb));

    // Shift hue toward warm or cool
    hsv.x += warmth * 0.05;

    // Adjust saturation
    hsv.y = clamp(hsv.y * saturation, 0.0, 1.0);

    // Adjust brightness
    hsv.z = clamp(hsv.z * brightness, 0.0, 1.0);

    float3 rgb = hsv2rgb(hsv);
    return half4(half3(rgb), color.a);
}
```

**SwiftUI Integration with State-Driven Parameters:**
```swift
struct PostureMoodView: View {
    let postureScore: Double // 0.0 (worst) to 1.0 (best)

    var warmth: Double {
        // Good posture = warm, bad = cool/blue
        postureScore * 2.0 - 1.0
    }
    var saturation: Double {
        // More saturated at extremes
        0.8 + abs(postureScore - 0.5) * 0.8
    }

    var body: some View {
        PostureDashboard()
            .colorEffect(
                ShaderLibrary.postureMood(
                    .float(warmth),
                    .float(saturation),
                    .float(1.0)
                )
            )
    }
}
```

---

## 5. Combining Shaders with SwiftUI Views

### 5.1 Applicable to Any SwiftUI View

Shader modifiers work on **any SwiftUI view** -- Text, Image, Shapes, VStacks, complex layouts:

```swift
// Text
Text("Lean: 12.3 deg")
    .font(.title)
    .colorEffect(ShaderLibrary.infrared())

// SF Symbols
Image(systemName: "figure.stand")
    .font(.system(size: 200))
    .colorEffect(ShaderLibrary.animatedGradientFill(.float2(size), .float(time)))

// Shapes
RoundedRectangle(cornerRadius: 16)
    .fill(.blue)
    .distortionEffect(ShaderLibrary.water(...), maxSampleOffset: ...)

// Complex layouts (use .drawingGroup() first)
VStack {
    PostureMetrics()
    BodySilhouette()
    TrendChart()
}
.drawingGroup()  // Flatten to single layer first
.layerEffect(ShaderLibrary.emboss(.float(3)), maxSampleOffset: .zero)
```

### 5.2 Shader as ShapeStyle

Shaders conforming to `ShapeStyle` can be used with `foregroundStyle`:

```swift
let gradient = ShaderLibrary.animatedGradientFill(
    .float2(CGSize(width: 300, height: 300)),
    .float(elapsed)
)

Text("POSTURE SCORE")
    .font(.largeTitle.bold())
    .foregroundStyle(gradient)
```

### 5.3 Layering Multiple Shaders

You can chain multiple shader effects on the same view:

```swift
PostureDashboard()
    .drawingGroup()
    // Layer 1: Color grading based on posture state
    .colorEffect(
        ShaderLibrary.postureMood(.float(warmth), .float(saturation), .float(1.0))
    )
    // Layer 2: Distortion that increases with bad posture
    .distortionEffect(
        ShaderLibrary.postureWave(.float(time), .float(intensity)),
        maxSampleOffset: CGSize(width: 15, height: 15)
    )
    // Layer 3: Chromatic aberration for severe warnings
    .layerEffect(
        ShaderLibrary.colorPlanes(.float2(aberrationOffset)),
        maxSampleOffset: CGSize(width: 20, height: 20)
    )
```

**Important:** Each additional shader adds a rendering pass. Two or three layered shaders are fine for 60fps; more than that requires profiling.

### 5.4 Animation with TimelineView

The standard pattern for time-driven shader animation:

```swift
struct AnimatedShaderView: View {
    @State private var startTime = Date.now

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startTime)

            MyView()
                .visualEffect { content, proxy in
                    content
                        .colorEffect(
                            ShaderLibrary.myShader(
                                .float2(proxy.size),
                                .float(elapsed),
                                .float(someDataValue)
                            )
                        )
                }
        }
    }
}
```

Key components:
- `TimelineView(.animation)` drives 60fps (or 120fps on ProMotion) updates
- `.visualEffect` provides `proxy.size` for the view dimensions
- `elapsed` time creates smooth continuous animation
- App state values (posture scores, etc.) can be mixed in as parameters

### 5.5 State-Driven Shader Parameters

Shader parameters can be driven by any SwiftUI state:

```swift
struct PostureShaderView: View {
    @ObservedObject var posture: PostureMonitor

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startTime)

            DashboardView()
                .distortionEffect(
                    ShaderLibrary.water(
                        .float2(size),
                        .float(elapsed),
                        .float(3),                          // speed
                        .float(posture.overallDeviation),   // strength from data
                        .float(10)                          // frequency
                    ),
                    maxSampleOffset: CGSize(width: 20, height: 20)
                )
        }
    }
}
```

### 5.6 Shader Pre-compilation (iOS 18+)

iOS 18 added the ability to pre-compile shaders to avoid first-frame hitches:

```swift
let shader = ShaderLibrary.myEffect(.float(10), .color(.blue))
try await shader.compile(as: .colorEffect)
```

---

## 6. Performance Characteristics

### 6.1 Frame Rate Capabilities

- **60fps is readily achievable** on all iOS 17+ devices for typical fragment shaders
- **120fps** achievable on ProMotion devices (iPhone 13 Pro+, all iPhone 14 Pro+, iPhone 15+)
- Metal shaders run on the GPU, which is optimized for massively parallel per-pixel computation
- Simple color effects (tinting, noise, gradient) have negligible performance impact
- Distortion effects are slightly more expensive due to coordinate remapping
- Layer effects with multi-sample operations (blur, emboss) are most expensive

### 6.2 Performance Guidelines

| Technique | Cost | Notes |
|-----------|------|-------|
| Simple `colorEffect` | Very Low | Per-pixel math only, no texture reads |
| `distortionEffect` | Low | Returns new coordinate, one implicit sample |
| `layerEffect` (single sample) | Low | One `layer.sample()` call |
| `layerEffect` (multi-sample) | Medium-High | Each `layer.sample()` is a texture read |
| Gaussian blur (16 samples) | High | 16+ texture reads per pixel |
| Nested loops in shader | Variable | Scale with loop count |
| Multiple chained shaders | Additive | Each adds a render pass |

### 6.3 Optimization Tips

1. **Use `half` precision** for color math -- it is faster on mobile GPUs:
   ```metal
   half4 color = ...;  // Prefer half4 over float4 for colors
   ```

2. **Use `fast::sin()` and `fast::cos()`** when exact precision is not needed (visual effects are fine with reduced precision):
   ```metal
   uv.x += fast::sin(argX) * strength;
   ```

3. **Wrap time values** to prevent numerical instability with large floats:
   ```metal
   float phase = fmod(time * speed, 6.28318530718);
   ```

4. **Minimize texture samples** in layer effects -- each `layer.sample()` call is expensive

5. **Use `drawingGroup()`** before applying shaders to complex view hierarchies to flatten them into a single rasterized layer first

6. **Pre-compile shaders** on iOS 18+ to avoid first-frame jank

7. **Profile with Instruments** using the Metal System Trace template

8. **Avoid branching** in shaders where possible -- GPUs prefer uniform execution across pixels. Use `step()`, `mix()`, and `smoothstep()` instead of `if/else`:
   ```metal
   // Instead of:  if (x > 0.5) color = red; else color = blue;
   color = mix(blue, red, step(0.5, x));
   ```

### 6.4 Gotchas

- **`maxSampleOffset`** must be large enough to cover the maximum pixel displacement, or pixels will be clipped. But setting it too large wastes memory.
- **Console errors, not compiler errors:** MSL shader errors often show only as runtime console messages, not Xcode build errors. Watch the console carefully.
- **Parameter order matters:** SwiftUI parameters must match the MSL function signature exactly in order and count.
- **Alpha premultiplication:** SwiftUI colors are premultiplied alpha. When modifying colors, always factor in alpha:
  ```metal
  return half4(newColor, 1.0h) * color.a;  // Preserve alpha edges
  ```
- **Coordinate space is in points**, not pixels -- on Retina displays, 1 point = 2-3 pixels, but the shader receives point coordinates.

---

## 7. WWDC Sessions on SwiftUI Shaders

### WWDC23: Metal Shader Integration

iOS 17 introduced the three core shader modifiers (`colorEffect`, `distortionEffect`, `layerEffect`) and the `ShaderLibrary` API. The `[[ stitchable ]]` attribute was introduced for MSL functions to be callable from SwiftUI.

**Key APIs Introduced:**
- `View.colorEffect(_:isEnabled:)`
- `View.distortionEffect(_:maxSampleOffset:isEnabled:)`
- `View.layerEffect(_:maxSampleOffset:isEnabled:)`
- `ShaderLibrary`, `ShaderFunction`, `Shader`
- `.boundingRect` parameter type

### WWDC24: "Create Custom Visual Effects with SwiftUI" (Session 10151)

[Apple Developer Video](https://developer.apple.com/videos/play/wwdc2024/10151/)

This session covers five visual effect techniques:

1. **Scroll Effects** -- Using `.scrollTransition` and `.visualEffect` to create scroll-driven animations with access to `phase.value` and geometry proxy
2. **MeshGradient** -- New in iOS 18, a grid of control points with interpolated colors. Points can be animated for dynamic backgrounds:
   ```swift
   MeshGradient(
       width: 3, height: 3,
       points: [...],
       colors: [.black, .black, .black, .blue, .blue, .blue, .green, .green, .green]
   )
   ```
3. **Custom Transitions** -- `Transition` protocol with `body(content:phase:)` for Metal-powered view transitions
4. **TextRenderer** -- Custom text rendering with per-glyph control via `Text.Layout` and `GraphicsContext`
5. **Metal Shaders** -- Advanced GPU effects applied to SwiftUI views

### Relevant Documentation

- [Creating Visual Effects with SwiftUI](https://developer.apple.com/documentation/swiftui/creating-visual-effects-with-swiftui)
- [ShaderLibrary API Reference](https://developer.apple.com/documentation/swiftui/shaderlibrary)
- [Shader API Reference](https://developer.apple.com/documentation/swiftui/shader)

---

## 8. Posture Visualization Shader Concepts

### 8.1 Calm Gradient to Turbulent Chaos

**Complexity:** Medium | **Visual Impact:** Dramatic

A flowing gradient background that becomes increasingly turbulent as posture worsens.

```metal
[[ stitchable ]] half4 postureAmbience(
    float2 position, half4 color, float2 size,
    float time, float chaos  // 0.0 = serene, 1.0 = turbulent
) {
    if (color.a == 0.0h) return color;

    float2 uv = position / size;
    float2 centered = uv * 2.0 - 1.0;

    // Base angle for gradient rotation
    float angle = atan2(centered.y, centered.x);
    float radius = length(centered);

    // Noise distortion increases with chaos
    float noiseScale = mix(1.0, 6.0, chaos);
    float noiseSpeed = mix(0.1, 0.8, chaos);

    float n1 = sin(uv.x * noiseScale + time * noiseSpeed) *
               cos(uv.y * noiseScale * 1.3 + time * noiseSpeed * 0.7);
    float n2 = sin(uv.y * noiseScale * 1.5 + time * noiseSpeed * 1.2) *
               cos(uv.x * noiseScale * 0.8 + time * noiseSpeed * 0.9);

    float distortedAngle = angle + (n1 + n2) * chaos * 2.0;

    // Color palette: serene blues/greens shift to urgent reds/oranges
    half3 c1 = mix(half3(0.1, 0.3, 0.7), half3(0.8, 0.1, 0.05), half(chaos));
    half3 c2 = mix(half3(0.1, 0.7, 0.5), half3(1.0, 0.5, 0.0), half(chaos));
    half3 c3 = mix(half3(0.3, 0.5, 0.8), half3(0.9, 0.2, 0.1), half(chaos));

    half t = half(sin(distortedAngle + time * mix(0.3, 2.0, chaos)) * 0.5 + 0.5);
    half3 result = mix(mix(c1, c2, t), c3, half(radius * 0.5));

    // Brightness pulsing increases with chaos
    float pulse = 1.0 + sin(time * mix(1.0, 8.0, chaos)) * chaos * 0.15;
    result *= half(pulse);

    return half4(result, 1.0h) * color.a;
}
```

**Rating:** Complexity: Medium | Visual Impact: Dramatic | Implementation: 2-3 hours

### 8.2 Distorting Text on Threshold Breach

**Complexity:** Easy | **Visual Impact:** Moderate

Apply wave distortion to metric text when values exceed thresholds.

```swift
struct MetricDisplay: View {
    let value: Double
    let threshold: Double
    @State private var startTime = Date.now

    var isWarning: Bool { value > threshold }
    var intensity: Double { isWarning ? min((value - threshold) / threshold, 1.0) : 0.0 }

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startTime)

            Text(String(format: "%.1f deg", value))
                .font(.system(.title, design: .monospaced))
                .foregroundStyle(isWarning ? .red : .green)
                // Wave distortion
                .distortionEffect(
                    ShaderLibrary.wave(
                        .float(elapsed),
                        .float(isWarning ? 4.0 : 0.0),  // speed
                        .float(20),                        // smoothing
                        .float(intensity * 8.0)            // strength
                    ),
                    maxSampleOffset: CGSize(width: 0, height: 10)
                )
                // Optional: add noise overlay at extreme values
                .colorEffect(
                    ShaderLibrary.glitchNoise(
                        .float(elapsed),
                        .float(intensity)
                    ),
                    isEnabled: intensity > 0.5
                )
        }
    }
}
```

**Rating:** Complexity: Easy | Visual Impact: Moderate | Implementation: 1 hour

### 8.3 Serene Water Surface to Choppy Seas

**Complexity:** Easy | **Visual Impact:** Moderate-Dramatic

Uses Inferno's `water` shader directly, driven by posture quality.

```swift
struct WaterPostureView: View {
    let postureQuality: Double  // 0.0 (bad) to 1.0 (good)
    @State private var startTime = Date.now

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startTime)
            let badness = 1.0 - postureQuality

            PostureDashboard()
                .drawingGroup()
                .visualEffect { content, proxy in
                    content.distortionEffect(
                        ShaderLibrary.water(
                            .float2(proxy.size),
                            .float(elapsed),
                            .float(mix(1.0, 8.0, badness)),  // speed
                            .float(mix(0.5, 5.0, badness)),  // strength
                            .float(mix(5.0, 25.0, badness))  // frequency
                        ),
                        maxSampleOffset: CGSize(width: 10, height: 10)
                    )
                }
        }
    }
}
```

**Rating:** Complexity: Easy (uses Inferno directly) | Visual Impact: Moderate-Dramatic | Implementation: 30 minutes

### 8.4 Aurora / Northern Lights with Posture State Colors

**Complexity:** Medium-Hard | **Visual Impact:** Dramatic

A layered noise-based aurora that shifts color palette based on posture state.

```metal
[[ stitchable ]] half4 postureAurora(
    float2 position, half4 color, float2 size,
    float time, float postureScore
) {
    if (color.a == 0.0h) return color;

    float2 uv = position / size;

    // Vertical aurora bands
    float aurora1 = sin(uv.x * 8.0 + time * 0.3) * 0.5 + 0.5;
    float aurora2 = sin(uv.x * 12.0 + time * 0.5 + 2.0) * 0.5 + 0.5;
    float aurora3 = sin(uv.x * 6.0 + time * 0.2 + 4.0) * 0.5 + 0.5;

    // Vertical falloff -- aurora concentrated at top
    float verticalMask = smoothstep(0.8, 0.2, uv.y);

    // Noise for organic movement
    float n = fract(sin(dot(uv * 5.0 + time * 0.1, float2(12.9898, 78.233))) * 43758.5453);

    // Blend auroras
    float combined = (aurora1 * 0.5 + aurora2 * 0.3 + aurora3 * 0.2) * verticalMask;
    combined += n * 0.1;

    // Good posture: green/teal aurora
    half3 goodBase = half3(0.0, 0.9, 0.4);
    half3 goodAccent = half3(0.1, 0.5, 0.9);

    // Bad posture: red/purple aurora
    half3 badBase = half3(0.9, 0.1, 0.3);
    half3 badAccent = half3(0.6, 0.0, 0.8);

    half3 baseColor = mix(badBase, goodBase, half(postureScore));
    half3 accentColor = mix(badAccent, goodAccent, half(postureScore));

    half3 auroraColor = mix(baseColor, accentColor, half(aurora2));
    auroraColor *= half(combined);

    // Shimmer
    float shimmer = sin(time * 2.0 + uv.x * 20.0) * 0.1 + 0.9;
    auroraColor *= half(shimmer);

    return half4(auroraColor, half(combined * 0.8)) * color.a;
}
```

**Rating:** Complexity: Medium-Hard | Visual Impact: Dramatic | Implementation: 3-4 hours

### 8.5 Heartbeat / Pulse Shader

**Complexity:** Easy-Medium | **Visual Impact:** Moderate

A radial pulse that expands outward at a rhythm matching posture quality.

```metal
[[ stitchable ]] half4 heartbeatPulse(
    float2 position, half4 color, float2 size,
    float time, float bpm  // beats per minute, e.g. 60 = calm, 120 = alert
) {
    if (color.a == 0.0h) return color;

    float2 uv = position / size;
    float2 center = float2(0.5, 0.5);
    float dist = distance(uv, center);

    // Convert BPM to pulse frequency
    float freq = bpm / 60.0;

    // Create expanding ring
    float phase = fract(time * freq);
    float ring = abs(dist - phase * 0.8);
    float pulse = smoothstep(0.05, 0.0, ring);

    // Second ring (double-beat like a heartbeat)
    float phase2 = fract(time * freq + 0.15);
    float ring2 = abs(dist - phase2 * 0.8);
    float pulse2 = smoothstep(0.03, 0.0, ring2) * 0.6;

    float combinedPulse = max(pulse, pulse2);

    // Fade the ring as it expands
    combinedPulse *= (1.0 - phase);

    // Color: calm blue to urgent red based on BPM
    half alertLevel = half(clamp((bpm - 60.0) / 60.0, 0.0, 1.0));
    half3 pulseColor = mix(half3(0.2, 0.5, 0.9), half3(0.9, 0.1, 0.1), alertLevel);

    // Add pulse glow to existing color
    return color + half4(pulseColor * half(combinedPulse * 0.4), 0.0h);
}
```

**Rating:** Complexity: Easy-Medium | Visual Impact: Moderate | Implementation: 1-2 hours

### 8.6 Frosted Glass: Clear When Good, Frosted When Bad

**Complexity:** Medium | **Visual Impact:** Moderate

Combines Gaussian blur with posture-driven blur radius. Uses Inferno's variable blur or a custom implementation.

```swift
// Using Inferno's variableBlur with a generated mask
struct FrostedPostureView: View {
    let postureQuality: Double // 0.0 (bad/frosted) to 1.0 (good/clear)

    var blurRadius: CGFloat {
        CGFloat((1.0 - postureQuality) * 20.0)
    }

    var body: some View {
        ZStack {
            // Background content
            PostureDashboard()
                .drawingGroup()
                .blur(radius: blurRadius) // SwiftUI native blur, driven by posture

            // Foreground overlay with frost texture via shader
            Rectangle()
                .fill(.ultraThinMaterial) // Native frosted glass
                .opacity(1.0 - postureQuality)

            // Important metrics always visible
            VStack {
                Text("Posture Score")
                    .font(.headline)
                Text("\(Int(postureQuality * 100))%")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
            }
        }
    }
}
```

For a custom shader-only approach with more control:

```metal
#include <SwiftUI/SwiftUI_Metal.h>

[[ stitchable ]] half4 frostEffect(
    float2 position, SwiftUI::Layer layer,
    float2 size, float frostAmount  // 0.0 = clear, 1.0 = fully frosted
) {
    int radius = int(frostAmount * 12.0);
    if (radius < 1) return layer.sample(position);

    half4 sum = half4(0.0);
    float totalWeight = 0.0;

    for (int x = -radius; x <= radius; x++) {
        for (int y = -radius; y <= radius; y++) {
            float2 offset = float2(x, y);
            float weight = 1.0 / (1.0 + length(offset));
            sum += layer.sample(position + offset) * half(weight);
            totalWeight += weight;
        }
    }

    half4 blurred = sum / half(totalWeight);

    // Add slight noise for frost texture
    float noise = fract(sin(dot(position * 0.1, float2(12.9898, 78.233))) * 43758.5453);
    blurred.rgb += half(noise * frostAmount * 0.05);

    // Slight white tint for frost appearance
    blurred.rgb = mix(blurred.rgb, half3(0.95), half(frostAmount * 0.15));

    return blurred;
}
```

**Rating:** Complexity: Medium | Visual Impact: Moderate | Implementation: 2-3 hours

---

## 9. Implementation Patterns

### 9.1 Data-Driven Shader Parameter Mapping

The core pattern for connecting posture data to shader parameters:

```swift
struct PostureShaderBridge {
    let overallScore: Double     // 0.0 = worst, 1.0 = best
    let leanAngle: Double        // degrees
    let twistAngle: Double       // degrees
    let forwardCreep: Double     // distance in cm

    // Map to shader parameters
    var chaosIntensity: Float {
        Float(1.0 - overallScore)
    }

    var chromaticOffset: CGSize {
        let magnitude = max(abs(leanAngle), abs(twistAngle)) / 30.0
        return CGSize(width: magnitude * 5.0, height: magnitude * 3.0)
    }

    var waterTurbulence: Float {
        Float(min(1.0, (abs(leanAngle) + abs(twistAngle) + forwardCreep) / 50.0))
    }

    var warmth: Float {
        // Good = warm green, bad = cold blue then hot red
        if overallScore > 0.5 {
            return Float(overallScore - 0.5) * 2.0  // 0 to 1 (neutral to warm)
        } else {
            return Float(overallScore - 0.5) * 2.0  // -1 to 0 (cool to neutral)
        }
    }

    var pulseRate: Float {
        // Good posture = slow calm pulse, bad = rapid urgent pulse
        Float(60.0 + (1.0 - overallScore) * 80.0)  // 60-140 BPM
    }
}
```

### 9.2 Smooth Parameter Transitions

Avoid jarring visual jumps by smoothing shader parameter changes:

```swift
struct SmoothedShaderView: View {
    let rawIntensity: Double
    @State private var smoothedIntensity: Double = 0.0

    var body: some View {
        TimelineView(.animation) { context in
            MyView()
                .colorEffect(
                    ShaderLibrary.myEffect(.float(smoothedIntensity))
                )
        }
        .onChange(of: rawIntensity) { _, newValue in
            withAnimation(.easeInOut(duration: 0.5)) {
                smoothedIntensity = newValue
            }
        }
    }
}
```

### 9.3 Conditional Shader Application

Apply shaders only when needed for maximum performance:

```swift
PostureDashboard()
    .distortionEffect(
        ShaderLibrary.wave(
            .float(elapsed),
            .float(4.0),
            .float(20),
            .float(intensity * 5.0)
        ),
        maxSampleOffset: CGSize(width: 0, height: 10),
        isEnabled: intensity > 0.05  // Disable when negligible
    )
```

### 9.4 Complete Example: Multi-Layer Posture Visualization

```swift
struct PostureVisualizationView: View {
    @ObservedObject var monitor: PostureMonitor
    @State private var startTime = Date.now

    private var bridge: PostureShaderBridge {
        PostureShaderBridge(
            overallScore: monitor.overallScore,
            leanAngle: monitor.leanAngle,
            twistAngle: monitor.twistAngle,
            forwardCreep: monitor.forwardCreep
        )
    }

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = Float(context.date.timeIntervalSince(startTime))

            ZStack {
                // Background: Aurora/flowing gradient
                Rectangle()
                    .visualEffect { content, proxy in
                        content.colorEffect(
                            ShaderLibrary.postureAmbience(
                                .float2(proxy.size),
                                .float(elapsed),
                                .float(bridge.chaosIntensity)
                            )
                        )
                    }

                // Main content with layered effects
                VStack {
                    PostureMetricCards()
                    BodySilhouetteView()
                    TrendGraph()
                }
                .drawingGroup()
                // Water distortion based on posture quality
                .visualEffect { content, proxy in
                    content.distortionEffect(
                        ShaderLibrary.water(
                            .float2(proxy.size),
                            .float(elapsed),
                            .float(mix(1.0, 6.0, bridge.waterTurbulence)),
                            .float(mix(0.3, 4.0, bridge.waterTurbulence)),
                            .float(10)
                        ),
                        maxSampleOffset: CGSize(width: 10, height: 10),
                        isEnabled: bridge.waterTurbulence > 0.1
                    )
                }
                // Chromatic aberration at high deviation
                .layerEffect(
                    ShaderLibrary.colorPlanes(
                        .float2(bridge.chromaticOffset)
                    ),
                    maxSampleOffset: CGSize(width: 20, height: 20),
                    isEnabled: bridge.chaosIntensity > 0.6
                )

                // Heartbeat pulse overlay
                Rectangle()
                    .fill(.clear)
                    .visualEffect { content, proxy in
                        content.colorEffect(
                            ShaderLibrary.heartbeatPulse(
                                .float2(proxy.size),
                                .float(elapsed),
                                .float(bridge.pulseRate)
                            )
                        )
                    }
                    .allowsHitTesting(false)
            }
        }
    }
}
```

---

## Effects Summary Table

| Effect | Shader Type | Complexity | Visual Impact | Best For |
|--------|-------------|-----------|---------------|----------|
| Wave distortion | distortionEffect | Easy | Moderate | Text wobble on threshold breach |
| Water ripple | distortionEffect | Easy | Moderate-Dramatic | Calm-to-choppy background |
| Chromatic aberration | layerEffect | Easy | Moderate | Glitch on bad metrics |
| Color grading / mood | colorEffect | Easy | Subtle-Moderate | Warm/cool tint shift |
| White/Rainbow noise | colorEffect | Easy | Moderate | Signal degradation metaphor |
| Infrared thermal | colorEffect | Easy | Moderate | Heat-map overlay |
| Interlace/CRT | colorEffect + layerEffect | Medium | Moderate | Retro display aesthetic |
| Shimmer | colorEffect | Easy | Subtle | Good posture reward |
| Animated gradient | colorEffect | Easy | Moderate | Ambient background |
| Heartbeat pulse | colorEffect | Easy-Medium | Moderate | Rhythmic urgency indicator |
| Heat distortion | distortionEffect | Easy-Medium | Moderate | Mirage/haze warning |
| Emboss | layerEffect | Easy | Subtle | Textural depth |
| FBM turbulence | colorEffect | Medium | Moderate-Dramatic | Organic chaos background |
| Aurora / northern lights | colorEffect | Medium-Hard | Dramatic | Ambient state indicator |
| Voronoi cells | colorEffect | Medium-Hard | Dramatic | Biological/organic data viz |
| Frosted glass (blur) | layerEffect | Medium | Moderate | Clarity reward / obscurity warning |
| CRT full effect | layerEffect | Medium | Dramatic | Complete retro monitor |
| Sinebow flowing lines | colorEffect | Medium | Dramatic | Organic flowing background |
| Variable Gaussian blur | layerEffect | Medium-Hard | Moderate | Per-region focus control |
| Soap bubble | layerEffect | Medium-Hard | Dramatic | Refraction/magnification |

---

## Sources

- [Hacking with Swift: Layer Effects Tutorial](https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-metal-shaders-to-swiftui-views-using-layer-effects)
- [Inferno GitHub Repository (twostraws)](https://github.com/twostraws/Inferno)
- [Introducing Inferno -- Hacking with Swift](https://www.hackingwithswift.com/articles/262/introducing-inferno-metal-shaders-for-swiftui)
- [Metal in SwiftUI: How to Write Shaders -- Jacob Bartlett](https://blog.jacobstechtavern.com/p/metal-in-swiftui-how-to-write-shaders)
- [Create With Swift: Custom Parameters and Animation](https://www.createwithswift.com/custom-parameters-and-animation-with-metal-shaders/)
- [Metal for SwiftUI -- Alex Logan (WWDC23)](https://alexanderlogan.co.uk/blog/wwdc23/09-metal)
- [SwiftUI Shaders: Wave Effect -- Cindori](https://cindori.com/developer/swiftui-shaders-wave)
- [WWDC24: Create Custom Visual Effects with SwiftUI (10151)](https://developer.apple.com/videos/play/wwdc2024/10151/)
- [Metal Shaders Course: Randomness and Noise](https://www.metal.graphics/chapter6-randomness-noise)
- [Metal Shaders Course: Color Mathematics](https://www.metal.graphics/chapter3-color-mathematics)
- [CRT Effect Gist (Priva28)](https://gist.github.com/Priva28/c4becef12fd8dd399cc769f2c7a5c246)
- [ShaderLibrary API Documentation](https://developer.apple.com/documentation/swiftui/shaderlibrary)
- [Variablur: Variable Blur for SwiftUI (daprice)](https://github.com/daprice/Variablur)
