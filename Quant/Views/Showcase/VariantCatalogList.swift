import SwiftUI

struct VariantCatalogList: View {
    @Binding var selectedVariant: VariantDescriptor?

    private var groupedVariants: [(VariantCategory, [VariantDescriptor])] {
        let grouped = Dictionary(grouping: VariantRegistry.allVariants, by: \.category)
        return VariantCategory.allCases.compactMap { category in
            guard let variants = grouped[category], !variants.isEmpty else { return nil }
            return (category, variants)
        }
    }

    var body: some View {
        List(selection: $selectedVariant) {
            ForEach(groupedVariants, id: \.0) { category, variants in
                Section(category.rawValue) {
                    ForEach(variants) { variant in
                        NavigationLink(value: variant) {
                            VariantRow(variant: variant)
                        }
                    }
                }
            }
        }
        .navigationTitle("Variants")
    }
}

private struct VariantRow: View {
    let variant: VariantDescriptor

    var body: some View {
        HStack {
            Text("\(variant.id)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(variant.name)
                    .font(.body)

                if !variant.technologies.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(variant.technologies, id: \.rawValue) { tech in
                            Text(tech.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }
}
