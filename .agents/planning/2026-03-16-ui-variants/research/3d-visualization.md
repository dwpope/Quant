# Research: 3D Human Body / Posture Visualization on iOS

**Date:** 2026-03-16
**Context:** Technical feasibility research for 3D/visual posture avatar variants in the Quant posture monitoring app (SwiftUI, iOS, Vision framework pipeline already in place).

---

## Summary

Five practical implementation paths exist for rendering a 3D human body or skeleton figure in a SwiftUI posture app:

1. **Programmatic SceneKit skeleton** — build a stick-figure mannequin from `SCNCylinder` / `SCNSphere` nodes and update joint rotations from Vision or ARKit pose data. Best for a lightweight, standalone (no AR camera) 3D figure. Recommended first choice for Quant variants.
2. **RealityKit + ARBodyAnchor** — attach a rigged USDZ character to a live rear-camera AR session. The skeleton mirrors a real person in real-time. Requires A12+ chip, live camera, and a compatible USDZ asset. Best for a "mirror your own body" AR variant.
3. **Vision `VNHumanBodyPose3DObservation`** — iOS 17+ API; extracts 3D joint positions from the front camera without ARKit. Feed directly into SceneKit nodes. Practical for Quant's front-camera pipeline.
4. **SwiftUI Canvas / SpriteKit** — 2D stick figure or silhouette overlay drawn frame-by-frame. Simplest to implement, lowest overhead, excellent for stylized/abstract variants.
5. **Custom Metal / Core Animation** — lowest-level; only warranted for specialized visual effects not achievable with SceneKit.

---

## 1. Programmatic SceneKit Skeleton (Recommended for Standalone 3D Variants)

### Concept

Build a human figure entirely from SceneKit geometric primitives — no imported model needed. Each joint is an `SCNSphere`; each bone is an `SCNCylinder` positioned and oriented between two joint positions. Update node rotations each frame from posture metric data.

### SwiftUI Integration

SceneKit integrates with SwiftUI via `UIViewRepresentable` wrapping an `SCNView`, or via the native `SceneView` (iOS 14+):

```swift
import SwiftUI
import SceneKit

struct PostureSceneView: UIViewRepresentable {
    @Binding var postureMetrics: PostureMetrics

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = buildSkeletonScene()
        scnView.backgroundColor = .clear
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = false
        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        // Called whenever postureMetrics binding changes.
        // Update node rotations/positions to reflect new pose.
        applyMetrics(postureMetrics, to: scnView.scene!)
    }
}
```

The `updateUIView` path is where posture data flows into the 3D scene — triggered by SwiftUI state changes whenever the pipeline publishes new metrics.

### Building Joints and Bones

**Joints (spheres):**
```swift
func makeSphereNode(radius: CGFloat = 0.04, color: UIColor = .white) -> SCNNode {
    let sphere = SCNSphere(radius: radius)
    sphere.firstMaterial?.diffuse.contents = color
    return SCNNode(geometry: sphere)
}
```

**Bones (cylinders between two 3D points):**
The key challenge is orienting a cylinder between two joint positions. The cylinder's natural axis is Y-up; use `SCNNode.look(at:up:localFront:)` to rotate it correctly:

```swift
func makeBoneNode(from posA: SCNVector3, to posB: SCNVector3,
                  radius: CGFloat = 0.015) -> SCNNode {
    let dx = posA.x - posB.x
    let dy = posA.y - posB.y
    let dz = posA.z - posB.z
    let distance = sqrt(dx*dx + dy*dy + dz*dz)

    let midpoint = SCNVector3(
        (posA.x + posB.x) / 2,
        (posA.y + posB.y) / 2,
        (posA.z + posB.z) / 2
    )

    let cylinder = SCNCylinder(radius: radius, height: CGFloat(distance))
    cylinder.radialSegmentCount = 6  // keep polygon count low
    cylinder.firstMaterial?.diffuse.contents = UIColor.systemBlue

    let node = SCNNode(geometry: cylinder)
    node.position = midpoint
    // Align cylinder axis toward posB
    node.look(at: posB,
              up: SCNVector3(0, 1, 0),
              localFront: SCNVector3(0, 1, 0))
    return node
}
```

Alternatively for thinner line rendering, use `SCNGeometryPrimitiveType.line` with a custom `SCNGeometrySource` (no radius, but line width is not controllable on Metal).

### Skeleton Node Hierarchy

A minimal posture-relevant skeleton (14 joints):

```
root (hip center)
├── spine
│   ├── neck
│   │   └── head
│   ├── leftShoulder
│   │   └── leftElbow
│   │       └── leftWrist
│   └── rightShoulder
│       └── rightElbow
│           └── rightWrist
├── leftHip
│   └── leftKnee
│       └── leftAnkle
└── rightHip
    └── rightKnee
        └── rightAnkle
```

Each node is an `SCNNode` at its anatomically correct offset. A dictionary `[String: SCNNode]` keyed by joint name enables fast lookup during update cycles.

### Applying Posture Metrics Without Raw Joint Data

Quant doesn't expose raw 3D joint positions to the UI layer — it exposes five high-level metrics. A programmatic skeleton driven by metrics (rather than raw pose) is the practical path:

```swift
func applyMetrics(_ metrics: PostureMetrics, to scene: SCNScene) {
    guard let skeleton = scene.rootNode.childNode(withName: "skeleton", recursively: false) else { return }

    // Forward creep: rotate torso forward around X axis
    let torsoNode = skeleton.childNode(withName: "spine", recursively: false)
    torsoNode?.eulerAngles.x = Float(metrics.shoulderRounding.delta) * forwardScale

    // Head drop: tilt head node downward
    let headNode = skeleton.childNode(withName: "head", recursively: true)
    headNode?.eulerAngles.x = Float(metrics.headDrop.delta) * headDropScale

    // Lateral lean: rotate root around Z axis
    skeleton.eulerAngles.z = Float(metrics.lateralLean.delta) * leanScale

    // Twist: rotate spine around Y axis
    let spineNode = skeleton.childNode(withName: "spine", recursively: false)
    spineNode?.eulerAngles.y = Float(metrics.twist.delta) * twistScale
}
```

Animate transitions with `SCNTransaction`:
```swift
SCNTransaction.begin()
SCNTransaction.animationDuration = 0.3
applyMetrics(metrics, to: scene)
SCNTransaction.commit()
```

### Performance Profile

- SceneKit with ~15 nodes and no physics: essentially zero CPU overhead.
- Safe to update at 60 fps via the SwiftUI state pipeline.
- Rendering is GPU-accelerated via Metal on all supported devices.

### References
- [SceneKit Documentation](https://developer.apple.com/documentation/scenekit)
- [SCNSkinner — skeletal animation](https://developer.apple.com/documentation/scenekit/scnskinner)
- [Drawing a line between two points in SceneKit (GitHub Gist)](https://gist.github.com/GrantMeStrength/62364f8a5d7ea26e2b97b37207459a10)
- [Building iOS Apps with SceneKit and 3D Graphics](https://reintech.io/blog/building-ios-apps-with-scenekit-and-3d-graphics)
- [Playing with SceneKit and Core Motion in SwiftUI](https://medium.com/@nunobarreto_69905/playing-with-scenekit-and-core-motion-in-swiftui-18b1978d0205)

---

## 2. RealityKit + ARBodyAnchor (AR Mirror Variant)

### Concept

Use `ARBodyTrackingConfiguration` to detect a person via the rear camera, then attach a rigged 3D character (`BodyTrackedEntity`) to the detected `ARBodyAnchor`. The character's skeleton is driven automatically by ARKit — no manual joint manipulation required.

### Requirements

- **Device:** A12 Bionic chip or later (iPhone XS / iPad Pro 2018+)
- **iOS:** 13.0+
- **Camera:** Rear-facing camera in live AR session
- **Asset:** A USDZ model rigged to the 91-joint ARKit skeleton naming convention

### Core API

```swift
import ARKit
import RealityKit

// In an ARView-based view controller:
func startBodyTracking() {
    guard ARBodyTrackingConfiguration.isSupported else { return }
    let config = ARBodyTrackingConfiguration()
    arView.session.run(config)
}

// ARSessionDelegate
func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
    for anchor in anchors {
        guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }
        attachCharacter(to: bodyAnchor)
    }
}

func attachCharacter(to bodyAnchor: ARBodyAnchor) {
    let anchorEntity = AnchorEntity(anchor: bodyAnchor)
    arView.scene.addAnchor(anchorEntity)

    Entity.loadBodyTrackedAsync(named: "character").sink(
        receiveCompletion: { _ in },
        receiveValue: { character in
            anchorEntity.addChild(character)
        }
    ).store(in: &cancellables)
}
```

Once attached, the character skeleton updates every frame automatically. ARKit provides:
- **`ARBodyAnchor.skeleton`** — `ARSkeleton3D` instance
- **`ARSkeleton3D.jointModelTransforms`** — array of `simd_float4x4` for all 91 joints (model-relative)
- **`ARSkeleton3D.jointLocalTransforms`** — parent-relative transforms
- **`modelTransform(for: ARSkeleton.JointName)`** — named joint lookup

### Accessing Raw Joints for Custom Visualization

If you need to drive your own geometry rather than a rigged character:

```swift
func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
    for anchor in anchors {
        guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }
        let skeleton = bodyAnchor.skeleton

        // Get transform for a specific named joint
        if let hipTransform = skeleton.modelTransform(for: .root) {
            // columns.3 = translation (position)
            let position = SIMD3<Float>(
                hipTransform.columns.3.x,
                hipTransform.columns.3.y,
                hipTransform.columns.3.z
            )
            updateNode(named: "hip", position: position)
        }

        // Or iterate all joints
        let allTransforms = skeleton.jointModelTransforms
        for (index, transform) in allTransforms.enumerated() {
            let pos = SCNVector3(transform.columns.3.x,
                                transform.columns.3.y,
                                transform.columns.3.z)
            updateJointNode(at: index, position: pos)
        }
    }
}
```

### ARSkeleton Joint Name Set (Key Joints)

The full ARKit skeleton has 91 joints, but 14 are the primary tracked joints:
- `root` (hips), `hips_joint`
- `spine_1_joint` through `spine_7_joint`
- `neck_1_joint` through `neck_4_joint`, `head_joint`
- `left_shoulder_1_joint`, `left_arm_joint`, `left_forearm_joint`, `left_hand_joint`
- `right_shoulder_1_joint`, `right_arm_joint`, `right_forearm_joint`, `right_hand_joint`
- `left_upLeg_joint`, `left_leg_joint`, `left_foot_joint`
- `right_upLeg_joint`, `right_leg_joint`, `right_foot_joint`

### USDZ Character Constraints

The USDZ model must follow Apple's 91-joint naming convention (same as the `robot.usdz` from Apple's WWDC19 sample). Key sources for compatible assets:
- **Apple's robot.usdz** — from WWDC19 body tracking sample (available in Apple's developer sample code download)
- **Reality Composer** — can set up body tracking rigs
- **Blender + Reality Converter** — export as USDZ with proper joint naming; see [blender-to-realitykit](https://github.com/radcli14/blender-to-realitykit)
- **CGTrader / Sketchfab** — some FBX models can be converted, but joint renaming is required

### SwiftUI Integration

RealityKit's `ARView` integrates via `UIViewRepresentable`. The native `RealityView` (iOS 18+) provides better SwiftUI integration but is limited to newer OS versions.

```swift
struct ARBodyTrackingView: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.setup(arView: arView)
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, ARSessionDelegate {
        var arView: ARView?
        var cancellables = Set<AnyCancellable>()
        // body tracking setup here
    }
}
```

### Open Source Reference

- [Reality-Dev/BodyTracking](https://github.com/Reality-Dev/BodyTracking) — Swift package that wraps ARKit/RealityKit body tracking. Provides `AnchorEntity(.body)` convenience and async character loading. iOS 15+, A12+.
- [nyerasi/body-tracking](https://github.com/nyerasi/body-tracking) — WWDC19 companion project, basic body segmentation and motion tracking.
- [fncischen/ARBodyTracking](https://github.com/fncischen/ARBodyTracking) — AR body tracking experiments.

### References
- [Capturing Body Motion in 3D — Apple Docs](https://developer.apple.com/documentation/arkit/capturing-body-motion-in-3d)
- [ARBodyAnchor — Apple Docs](https://developer.apple.com/documentation/arkit/arbodyanchor)
- [ARSkeleton3D — Apple Docs](https://developer.apple.com/documentation/arkit/arskeleton3d)
- [BodyTrackedEntity — Apple Docs](https://developer.apple.com/documentation/realitykit/bodytrackedentity)
- [Bringing People into AR — WWDC19](https://developer.apple.com/videos/play/wwdc2019/607/)
- [Body Tracking with ARKit — LightBuzz](https://lightbuzz.com/body-tracking-arkit/)
- [How to use motion capture on ARKit to compute posture angle — Medium](https://eorvain-app.medium.com/how-to-use-motion-capture-on-arkit-to-compute-posture-angle-c73d0a7f9bb3)

---

## 3. Vision `VNHumanBodyPose3DObservation` (Front Camera, No ARKit)

### Concept

iOS 17 introduced `VNDetectHumanBodyPose3DRequest` which returns 3D joint positions from a **single camera image** — no ARKit session, no AR anchor, no LiDAR required. This is the most relevant path for Quant since the app uses the **front camera** via AVFoundation/Vision (not ARKit).

### Key Characteristics

- **Works without ARKit or ARSession** — uses monocular depth estimation
- **17 joints** returned in 3D camera space
- **Coordinate frame:** depth along camera Z-axis; absolute metric scale requires LiDAR (ProMotion devices), otherwise proportional scale
- **`cameraOriginMatrix`** — provides camera position in world coordinates at capture time
- **Can project joints back to 2D** — useful for overlay on camera preview
- **Minimum iOS 17**, recommended A12+ for performance

### Joint Names (17 Joints)

```
Head group:    head, neck
Torso:         leftShoulder, rightShoulder, spine (root)
Left arm:      leftArm (shoulder), leftForearm (elbow), leftWrist
Right arm:     rightArm (shoulder), rightForearm (elbow), rightWrist
Left leg:      leftUpLeg (hip), leftLeg (knee), leftAnkle
Right leg:     rightUpLeg (hip), rightLeg (knee), rightAnkle
```

(`VNHumanBodyPose3DObservation.JointName` enum)

### Request Setup

```swift
import Vision

let request = VNDetectHumanBodyPose3DRequest { [weak self] request, error in
    guard let self,
          let observations = request.results as? [VNHumanBodyPose3DObservation],
          let observation = observations.first else { return }
    self.handlePose3D(observation)
}

// In your AVCaptureVideoDataOutputSampleBufferDelegate:
func captureOutput(_ output: AVCaptureOutput,
                   didOutput sampleBuffer: CMSampleBuffer,
                   from connection: AVCaptureConnection) {
    let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer)
    try? handler.perform([request])
}
```

### Accessing 3D Joint Positions

```swift
func handlePose3D(_ observation: VNHumanBodyPose3DObservation) {
    // Get all recognized joints
    guard let joints = try? observation.recognizedPoints(.all) else { return }

    // Access individual joint
    if let neck = joints[.neck] {
        // neck.position is simd_float4x4 — camera-relative transform
        let worldPosition = neck.position  // 4x4 transform matrix
        let translation = SIMD3<Float>(
            worldPosition.columns.3.x,
            worldPosition.columns.3.y,
            worldPosition.columns.3.z
        )
        // Feed translation into SceneKit node
    }

    // Body orientation estimate
    let cameraMatrix = observation.cameraOriginMatrix
}
```

### SceneKit Visualization from 3D Observations

This is exactly what Apple's WWDC23 sample demonstrates (session 111241). The approach:

1. For each recognized joint, extract the 3D position from the `simd_float4x4` transform
2. Place an `SCNSphere` node at that position
3. For each bone (pair of connected joints), create an `SCNCylinder` between them using the `lineBetweenNodes` function described in Section 1
4. Apply 90-degree pitch rotation to align cylinder geometry (SceneKit cylinders default to Y-up)
5. On each new observation, update node positions or recreate the skeleton

```swift
// WWDC23 pattern: pitch correction for SceneKit cylinder orientation
let cylinderNode = SCNNode(geometry: SCNCylinder(...))
cylinderNode.eulerAngles.x = Float.pi / 2  // Align to match skeleton direction
```

### Key Limitation: Depth Without LiDAR

On non-LiDAR devices, Z-depth is estimated — accurate enough for posture angles (lean, twist) but not absolute metric positions. For a visual avatar that "looks right," relative proportions are all that matter, so this is fine.

### Sample Project

- [gromb57/ios-wwdc23__DetectingHumanBodyPosesIn3DWithVision](https://github.com/gromb57/ios-wwdc23__DetectingHumanBodyPosesIn3DWithVision) — Apple's WWDC23 companion sample code. Renders a SceneKit skeleton overlay on the input image using `VNHumanBodyPose3DObservation`. This is the definitive reference implementation.

### References
- [VNHumanBodyPose3DObservation — Apple Docs](https://developer.apple.com/documentation/vision/vnhumanbodypose3dobservation)
- [Detecting human body poses in 3D with Vision — Apple Docs](https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-3d-with-vision)
- [Explore 3D body pose in Vision — WWDC23 session 111241](https://developer.apple.com/videos/play/wwdc2023/111241/)
- [Identifying 3D human body poses in images — Apple Docs](https://developer.apple.com/documentation/vision/identifying-3d-human-body-poses-in-images)

---

## 4. SwiftUI Canvas / SpriteKit for 2D Body Visualization

### SwiftUI Canvas (Strongly Recommended for 2D Variants)

The SwiftUI `Canvas` view provides immediate-mode drawing and is the right choice for a stylized 2D stick figure or body silhouette driven by posture metrics. It avoids the overhead of SceneKit for cases where 3D depth isn't needed.

**Key advantages:**
- Zero third-party dependencies
- Runs inside any `View`; composable with other SwiftUI elements
- Supports `TimelineView(.animation)` for continuous redraw at display refresh rate
- Performant: Canvas renders all drawing as a single GPU-composited layer

**Real-time animation pattern:**
```swift
struct PostureStickFigureView: View {
    let metrics: PostureMetrics

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                drawSkeleton(context: context, size: size, metrics: metrics)
            }
        }
    }

    func drawSkeleton(context: GraphicsContext, size: CGSize, metrics: PostureMetrics) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // Compute joint positions from metrics
        // Example: shift head based on headDrop metric
        let headPos = CGPoint(x: center.x, y: center.y - 120 + CGFloat(metrics.headDrop.delta) * 30)
        let shoulderMidY = center.y - 80
        let leftShoulder = CGPoint(x: center.x - 40, y: shoulderMidY)
        let rightShoulder = CGPoint(x: center.x + 40, y: shoulderMidY)

        // Forward creep: shift upper body forward (shrink visual depth via x-offset for 2D feel)
        let torsoOffset = CGFloat(metrics.forwardCreep.delta) * 20
        // Lateral lean: tilt entire figure
        // Apply as a rotation transform to the context

        context.withCGContext { cgCtx in
            cgCtx.translateBy(x: center.x, y: center.y)
            cgCtx.rotate(by: CGFloat(metrics.lateralLean.delta) * 0.3)
            cgCtx.translateBy(x: -center.x, y: -center.y)
        }

        // Draw bones as lines
        var bonePath = Path()
        bonePath.move(to: headPos)
        bonePath.addLine(to: CGPoint(x: center.x + torsoOffset, y: shoulderMidY))
        bonePath.addLine(to: CGPoint(x: center.x + torsoOffset, y: center.y + 40))
        // ... add arms and legs

        context.stroke(bonePath, with: .color(.primary), lineWidth: 3)

        // Draw joint circles
        context.fill(Circle().path(in: CGRect(x: headPos.x - 16, y: headPos.y - 16,
                                              width: 32, height: 32)),
                     with: .color(.primary))
    }
}
```

**Color-coding by state:**
```swift
let boneColor: Color = switch postureState {
    case .good:     .green
    case .drifting: .yellow
    case .bad:      .red
    default:        .secondary
}
```

**Canvas limitations:**
- No built-in animation scheduling — requires `TimelineView` wrapper
- Text rendering requires `context.draw(Text(...), at:)` — works but not as flexible
- No hit testing or interaction within the canvas

### SpriteKit Approach

SpriteKit is viable but adds unnecessary complexity vs. SwiftUI Canvas for a static/posed figure. SpriteKit's strengths (physics, game loops, particle systems) are not needed for a posture indicator. Use Canvas instead unless you want SpriteKit's particle effects for ambient animations.

If SpriteKit is specifically needed:
```swift
struct PostureSpriteView: UIViewRepresentable {
    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        let scene = PostureBodyScene(size: CGSize(width: 300, height: 500))
        view.presentScene(scene)
        return view
    }
    func updateUIView(_ view: SKView, context: Context) {}
}
```

Joints would be `SKShapeNode` circles; bones would be `SKShapeNode` with `.init(rectOf:)` or custom paths.

### References
- [Canvas — Apple Docs](https://developer.apple.com/documentation/swiftui/canvas)
- [Mastering Canvas in SwiftUI](https://swiftwithmajid.com/2023/04/11/mastering-canvas-in-swiftui/)
- [Advanced SwiftUI Animations — Part 5: Canvas](https://swiftui-lab.com/swiftui-animations-part5/)
- [TimelineView + Canvas — Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-custom-animated-drawings-with-timelineview-and-canvas)
- [iOS 14 Vision Body Pose — SwiftUI Workout App](https://betterprogramming.pub/ios-14-vision-body-pose-detection-count-squat-reps-in-a-workout-c88991f7cad4)

---

## 5. Metal / Core Animation (Lower-Level Approaches)

### Metal (`MTKView`)

Metal is warranted only for:
- Custom shader-driven body distortion effects (e.g., fluid mesh deformation based on posture)
- Real-time depth map visualization
- Very high particle count ambient effects (thousands of particles reacting to posture)

For a skeleton or body silhouette, Metal is overkill. SceneKit and Canvas both use Metal under the hood — you get Metal performance without writing shaders.

If pursued, the pattern is:
```swift
struct MetalBodyView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = context.coordinator
        return view
    }
    func makeCoordinator() -> MetalCoordinator { MetalCoordinator() }
}

class MetalCoordinator: NSObject, MTKViewDelegate {
    func draw(in view: MTKView) {
        // Custom vertex/fragment shaders for body rendering
    }
}
```

`CADisplayLink` is useful for synchronizing updates to display refresh in non-SwiftUI contexts, but `TimelineView(.animation)` in SwiftUI and SceneKit's built-in render loop handle this automatically.

### Core Animation

`CALayer` animations are appropriate for:
- Animating 2D body silhouette shape transitions (using `CAShapeLayer` with animated `path`)
- Smooth metric bar transitions
- Pulsing / glow effects on joint markers

A `CAShapeLayer` body outline that morphs its Bezier path as posture changes is achievable:
```swift
let bodyLayer = CAShapeLayer()
bodyLayer.path = buildBodyPath(for: metrics).cgPath
bodyLayer.strokeColor = UIColor.systemGreen.cgColor
bodyLayer.fillColor = UIColor.clear.cgColor

// Animate path change
let animation = CABasicAnimation(keyPath: "path")
animation.toValue = buildBodyPath(for: newMetrics).cgPath
animation.duration = 0.3
bodyLayer.add(animation, forKey: "morphBody")
```

Note: `CAShapeLayer` path morphing requires the same number of path control points in source and destination paths.

### References
- [Creating a custom Metal view — Apple Docs](https://developer.apple.com/documentation/metal/drawable_objects/creating_a_custom_metal_view)
- [CADisplayLink — Apple Docs](https://developer.apple.com/documentation/quartzcore/cadisplaylink)

---

## 6. Open-Source iOS Posture / Skeleton Visualization Projects

| Project | Framework | What it demonstrates | Notes |
|---|---|---|---|
| [gromb57/ios-wwdc23__DetectingHumanBodyPosesIn3DWithVision](https://github.com/gromb57/ios-wwdc23__DetectingHumanBodyPosesIn3DWithVision) | Vision + SceneKit | 3D skeleton overlay from `VNHumanBodyPose3DObservation` | Apple's official WWDC23 sample — definitive reference |
| [Reality-Dev/BodyTracking](https://github.com/Reality-Dev/BodyTracking) | RealityKit + ARKit | Convenient body tracking Swift package | High-level API, iOS 15+, A12+ required |
| [nyerasi/body-tracking](https://github.com/nyerasi/body-tracking) | ARKit + SceneKit | Body segmentation and motion tracking | WWDC19 companion, basic sphere-at-joints pattern |
| [SimformSolutionsPvtLtd/ARKit-Prototype](https://github.com/SimformSolutionsPvtLtd/ARKit-Prototype) | ARKit + SceneKit | Cylinder bones + sphere joints skeleton, posture analysis | Virtual skeleton mimicking user, angle calculations at joints |
| [quickpose/quickpose-ios-sdk](https://github.com/quickpose/quickpose-ios-sdk) | MediaPipe (wrapped) | Skeleton overlay + joint angles overlay | Third-party SDK, iOS 14+, commercial license |

---

## 7. USDZ Human Body Models

### Availability

| Source | Type | License | ARKit-Compatible |
|---|---|---|---|
| Apple's `robot.usdz` (WWDC19 sample) | Robot character | Apple sample code license | Yes — purpose-built for 91-joint ARKit rig |
| [Apple Quick Look Gallery](https://developer.apple.com/augmented-reality/quick-look/) | Misc objects (no human body) | Free for use | Not a body rig |
| CGTrader | Human body meshes (FBX/OBJ) | Varies (free + paid) | Requires conversion + joint renaming |
| Sketchfab | Human body meshes | Varies | Requires Blender retargeting |
| Reality Composer / RealityKit | Custom | N/A | Yes, if joints named correctly |

### Key Constraint for Body-Tracked USDZ

To use `BodyTrackedEntity`, the USDZ **must** contain a skeleton with joints named following Apple's 91-joint convention (derived from the USD Humanoid schema). There is no official free human-looking USDZ from Apple — only the robot. A custom asset requires:
1. Human mesh in Blender or Maya
2. Rigging with ARKit joint names (spine_1_joint, left_arm_joint, etc.)
3. Export via Reality Composer or `usdz_converter` CLI tool
4. Validate using Reality Composer's preview

### Practical Alternative: Programmatic Mannequin

For Quant's posture variants, a **programmatic SceneKit mannequin** (Section 1) sidesteps the USDZ dependency entirely. It renders immediately, has no asset pipeline, and is simpler to style (color, opacity, glow effects).

### References
- [Apple Quick Look Gallery](https://developer.apple.com/augmented-reality/quick-look/)
- [Custom 3D character model for RealityKit — Apple Forums](https://developer.apple.com/forums/thread/131453)
- [blender-to-realitykit](https://github.com/radcli14/blender-to-realitykit)
- [Awesome-RealityKit resources](https://github.com/divalue/Awesome-RealityKit)

---

## Recommendation for Quant UI Variants

Given Quant's architecture (front camera, Vision framework, SwiftUI, no ARKit dependency, mock-data variants), here is the recommended approach for each class of 3D/body variants:

### Variant Class A: Stylized 2D Figure (Simplest — Start Here)
- **Framework:** SwiftUI `Canvas` + `TimelineView`
- **Approach:** Draw a stick figure or rounded silhouette using `Path`. Apply affine transforms (rotation, translation) to body segments based on metric deltas. Animate transitions with explicit interpolation.
- **Effort:** Low. Pure SwiftUI, no additional frameworks.
- **Best for:** Variants 1–2 that need a body shape but not true 3D depth.

### Variant Class B: Programmatic 3D Mannequin (Best Balance)
- **Framework:** SceneKit via `UIViewRepresentable`
- **Approach:** Build a ~15-node skeleton from `SCNCylinder` + `SCNSphere`. Update node euler angles from posture metric deltas each frame via the `updateUIView` binding path. Use `SCNTransaction` for smooth animation.
- **Effort:** Medium. One reusable `PostureSkeletonScene.swift` that any variant can instantiate.
- **Best for:** Variants wanting true 3D rotation/depth cues without an AR camera requirement.

### Variant Class C: Live Body Mirror (Most Impressive, Highest Complexity)
- **Framework:** RealityKit + ARKit body tracking
- **Approach:** `ARBodyTrackingConfiguration` + `BodyTrackedEntity` or custom sphere-at-joints rendering. Requires switching to rear camera.
- **Effort:** High. Requires A12+ device, rear camera, USDZ asset, `ARView` integration.
- **Best for:** One "wow factor" variant that shows the user's own skeleton in AR.

### Variant Class D: Front Camera 3D Overlay (Vision-Only)
- **Framework:** Vision `VNHumanBodyPose3DObservation` + SceneKit
- **Approach:** Feed from existing Vision pipeline into `VNDetectHumanBodyPose3DRequest`. Extract 3D joint positions and drive SceneKit skeleton nodes. Overlay on camera preview.
- **Effort:** Medium-High. iOS 17+ requirement; coordinate system alignment between Vision and SceneKit needed.
- **Best for:** A variant that shows a real-time skeleton overlay on the user's camera feed using only front camera data.

### Implementation Order Suggestion

1. Start with **Canvas stick figure** (Class A) — establishes the metric-to-body-motion mapping in the simplest possible way. Reuse this mapping logic in all subsequent approaches.
2. Build **programmatic SceneKit mannequin** (Class B) as a shared component. Parameterize it well so multiple variants can use it with different styling.
3. Add **Vision 3D overlay** (Class D) as one variant, reusing existing Vision pipeline plumbing.
4. Consider **ARKit body mirror** (Class C) as a single showcase variant if device compatibility is acceptable.
