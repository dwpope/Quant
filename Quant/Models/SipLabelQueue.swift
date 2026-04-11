import Foundation
import PostureLogic

/// A FIFO queue of `PendingSipLabel` items with a per-item timeout.
///
/// Extracted from `AppModel` so the queue semantics can be tested
/// independently — no camera pipeline or live stores needed.
///
/// ## Lifecycle
///
/// 1. `enqueue(_:)` — adds a new item. If the queue was empty the item
///    becomes active immediately and its timeout starts.
/// 2. `applyLabel(_:toID:)` — user chose a category. Fires `onLabel`,
///    cancels the timeout, and promotes the next pending item.
/// 3. `dismissActiveAsUnconfirmed()` — timeout fired or user cancelled
///    without choosing. Fires `onLabel` with `.unconfirmed`.
/// 4. `drainAsUnconfirmed()` — app entering background. All items (active
///    + pending) are immediately labeled `.unconfirmed` so nothing is
///    left in limbo while the app is suspended.
///
/// ## Threading
///
/// All methods must be called on `@MainActor`. Callbacks (`onLabel`,
/// `onActiveItemChanged`) are always invoked on `@MainActor` as well.
@MainActor
final class SipLabelQueue {

    // MARK: - Callbacks

    /// Called when a label is determined for an item — either by the user,
    /// on timeout, or via `drainAsUnconfirmed`. Receives (id, label).
    /// AppModel forwards this to `SipStore.setLabel(id:label:)`.
    var onLabel: ((UUID, SipEvent.Label) -> Void)?

    /// Called whenever the active item changes. `nil` means the queue is
    /// empty and no popup should be shown.
    var onActiveItemChanged: ((PendingSipLabel?) -> Void)?

    // MARK: - State

    /// The item currently shown in the UI (nil = nothing pending).
    private(set) var activeItem: PendingSipLabel?

    /// Items waiting behind the active one, oldest first.
    private var pending: [PendingSipLabel] = []

    /// Cancels the running timeout when the item is resolved before expiry.
    private var timeoutTask: Task<Void, Never>?

    /// How long the user has to respond before the item auto-dismisses.
    let timeoutInterval: TimeInterval

    // MARK: - Initialization

    init(timeoutInterval: TimeInterval = 15) {
        self.timeoutInterval = timeoutInterval
    }

    // MARK: - Public API

    /// Enqueues a new item. If nothing is active, promotes it immediately.
    func enqueue(_ item: PendingSipLabel) {
        if activeItem == nil {
            activate(item)
        } else {
            pending.append(item)
        }
    }

    /// Applies a user-chosen label to the currently active item.
    /// No-op if `id` does not match the active item's id.
    func applyLabel(_ label: SipEvent.Label, toID id: UUID) {
        guard let item = activeItem, item.id == id else { return }
        finish(item, label: label)
    }

    /// Dismisses the active item as `.unconfirmed` (timeout or explicit cancel).
    /// No-op if the queue is empty.
    func dismissActiveAsUnconfirmed() {
        guard let item = activeItem else { return }
        finish(item, label: .unconfirmed)
    }

    /// Drains the entire queue — active item + all pending — writing
    /// `.unconfirmed` for each. Call on `UIApplication.didEnterBackgroundNotification`
    /// so no event is left in limbo while the process is suspended.
    func drainAsUnconfirmed() {
        timeoutTask?.cancel()
        timeoutTask = nil

        if let item = activeItem {
            onLabel?(item.id, .unconfirmed)
        }
        for item in pending {
            onLabel?(item.id, .unconfirmed)
        }
        pending.removeAll()
        activeItem = nil
        onActiveItemChanged?(nil)
    }

    // MARK: - Private

    private func activate(_ item: PendingSipLabel) {
        timeoutTask?.cancel()
        activeItem = item
        onActiveItemChanged?(item)
        startTimeout(for: item)
    }

    private func finish(_ item: PendingSipLabel, label: SipEvent.Label) {
        timeoutTask?.cancel()
        timeoutTask = nil
        onLabel?(item.id, label)
        activeItem = nil
        if pending.isEmpty {
            onActiveItemChanged?(nil)
        } else {
            let next = pending.removeFirst()
            activate(next)
        }
    }

    private func startTimeout(for item: PendingSipLabel) {
        let nanoseconds = UInt64(timeoutInterval * 1_000_000_000)
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return  // Cancelled — item was resolved before the timeout fired.
            }
            self?.dismissActiveAsUnconfirmed()
        }
    }
}
