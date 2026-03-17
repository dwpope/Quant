import SwiftUI

struct MetricRatioBar: View {
    let info: MetricInfo
    var showLabel: Bool = true
    var showValue: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showLabel {
                HStack {
                    Image(systemName: info.key.symbolName)
                        .font(.caption)
                    Text(info.key.displayName)
                        .font(.caption)
                    Spacer()
                    if showValue {
                        Text(String(format: "%.0f%%", info.clampedRatio * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)

                    Capsule()
                        .fill(PostureVisualStyle.metricColor(ratio: info.ratio))
                        .frame(width: max(0, geo.size.width * CGFloat(info.clampedRatio)))
                        .animation(PostureAnimations.metricUpdate, value: info.clampedRatio)

                    // Threshold marker
                    Rectangle()
                        .fill(.primary.opacity(0.3))
                        .frame(width: 1.5)
                        .offset(x: geo.size.width - 1)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
        }
    }
}
