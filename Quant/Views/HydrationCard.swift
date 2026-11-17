import SwiftUI

/// Today's water on the main screen, under the posture band: the total against the 2 L goal,
/// the rising total over the same span as the posture band, and when the last drink was
/// (hydration design §7.5). Tap for the drinks list.
///
/// It asks for Apple Health access the first time it appears, and says so plainly when Health
/// is off or missing. It never reminds anyone to drink.
struct HydrationCard: View {
    @ObservedObject var hydration: HydrationModel
    let onTap: () -> Void

    /// Today's posture, for the chart's span and its away shading.
    @StateObject private var loader = PostureTimelineLoader()

    var body: some View {
        let now = Date()
        let day = hydration.day
        let note = HydrationDay.accessNote(hydration.access)
        Button(action: onTap) {
            CardContainer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("HYDRATION")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .tracking(1.2)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let note, hydration.access == .unavailable {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(day.headline)
                            .font(.headline)
                        HydrationChart(day: day,
                                       span: day.chartSpan(postureSpan: loader.timeline?.span, now: now),
                                       away: HydrationDay.awayStretches(loader.timeline?.segments ?? []))
                            .frame(height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(day.detailLine(now: now))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let note {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hydration.access == .unavailable
                            ? "Hydration. \(note ?? "")"
                            : "Hydration. \(day.headline). \(day.detailLine(now: now))")
        .accessibilityHint("Shows today's drinks")
        .task { await loader.keepLoadingToday() }
        // Asks for Health access as soon as the card appears.
        .task {
            await hydration.start()
            await hydration.keepRefreshing()
        }
    }
}
