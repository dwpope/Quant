import Combine
import Foundation
import PostureLogic
import SwiftUI

// This ships. A Release build DOES contain this store, the call site and the Jev UI — the
// `#if DEBUG` gate was removed on 2026-09-24 so the experiment can be run from TestFlight.
//
// Consequence worth knowing before reading further: on any device where a tester enables the
// classifier, this writes camera-derived posture records — the exact payload sent, plus the
// calibration baseline — to the app's Documents directory as `jev-comparisons-YYYY-MM-DD.json`.
// That container is sandbox-private and has no file-sharing key, but it is included in device
// backups, and nothing prunes old files.

/// Jev's five posture classes: what "both wrong" records as the true class.
///
/// The raw values are the keys of `POSTURE_CRITERIA` in `jev-proxy/src/classify.ts`, the rubric
/// Jev answers from. `JevComparisonLegacyDecodeTests.test_jevClasses_matchTheProxysRubric` reads
/// that file, so a rename on either side fails a test instead of splitting the dataset.
enum JevClass: String, Codable, CaseIterable {
    case goodPosture = "good_posture"
    case slouch
    case lean
    case chairSwivel = "chair_swivel"
    case ambiguous
}

/// One moment where Jev and the threshold engine both had an opinion, plus what Dave said.
///
/// This is step 3c's dataset, and it is deliberately self-contained: it must answer "was Jev
/// better than the thresholds here?" **without re-running anything**. Hence two things that look
/// redundant and are not:
///
/// - `features` is the exact payload that was sent, not the raw sample. What Jev saw is what
///   matters, including the normalisation applied to it.
/// - `baseline` is kept alongside, because every metric in `features` is a delta from it. The
///   live baseline is cleared on recalibration and treated as stale after an hour, so a record
///   without it becomes uninterpretable within the hour. Same reasoning as `SessionMetadata
///   .baseline` in step 3a.
///
/// Note what is deliberately NOT claimed: `thresholdState` is a temporal state
/// (good/drifting/bad) while `jev.posture` is a morphological class (slouch/lean/chair_swivel).
/// They are not the same kind of thing, so the record stores both verbatim and lets the human
/// adjudicate rather than pretending to a like-for-like comparison.
// Not `Equatable`: `Baseline` is not, and nothing here needs record equality. Widening a
// core PostureLogic model to satisfy a convenience would be the wrong trade.
struct JevComparisonRecord: Codable, Identifiable {

    /// Who was right, in Dave's judgement. The only ground truth available here — he is present
    /// and in the chair, which no stored signal can substitute for.
    enum UserVerdict: String, Codable, CaseIterable {
        case jevWasRight
        case thresholdsWereRight
        case bothWrong
    }

    let id: UUID
    let capturedAt: Date
    /// Exactly what was sent to the proxy.
    let features: JevFeatures
    /// What those deltas were relative to. Unrecoverable later; see the type doc.
    let baseline: Baseline
    /// The threshold engine's state at the same moment.
    let thresholdState: PostureState
    /// The verdict, or `nil` when the call failed — which is itself evidence that Jev was
    /// unavailable at a moment the thresholds had an opinion.
    let jev: JevVerdict?
    let jevError: String?
    var userVerdict: UserVerdict?
    /// What the posture actually was, when both sides got it wrong.
    ///
    /// One of Jev's classes since 2026-09-29. Before that it was a recording tag (reading,
    /// typing…), which 3c can't compare with Jev's answer. Those old strings decode as `nil`;
    /// see ``init(from:)``.
    var trueClass: JevClass?

    init(
        id: UUID,
        capturedAt: Date,
        features: JevFeatures,
        baseline: Baseline,
        thresholdState: PostureState,
        jev: JevVerdict?,
        jevError: String?,
        userVerdict: UserVerdict? = nil,
        trueClass: JevClass? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.features = features
        self.baseline = baseline
        self.thresholdState = thresholdState
        self.jev = jev
        self.jevError = jevError
        self.userVerdict = userVerdict
        self.trueClass = trueClass
    }

    /// Decodes every field strictly except `trueClass`, which is tolerant.
    ///
    /// Records saved before 2026-09-29 hold a recording tag there. None of those maps honestly
    /// onto a Jev class: "goodPosture" and "slouching" were often just the nearest pick for a lean
    /// or a swivel, so translating them would launder a guess into a label. They become `nil`,
    /// and the "both wrong" verdict stays, flagging the record for re-labelling. A strict decode
    /// here would throw and lose the whole record.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        features = try c.decode(JevFeatures.self, forKey: .features)
        baseline = try c.decode(Baseline.self, forKey: .baseline)
        thresholdState = try c.decode(PostureState.self, forKey: .thresholdState)
        jev = try c.decodeIfPresent(JevVerdict.self, forKey: .jev)
        jevError = try c.decodeIfPresent(String.self, forKey: .jevError)
        userVerdict = try c.decodeIfPresent(UserVerdict.self, forKey: .userVerdict)
        trueClass = (try? c.decodeIfPresent(String.self, forKey: .trueClass))
            .flatMap { $0 }
            .flatMap(JevClass.init(rawValue:))
    }
}

/// Persists and exposes today's Jev-vs-thresholds comparisons.
///
/// Stored per-day in Documents as `jev-comparisons-YYYY-MM-DD.json`, following `SipStore`
/// exactly — same per-day key, same best-effort load, same static serial write queue, same
/// `flushPendingWrites` test hook. Deliberately not a new pattern.
@MainActor
final class JevComparisonStore: ObservableObject {

    // Teardown only releases stored properties; it touches no main-actor state.
    // Marking it `nonisolated` keeps Swift's MainActor isolated-deinit back-deploy shim out of
    // XCTest's NSInvocation-driven dealloc path, which otherwise corrupts the heap and aborts
    // under Xcode 26 / iOS 26.
    nonisolated deinit {}

    /// Today's comparisons, oldest first.
    @Published private(set) var comparisons: [JevComparisonRecord] = []

    /// How many comparisons Dave has adjudicated today — the number that actually matters for 3c.
    var adjudicatedCount: Int { comparisons.filter { $0.userVerdict != nil }.count }

    private let calendar = Calendar.current
    private var todayKey: String { dateKey(for: Date()) }

    /// Today's records this build couldn't decode, each as its own JSON, written back with every
    /// save. Without this, loading drops them and the next save deletes them from disk.
    private var unreadable: [Data] = []

    init() {
        load()
    }

    func add(_ record: JevComparisonRecord) {
        comparisons.append(record)
        comparisons.sort { $0.capturedAt < $1.capturedAt }
        persist()
    }

    /// Records who was right. No-op for an unknown id, so a stale tap cannot corrupt the set.
    func setUserVerdict(id: UUID, verdict: JevComparisonRecord.UserVerdict, trueClass: JevClass?) {
        guard let idx = comparisons.firstIndex(where: { $0.id == id }) else { return }
        comparisons[idx].userVerdict = verdict
        comparisons[idx].trueClass = trueClass
        persist()
    }

    // MARK: - Export

    /// Writes today's comparisons as JSONL to caches and returns the file, for a `ShareLink`.
    ///
    /// Exists because remote testing is otherwise write-only: the records live in the app's
    /// private container, and without this the dataset cannot leave the phone without a Mac and
    /// Xcode's container download. Follows `SipTrainingStore.exportJSONL` — caches directory,
    /// `.sortedKeys` for stable diffs, one self-contained JSON object per line.
    ///
    /// **Every record is exported, adjudicated or not.** One without a user verdict has no
    /// ground truth, but it still records what both sides answered at the same moment, which
    /// measures agreement. Filtering here would silently discard evidence the analysis might
    /// want, and the analysis can filter for itself.
    ///
    /// Each line carries the exact payload sent AND the baseline it was relative to, so the
    /// deltas remain interpretable long after the live baseline has been recalibrated away.
    func exportJSONL() throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let joined = try comparisons
            .map { String(data: try encoder.encode($0), encoding: .utf8) ?? "" }
            .joined(separator: "\n")

        let url = cachesFile(name: "jev-comparisons-\(todayKey).jsonl")
        try Data(joined.utf8).write(to: url, options: .atomic)
        return url
    }

    private func cachesFile(name: String) -> URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }

    // MARK: - Persistence

    /// Loads today's file one record at a time, so one bad record can never empty the day.
    ///
    /// This used to decode the whole file with one `try?`. Any record that failed to decode made
    /// the day load empty, and the next capture's save then replaced the file with just itself.
    /// Now a record that fails is kept aside and written back untouched. A file that isn't a
    /// JSON array at all is moved aside before anything can overwrite it.
    private func load() {
        let url = fileURL(for: todayKey)
        guard let data = try? Data(contentsOf: url) else { return }  // no file yet today

        guard let elements = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            setAside(url)
            return
        }

        let decoder = JSONDecoder()
        var decoded: [JevComparisonRecord] = []
        for element in elements {
            guard let elementData = try? JSONSerialization.data(
                withJSONObject: element, options: .fragmentsAllowed)
            else { continue }  // unreachable: it was just parsed from JSON
            if let record = try? decoder.decode(JevComparisonRecord.self, from: elementData) {
                decoded.append(record)
            } else {
                unreadable.append(elementData)
            }
        }
        comparisons = decoded.sorted { $0.capturedAt < $1.capturedAt }
    }

    /// Renames an unparseable day file so the next save starts a new one beside it.
    private func setAside(_ url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = url.deletingLastPathComponent()
            .appendingPathComponent("jev-comparisons-\(todayKey).unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: aside)
    }

    /// Serial utility queue for disk writes. Static so every instance writing the same per-day
    /// file shares one ordered queue — the file on disk is always the latest snapshot.
    private static let persistQueue = DispatchQueue(label: "com.quant.jevComparisonStore.persist",
                                                    qos: .utility)

    private func persist() {
        let snapshot = comparisons
        let kept = unreadable
        let url = fileURL(for: todayKey)
        Self.persistQueue.async {
            guard var data = try? JSONEncoder().encode(snapshot) else { return }
            if !kept.isEmpty {
                // Append the records this build couldn't read, so saving never deletes them.
                guard var array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return }
                array.append(contentsOf: kept.compactMap {
                    try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed)
                })
                guard let merged = try? JSONSerialization.data(withJSONObject: array) else { return }
                data = merged
            }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Blocks until queued writes complete. Test hook only.
    static func flushPendingWrites() {
        persistQueue.sync {}
    }

    private func fileURL(for key: String) -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jev-comparisons-\(key).json")
    }

    private func dateKey(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
