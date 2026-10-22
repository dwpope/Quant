import Combine
import CoreImage
import Metal
import PostureLogic
import RealityKit
import SwiftUI
import UIKit

/// Draws your 3D model, `quant_person.usdz`, posed, one frame at a time (2026-10-22).
///
/// A RealityKit view can't be paused: it draws every frame, and a hidden one has been measured
/// at about 30% of the CPU. On a screen left on for hours, beside the camera and Vision, that's
/// heat, and heat pauses detection. So the model is drawn offscreen (`RealityRenderer`, iOS 18)
/// only when your posture changes: a few frames a minute while you slouch, none while you sit
/// well. Matte and softly lit, so its shape reads in 3D; a small nose, as the primitive figure
/// had, so a turned head shows on an egg that looks the same from every side.
@MainActor
final class CalmModelRenderer {
    /// The image's size, in pixels: the hero's shape (0.82 wide to 1 tall) at about 3× scale.
    static let pixelWidth = 600
    static let pixelHeight = 732

    private let renderer: RealityRenderer
    private let assembly: Entity
    private let torso: Entity
    private let head: Entity
    private let headRest: SIMD3<Float>
    private let texture: MTLTexture
    private let context = CIContext()

    private init(renderer: RealityRenderer, assembly: Entity, torso: Entity, head: Entity, texture: MTLTexture) {
        self.renderer = renderer
        self.assembly = assembly
        self.torso = torso
        self.head = head
        self.headRest = head.position
        self.texture = texture
    }

    /// Nil without Metal, the model, or its named parts: the calm view then draws the figure
    /// itself (`PostureFigure`).
    static func make() async -> CalmModelRenderer? {
        guard Bundle.main.url(forResource: "quant_person", withExtension: "usdz") != nil,
              let device = MTLCreateSystemDefaultDevice(),
              let renderer = try? RealityRenderer() else { return nil }
        let assembly = await PostureVisualizationScene.loadAssembly()
        guard let torso = assembly.findEntity(named: PostureVisualizationScene.EntityName.shoulderDisc),
              let head = assembly.findEntity(named: PostureVisualizationScene.EntityName.head) else { return nil }

        // The nose: front (−Y) and a little below the middle of the head, in its own units.
        let nose = ModelEntity(mesh: .generateSphere(radius: 0.12), materials: [SimpleMaterial()])
        nose.position = SIMD3<Float>(0, -0.8, 0.55)
        nose.scale = SIMD3<Float>(0.9, 0.7, 1.15)
        head.addChild(nose)
        renderer.entities.append(assembly)

        // Front on, a little above, the whole figure with room to lean in and sink.
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 25
        let target = SIMD3<Float>(0, 0.13, 0)
        camera.look(at: target, from: target + SIMD3<Float>(0, 0.05, 0.95), relativeTo: nil)
        renderer.entities.append(camera)
        renderer.activeCamera = camera

        // A key light from the upper left, a softer fill from the right, a rim from behind.
        for (intensity, from) in [(Float(4000), SIMD3<Float>(-0.5, 0.8, 1)),
                                  (1500, SIMD3<Float>(0.8, 0.2, 0.6)),
                                  (2500, SIMD3<Float>(0.2, 0.6, -1))] {
            let light = DirectionalLight()
            light.light.intensity = intensity
            light.look(at: .zero, from: from, relativeTo: nil)
            renderer.entities.append(light)
        }
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 0))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: pixelWidth, height: pixelHeight, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        return CalmModelRenderer(renderer: renderer, assembly: assembly, torso: torso, head: head,
                                 texture: texture)
    }

    /// The model in `pose`, in `colour`, on transparency. Nil if the frame couldn't be drawn.
    func render(_ pose: CalmFigurePose, colour: UIColor) async -> CGImage? {
        let model = CalmModelPose(pose)
        torso.orientation = model.torso
        head.orientation = model.head
        head.position = headRest - SIMD3<Float>(0, 0, model.headLowered)
        assembly.scale = SIMD3<Float>(repeating: model.scale)
        assembly.position = SIMD3<Float>(0, -model.sunk, 0)
        paint(assembly, colour: colour)

        guard let output = try? RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        else { return nil }
        let drawn: Bool = await withCheckedContinuation { done in
            do {
                try renderer.updateAndRender(deltaTime: 0, cameraOutput: output,
                                             onComplete: { _ in done.resume(returning: true) })
            } catch {
                done.resume(returning: false)
            }
        }
        guard drawn, let image = CIImage(mtlTexture: texture, options: [
            .colorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ]) else { return nil }
        // Metal's rows run the other way from Core Image's.
        let upright = image.oriented(.downMirrored)
        return context.createCGImage(upright, from: upright.extent)
    }

    /// The outline of the model at rest, how you sat at calibration: a white ring.
    func outline() async -> CGImage? {
        guard let rest = await render(.neutral, colour: .white) else { return nil }
        // White where the model is, black elsewhere, opaque: morphology works on the colours and
        // leaves alpha alone.
        let frame = CIImage(cgImage: rest).extent
        let mask = CIImage(cgImage: rest).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: frame)   // the bias makes the endless clear round the image opaque too
        // Its edge, a few pixels wide, then back to white on transparency, the edge's brightness
        // its alpha. The gradient peaks at about half (measured), so it's doubled and clamped.
        let ring = mask.applyingFilter("CIMorphologyGradient", parameters: [kCIInputRadiusKey: 3])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 2, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 2, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 2, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 2, y: 0, z: 0, w: 0),
            ])
            .applyingFilter("CIColorClamp")
        return context.createCGImage(ring, from: frame)
    }

    private func paint(_ entity: Entity, colour: UIColor) {
        if let model = entity as? ModelEntity, model.model != nil {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: colour)
            material.roughness = .init(floatLiteral: 0.9)
            material.metallic = .init(floatLiteral: 0)
            model.model?.materials = [material]
        }
        for child in entity.children { paint(child, colour: colour) }
    }
}

/// The frames the calm view shows: the model rendered at each pose, moving between them over
/// half a second (none with Reduce Motion), and its outline.
@MainActor
final class CalmModelFrames: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var outline: CGImage?
    /// The model couldn't be drawn: the calm view draws the figure itself.
    @Published private(set) var unavailable = false

    private var renderer: CalmModelRenderer?
    private var shown: (pose: CalmFigurePose, colour: SIMD4<Double>)?
    private var moving: Task<Void, Never>?

    /// A move's frames: half a second at 30 a second.
    static let moveFrames = 15

    func show(_ pose: CalmFigurePose, colour: UIColor, animated: Bool) {
        moving?.cancel()
        moving = Task { await move(to: pose, colour: Self.components(colour), animated: animated) }
    }

    private func move(to pose: CalmFigurePose, colour: SIMD4<Double>, animated: Bool) async {
        if renderer == nil {
            guard let made = await CalmModelRenderer.make() else { unavailable = true; return }
            renderer = made
            outline = await made.outline()
        }
        guard let renderer else { return }
        let from = shown ?? (pose, colour)
        let frames = animated && shown != nil ? Self.moveFrames : 1
        for frame in 1...frames {
            guard !Task.isCancelled else { return }
            // Eased in and out.
            let x = Double(frame) / Double(frames), t = x * x * (3 - 2 * x)
            let p = CalmFigurePose.mix(from.pose, pose, t)
            let c = from.colour + (colour - from.colour) * t
            if let image = await renderer.render(p, colour: UIColor(red: c.x, green: c.y, blue: c.z, alpha: c.w)) {
                self.image = image
                shown = (p, c)
            }
            if frame < frames { try? await Task.sleep(for: .milliseconds(33)) }
        }
    }

    private static func components(_ colour: UIColor) -> SIMD4<Double> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Double(r), Double(g), Double(b), Double(a))
    }
}

/// Your 3D model in the calm view: posed as you sit, in the posture's colour at its brightness
/// (`CalmPalette`), with the outline of how you sat at calibration over it. Falls back to the
/// drawn figure when the model can't be drawn.
struct CalmModelFigure: View {
    let band: PostureTimeline.Band?
    let pose: CalmFigurePose
    var neckLength: Double = 1
    var symbol: String?

    @StateObject private var frames = CalmModelFrames()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private struct Shown: Hashable {
        let pose: CalmFigurePose
        let band: PostureTimeline.Band?
    }

    var body: some View {
        if frames.unavailable {
            PostureFigure(band: band, pose: pose, neckLength: neckLength, symbol: symbol)
        } else {
            ZStack {
                // Away there's no one to draw: the outline stands empty.
                if let image = frames.image, let band, band != .away {
                    let slouched = band == .drifting || band == .bad
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .shadow(color: slouched ? band.color.opacity(0.4) : .clear, radius: 30)
                }
                if let outline = frames.outline {
                    Image(decorative: outline, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .opacity(band == nil || band == .away ? 0.35 : 0.22)
                }
                if let symbol {
                    GeometryReader { geo in
                        Image(systemName: symbol)
                            .font(.system(size: geo.size.width * 0.16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.7)
                    }
                }
            }
            .task(id: Shown(pose: pose, band: band)) {
                frames.show(band != nil && band != .away ? pose : .neutral,
                            colour: modelColour, animated: !reduceMotion)
            }
            .accessibilityHidden(true)
        }
    }

    /// The posture's colour at its brightness: a dim green sitting well, the quietest the
    /// screen gets, a bright yellow, then red, slouching. Sitting well is a shade brighter than
    /// the drawn figure's, as the model's shading darkens it again.
    private var modelColour: UIColor {
        guard let band, band != .away else { return .gray }
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let base = UIColor(band.color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getRed(&r, green: &g, blue: &b, alpha: &a)
        let k = CGFloat(band == .good ? 0.62 : CalmPalette.intensity(of: band))
        return UIColor(red: r * k, green: g * k, blue: b * k, alpha: 1)
    }
}
