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

    typealias Read = @Sendable (_ dayKey: String) -> (events: [PostureLogEvent], dayKeys: [String])
    private let read: Read

    init(read: @escaping Read = { (PostureLogStore.events(dayKey: $0), PostureLogStore.dayKeys()) }) {
        self.read = read
    }

    func load(dayKey: String, now: Date = Date()) async {
        let read = self.read
        let (events, keys) = await Task.detached(priority: .utility) { read(dayKey) }.value
        timeline = PostureTimeline(events: events, now: now)
        dayKeys = keys
    }

    /// Today's, now and then every `interval` until the task is cancelled (2026-10-16): run from
    /// the card's `.task`, which lasts as long as the card. Its timer used to be a property of
    /// the view, rebuilt with the main screen about ten times a second, and it never fired.
    func keepLoadingToday(every interval: Duration = .seconds(30)) async {
        while !Task.isCancelled {
            await load(dayKey: PostureLogStore.dayKey(for: Date()))
            try? await Task.sleep(for: interval)
        }
    }
}

extension PostureTimeline.Band {
    /// The phone's posture colours (`PosturePalette`), grey for away.
    var color: Color {
        switch self {
        case .good: return Color(PosturePalette.good)
        case .drifting: return Color(PosturePalette.slouching)
        case .bad: return Color(PosturePalette.stillSlouching)
        case .away: return .gray.opacity(0.35)
        }
    }

    /// How tall the band stands, of its full height: it dips while you slouch, lower the longer
    /// it goes on, so it reads without its colours (2026-10-16).
    var height: Double {
        switch self {
        case .good: return 1
        case .drifting: return 0.6
        case .bad: return 0.3
        case .away: return 0.12
        }
    }

    /// The posture card's words (`PostureCard.label(for:)`).
    var label: String {
        switch self {
        case .good: return "Sitting well"
        case .drifting: return "Slouching"
        case .bad: return "Still slouching"
        case .away: return "Away"
        }
    }
}

/// The band across the day: full height and green when you sat well, lower and yellow then red
/// while slouched, a grey sliver while away, with a mark at each nudge.
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
                    yEnd: .value("Top", segment.band.height))
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
        .task { await loader.keepLoadingToday() }
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
