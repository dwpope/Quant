import Foundation
import PostureLogic

/// One item waiting in the training-mode label queue.
///
/// Created by `AppModel` when `SipDetector.onSipConfirmed` fires while
/// training mode is enabled. The corresponding `SipEvent` has already
/// been persisted by the time a `PendingSipLabel` exists — this struct
/// just carries the join key plus the information the confirmation
/// popup needs to display.
///
/// Entirely additive to the training-mode workflow. Ripping out training
/// mode means deleting this file along with `SipLabelQueue`.
struct PendingSipLabel: Identifiable, Equatable {
    /// Same UUID as the underlying `SipEvent` — this is how
    /// `SipLabelQueue.onResolved` calls back into `SipStore.setLabel`.
    let id: UUID

    /// Wall-clock time the sip started (seconds since 1970). Matches
    /// `SipEvent.timestamp`.
    let sipStartTimestamp: TimeInterval

    /// Duration of the detected sip (seconds). Matches `SipEvent.duration`.
    let sipDuration: TimeInterval

    /// Detector score snapshot at confirmation time. Display-only —
    /// surfaced in the debug overlay / label popup so the user has
    /// context for the labeling decision.
    let scores: SipDetector.Scores
}
