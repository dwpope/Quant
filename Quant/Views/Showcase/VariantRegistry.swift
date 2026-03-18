import SwiftUI

enum VariantRegistry {
    static let allVariants: [VariantDescriptor] = [
        // MARK: - Score-Centric (1–6)
        VariantDescriptor(id: 1, name: "Precision Gauge", category: .scoreCentric, technologies: [.canvas],
                          makeView: { AnyView(Variant1View()) }),
        VariantDescriptor(id: 2, name: "Triadic Rings", category: .scoreCentric, technologies: [.canvas],
                          makeView: { AnyView(Variant2View()) }),
        VariantDescriptor(id: 3, name: "Battery Drain", category: .scoreCentric, technologies: [.canvas],
                          makeView: { AnyView(Variant3View()) }),
        VariantDescriptor(id: 4, name: "Arc Meter", category: .scoreCentric, technologies: [.canvas],
                          makeView: { AnyView(Variant4View()) }),
        VariantDescriptor(id: 5, name: "Numeric Countdown", category: .scoreCentric, technologies: [],
                          makeView: { AnyView(Variant5View()) }),
        VariantDescriptor(id: 6, name: "Traffic Light", category: .scoreCentric, technologies: [],
                          makeView: { AnyView(Variant6View()) }),

        // MARK: - Data Visualization (7–12)
        VariantDescriptor(id: 7, name: "Five-Bar Equalizer", category: .dataVisualization, technologies: [.canvas],
                          makeView: { AnyView(Variant7View()) }),
        VariantDescriptor(id: 8, name: "Donut Breakdown", category: .dataVisualization, technologies: [.canvas],
                          makeView: { AnyView(Variant8View()) }),
        VariantDescriptor(id: 9, name: "Horizontal Rails", category: .dataVisualization, technologies: [],
                          makeView: { AnyView(Variant9View()) }),
        VariantDescriptor(id: 10, name: "Radial Dial Array", category: .dataVisualization, technologies: [.canvas],
                          makeView: { AnyView(Variant10View()) }),
        VariantDescriptor(id: 11, name: "Digital Cockpit", category: .dataVisualization, technologies: [.canvas],
                          makeView: { AnyView(Variant11View()) }),
        VariantDescriptor(id: 12, name: "Split Flap Display", category: .dataVisualization, technologies: [],
                          makeView: { AnyView(Variant12View()) }),

        // MARK: - Typographic (13–20)
        VariantDescriptor(id: 13, name: "Single Word", category: .typographic, technologies: [],
                          makeView: { AnyView(Variant13View()) }),
        VariantDescriptor(id: 14, name: "Breathing Dot", category: .typographic, technologies: [],
                          makeView: { AnyView(Variant14View()) }),
        VariantDescriptor(id: 15, name: "Thin Line", category: .typographic, technologies: [.canvas],
                          makeView: { AnyView(Variant15View()) }),
        VariantDescriptor(id: 16, name: "Gradient Wash", category: .typographic, technologies: [.meshGradient],
                          makeView: { AnyView(Variant16View()) }),
        VariantDescriptor(id: 17, name: "Clock Face", category: .typographic, technologies: [.canvas],
                          makeView: { AnyView(Variant17View()) }),
        VariantDescriptor(id: 18, name: "Emoji Mood", category: .typographic, technologies: [],
                          makeView: { AnyView(Variant18View()) }),
        VariantDescriptor(id: 19, name: "Concentric Ripples", category: .typographic, technologies: [.canvas],
                          makeView: { AnyView(Variant19View()) }),
        VariantDescriptor(id: 20, name: "Kanji / Symbol", category: .typographic, technologies: [],
                          makeView: { AnyView(Variant20View()) }),

        // MARK: - Abstract Geometric (21–28)
        variant(21, "Stacked Totem",         .abstract,           [.canvas]),
        variant(22, "Radar Glyph",           .abstract,           [.canvas]),
        variant(23, "Concentric Target",     .abstract,           [.canvas]),
        variant(24, "Pendulum Array",        .abstract,           [.canvas]),
        variant(25, "Tensegrity",            .abstract,           [.canvas]),
        variant(26, "Origami Crane",         .abstract,           [.canvas]),
        variant(27, "Bauhaus Figure",        .abstract,           [.canvas]),
        variant(28, "Sacred Geometry",       .abstract,           [.canvas]),

        // MARK: - Anatomical / 3D (29–34)
        variant(29, "SceneKit Mannequin",    .anatomical,         [.sceneKit]),
        variant(30, "Wire Skeleton",         .anatomical,         [.sceneKit]),
        variant(31, "Body Silhouette",       .anatomical,         [.canvas]),
        variant(32, "Muscle Heatmap",        .anatomical,         [.canvas]),
        variant(33, "Spine Column",          .anatomical,         [.sceneKit]),
        variant(34, "Mirror Avatar",         .anatomical,         [.realityKit]),

        // MARK: - Ambient / Atmospheric — Instruments (35–40)
        variant(35, "Attitude Indicator",    .experimental,       [.canvas]),
        variant(36, "Spirit Level",          .experimental,       [.canvas]),
        variant(37, "Gyroscope Rings",       .experimental,       [.sceneKit]),
        variant(38, "Compass Rose",          .experimental,       [.canvas]),
        variant(39, "Oscilloscope",          .experimental,       [.canvas]),
        variant(40, "Load Diagram",          .experimental,       [.canvas]),

        // MARK: - Ambient / Atmospheric — Organic / Nature (41–46)
        variant(41, "Wilting Plant",         .ambient,            [.canvas]),
        variant(42, "Tree of Life",          .ambient,            [.canvas]),
        variant(43, "Water Surface",         .ambient,            [.metal]),
        variant(44, "Terrain Map",           .ambient,            [.canvas]),
        variant(45, "Weather System",        .ambient,            [.canvas, .spriteKit]),
        variant(46, "Coral Reef",            .ambient,            [.sceneKit]),

        // MARK: - Ambient / Atmospheric — Shader-Driven (47–54)
        variant(47, "Aurora Borealis",       .ambient,            [.metal]),
        variant(48, "Turbulent Flow",        .ambient,            [.metal]),
        variant(49, "Frosted Glass",         .ambient,            [.metal]),
        variant(50, "Chromatic Split",       .ambient,            [.metal]),
        variant(51, "Glitch Matrix",         .ambient,            [.metal]),
        variant(52, "Lava Lamp",             .ambient,            [.metal, .meshGradient]),
        variant(53, "Heartbeat Pulse",       .ambient,            [.metal]),
        variant(54, "Starfield",             .ambient,            [.spriteKit]),

        // MARK: - Gamified (55–58)
        variant(55, "XP Health Bar",         .gamified,           [.canvas]),
        variant(56, "Streak Counter",        .gamified,           []),
        variant(57, "Achievement Rings",     .gamified,           [.canvas]),
        variant(58, "Boss Battle",           .gamified,           [.spriteKit]),

        // MARK: - Experimental — Architectural (59–60)
        variant(59, "Torii Gate",            .experimental,       [.sceneKit]),
        variant(60, "Suspension Bridge",     .experimental,       [.sceneKit]),
    ]

    private static func variant(
        _ id: Int,
        _ name: String,
        _ category: VariantCategory,
        _ technologies: [TechTag]
    ) -> VariantDescriptor {
        VariantDescriptor(
            id: id,
            name: name,
            category: category,
            technologies: technologies,
            makeView: {
                AnyView(
                    VariantPlaceholderView(
                        descriptor: VariantDescriptor(
                            id: id,
                            name: name,
                            category: category,
                            technologies: technologies,
                            makeView: { AnyView(EmptyView()) }
                        )
                    )
                )
            }
        )
    }
}
