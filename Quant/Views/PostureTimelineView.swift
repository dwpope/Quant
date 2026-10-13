import Charts
import Combine
import PostureLogic
import SwiftUI

/// Reads a day of the posture log into a timeline, off the main thread (2026-10-13).
///
/// Its own object so the main screen, which redraws with every frame, never reads the file: the
/// card reloads on its own timer.
@MainActor
final class PostureTimelineLoader: ObservableObject {
    @Published private(set) var timeline: PostureTimeline?
    @Published private(set) var dayKeys: [String] = []

    func load(dayKey: String, now: Date = Date()) async {
        let (events, keys) = await Task.detached(priority: .utility) {
            (PostureLogStore.events(dayKey: dayKey), PostureLogStore.dayKeys())
        }.value
        timeline = PostureTimeline(events: events, now: now)
        dayKeys = keys
    }
}

extension PostureTimeline.Band {
    /// The phone's posture colours (`PostureCard`), grey for away.
    var color: Color {
        switch self {
        case .good: return .green
        case .drifting: return .yellow
        case .bad: return .red
        case .away: return .gray.opacity(0.35)
        }
    }

    var label: String {
        switch self {
        case .good: return "Sat well"
        case .drifting: return "Slouching"
        case .bad: return "Slouched long enough to nudge"
        case .away: return "Away"
        }
    }
}

/// The band across the day: green when you sat well, yellow and red while slouched, grey while
/// away, with a mark at each nudge.
struct PostureTimelineChart: View {
    let timeline: PostureTimeline
    var showsAxis = false

    var body: some View {
        Chart {
            ForEach(Array(timeline.segments.enumerated()), id: \.offset) { _, segment in
                RectangleMark(
                    xStart: .value("Start", segment.start),
                    xEnd: .value("End", segment.end),
                    yStart: .value("Bottom", 0),
                    yEnd: .value("Top", 1))
                    .foregroundStyle(segment.band.color)
            }
            ForEach(Array(timeline.nudges.enumerated()), id: \.offset) { _, nudge in
                RuleMark(x: .value("Nudge", nudge.at))
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
        .chartXAxis(showsAxis ? .automatic : .hidden)
        .chartXScale(domain: timeline.span ?? Date()...Date())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(timeline.summary ?? "No posture recorded")
    }
}

/// Today's posture on the main screen; tap for the whole day and earlier days.
struct PostureTimelineCard: View {
    @StateObject private var loader = PostureTimelineLoader()
    @State private var showDetail = false

    /// Reloaded this often while the screen is up: the log only grows when something changes.
    private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Button { showDetail = true } label: {
            CardContainer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("TODAY")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .tracking(1.2)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let timeline = loader.timeline, !timeline.segments.isEmpty {
                        PostureTimelineChart(timeline: timeline)
                            .frame(height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(timeline.summary ?? "Not judged yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Your posture today will show here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task { await loader.load(dayKey: PostureLogStore.dayKey(for: Date())) }
        .onReceive(refresh) { _ in
            Task { await loader.load(dayKey: PostureLogStore.dayKey(for: Date())) }
        }
        .sheet(isPresented: $showDetail) {
            PostureTimelineView()
        }
    }
}

/// A day's posture in full: the band with times, the totals and each nudge. Earlier days from
/// the menu.
struct PostureTimelineView: View {
    @StateObject private var loader = PostureTimelineLoader()
    @State private var dayKey = PostureLogStore.dayKey(for: Date())
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let timeline = loader.timeline, !timeline.segments.isEmpty {
                    Section {
                        PostureTimelineChart(timeline: timeline, showsAxis: true)
                            .frame(height: 80)
                            .padding(.vertical, 8)
                        if let summary = timeline.summary {
                            Text(summary).font(.subheadline)
                        }
                    }
                    Section("Time") {
                        ForEach(PostureTimeline.Band.allCases, id: \.self) { band in
                            let seconds = timeline.total(band)
                            if seconds > 0 {
                                HStack {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(band.color)
                                        .frame(width: 14, height: 14)
                                    Text(band.label)
                                    Spacer()
                                    Text(PostureTimeline.minutes(seconds))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                    Section("Nudges") {
                        if timeline.nudges.isEmpty {
                            Text("None").foregroundStyle(.secondary)
                        }
                        ForEach(Array(timeline.nudges.enumerated()), id: \.offset) { _, nudge in
                            HStack {
                                Text(nudge.at, style: .time)
                                    .monospacedDigit()
                                Spacer()
                                Text(PostureTimeline.label(for: nudge.reason))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Nothing recorded on this day")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if loader.dayKeys.count > 1 {
                    ToolbarItem(placement: .primaryAction) {
                        Picker("Day", selection: $dayKey) {
                            ForEach(loader.dayKeys, id: \.self) { key in
                                Text(Self.dayName(key)).tag(key)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .task(id: dayKey) { await loader.load(dayKey: dayKey) }
        }
    }

    private var title: String { Self.dayName(dayKey) }

    /// "Today", "Yesterday", or the date.
    static func dayName(_ key: String) -> String {
        if key == PostureLogStore.dayKey(for: Date()) { return "Today" }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()),
           key == PostureLogStore.dayKey(for: yesterday) { return "Yesterday" }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: key) else { return key }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
