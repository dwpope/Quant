import Charts
import SwiftUI

/// The day's water as a rising total over the posture band's span, with the pace line dashed
/// behind it and the away stretches shaded grey (hydration design §7.5, option C).
struct HydrationChart: View {
    let day: HydrationDay
    let span: ClosedRange<Date>
    let away: [ClosedRange<Date>]

    var body: some View {
        Chart {
            ForEach(Array(awayInSpan.enumerated()), id: \.offset) { _, stretch in
                RectangleMark(
                    xStart: .value("Start", stretch.lowerBound),
                    xEnd: .value("End", stretch.upperBound),
                    yStart: .value("Bottom", 0),
                    yEnd: .value("Top", day.yMax))
                    .foregroundStyle(Color.gray.opacity(0.18))
            }
            ForEach(Array(total.enumerated()), id: \.offset) { _, step in
                AreaMark(x: .value("Time", step.at), y: .value("Total", step.millilitres))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Color.blue.opacity(0.3))
                LineMark(x: .value("Time", step.at), y: .value("Total", step.millilitres),
                         series: .value("Series", "total"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Color.blue)
            }
            ForEach(Array(day.pacePoints(in: span).enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Time", point.at), y: .value("Pace", point.millilitres),
                         series: .value("Series", "pace"))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: span)
        .chartYScale(domain: 0...day.yMax)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityElement(children: .ignore)
    }

    private var total: [HydrationDay.Step] {
        day.runningTotal(from: span.lowerBound, to: span.upperBound)
    }

    /// The away stretches, cut to the chart's span.
    private var awayInSpan: [ClosedRange<Date>] {
        away.compactMap { stretch in
            let lower = max(stretch.lowerBound, span.lowerBound), upper = min(stretch.upperBound, span.upperBound)
            return lower < upper ? lower...upper : nil
        }
    }
}
