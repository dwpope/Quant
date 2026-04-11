import Combine
import Foundation
import PostureLogic

/// A FIFO queue of pending training-mode label prompts, plus the
/// resolution semantics (apply a label, dismiss as unconfirmed, drain
/// everything on background) used by the confirmation popup.
///
/// `AppModel` owns an instance and wires:
/// 1. `SipDetector.onSipConfirmed` → `enqueue(_:)` when training mode is on.
/// 2. `$active` → the confirmation popup view.
/// 3. `UIApplication.willResignActiveNotification` → `drainAsUnconfirmed()`.
/// 4. A 15-second `Timer` tied to `$active` changes → `fireActiveTimeout()`.
///
/// Kept deliberately timer-free internally so it can be unit-tested
/// without spinning up a full `AppModel`, a run loop, or real wall-clock
/// waits. The production timeout lives in `AppModel` and calls
/// `fireActiveTimeout()` when the 15-second window expires.
@MainActor
final class SipLabelQueue: ObservableObject {

    // MARK: - Published State

    /// The item currently shown in the confirmation popup, or `nil` if
    /// the queue is empty. `@Published` so SwiftUI views can observe it
    /// and sheets can bind to it directly.
    @Published private(set) var active: PendingSipLabel?

    /// Items waiting behind `active`, oldest first.
    private(set) var pending: [PendingSipLabel] = []

    // MARK: - Callbacks

    /// Fired when an item is resolved — either by the user labeling it,
    /// by the 15-second timeout, or by a background drain. The owner
    /// (`AppModel`) uses this to call `SipStore.setLabel(id:label:)`.
    var onResolved: ((UUID, SipEvent.Label) -> Void)?

    // MARK: - Config

    /// How long the popup stays on screen before it auto-dismisses as
    /// `.unconfirmed`. Exposed read-only for the owner to schedule its
    /// production timer with a matching value.
    let timeoutSeconds: TimeInterval

    // MARK: - Initialization

    init(timeoutSeconds: TimeInterval = 15) {
        self.timeoutSeconds = timeoutSeconds
    }

    // MARK: - Queue operations

    /// Append a new label prompt. If nothing is active it is promoted
    /// immediately; otherwise it queues behind any existing items.
    func enqueue(_ item: PendingSipLabel) {
        if active == nil {
            active = item
        } else {
            pending.append(item)
        }
    }

    /// Resolve the currently-active item with an explicit user label.
    /// No-op if `id` doesn't match the active item (the active item may
    /// have changed by the time a delayed UI callback arrives).
    func applyLabel(_ label: SipEvent.Label, to id: UUID) {
        guard let current = active, current.id == id else { return }
        resolve(id: current.id, as: label)
    }

    /// Resolve the currently-active item as `.unconfirmed`. Called by
    /// the production 15-second timer and by an explicit "Skip" button.
    /// No-op if `id` doesn't match the active item.
    func dismissAsUnconfirmed(id: UUID) {
        guard let current = active, current.id == id else { return }
        resolve(id: current.id, as: .unconfirmed)
    }

    /// Drains the queue by resolving the active item and every pending
    /// item as `.unconfirmed`. Called when the app leaves the foreground
    /// so training data never ends up in a half-labeled state.
    func drainAsUnconfirmed() {
        if let current = active {
            onResolved?(current.id, .unconfirmed)
        }
        for item in pending {
            onResolved?(item.id, .unconfirmed)
        }
        active = nil
        pending.removeAll()
    }

    /// Immediately resolve the active item as `.unconfirmed` and
    /// promote the next one. Called by the 15-second timer in
    /// `AppModel`, and directly from tests so they don't have to wait.
    func fireActiveTimeout() {
        guard let current = active else { return }
        resolve(id: current.id, as: .unconfirmed)
    }

    // MARK: - Private

    private func resolve(id: UUID, as label: SipEvent.Label) {
        onResolved?(id, label)
        if !pending.isEmpty {
            active = pending.removeFirst()
        } else {
            active = nil
        }
    }
}
