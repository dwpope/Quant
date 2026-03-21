import SwiftUI

struct VariantDescriptor: Identifiable, Hashable {
    let id: Int
    let name: String
    let category: VariantCategory
    let technologies: [TechTag]
    let makeView: () -> AnyView

    static func == (lhs: VariantDescriptor, rhs: VariantDescriptor) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum VariantCategory: String, CaseIterable, Identifiable {
    case scoreCentric      = "Score-Centric"
    case dataVisualization = "Data Visualization"
    case typographic       = "Typographic"
    case abstract          = "Abstract Geometric"
    case anatomical        = "Anatomical / 3D"
    case ambient           = "Ambient / Atmospheric"
    case gamified          = "Gamified"
    case experimental      = "Experimental"

    var id: String { rawValue }
}

enum TechTag: String {
    case canvas
    case swiftCharts
    case sceneKit
    case realityKit
    case spriteKit
    case metal
    case meshGradient
    case gauge
    case swiftUI
}
