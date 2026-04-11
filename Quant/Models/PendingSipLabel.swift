import Foundation
import PostureLogic

/// A confirmed sip event waiting for a human-supplied training label.
///
/// `SipLabelQueue` holds a FIFO queue of these items and promotes them
/// one at a time to `AppModel.activeSipLabelItem`, which drives the
/// confirmation popup in the UI.
///
/// `id` matches the underlying `SipEvent.id` so `SipStore.setLabel` can
/// be called by key when the user responds (or the timeout fires).
struct PendingSipLabel: Identifiable {

    /// Same UUID as the corresponding `SipEvent`.
    let id: UUID

    /// The event awaiting classification.
    let event: SipEvent

    /// Detector signal scores captured at confirmation time, so the
    /// label popup can display proximity / velocity / duration values
    /// and the active wrist without re-reading detector state.
    let scores: SipDetector.Scores?

    /// Wall-clock time at which the item entered the queue. Used for
    /// audit logging and potential future display ("5s ago…").
    let enqueuedAt: Date

    init(event: SipEvent, scores: SipDetector.Scores? = nil, enqueuedAt: Date = Date()) {
        self.id = event.id
        self.event = event
        self.scores = scores
        self.enqueuedAt = enqueuedAt
    }
}
