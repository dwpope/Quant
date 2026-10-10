//
//  WristNudgeSession.swift
//  QuantWatch Watch App
//
//  Keeps the app running an hour at a time, so nudges arrive on time.
//

import Foundation
import UserNotifications
import WatchKit

/// What `WristNudgeSession` needs from `WKExtendedRuntimeSession`, so tests can stand in for it.
protocol ExtendedRuntime: AnyObject {
    func start()
    func invalidate()
}

extension WKExtendedRuntimeSession: ExtendedRuntime {}

enum WristNudgeState: Equatable {
    /// Not running: a nudge waits for watchOS to wake the app.
    case off
    case starting
    /// Running until then: a nudge is shown the moment it comes.
    case on(until: Date)
    /// watchOS refused. Shown, and tried again only when the app is opened.
    case unavailable(String)
}

/// Keeps the Watch app running an hour at a time, so nudges arrive on time (2026-10-10).
///
/// In session 3 all four nudges were queued for a closed Watch app and arrived late: watchOS wakes
/// a closed app when it chooses. A physical-therapy extended runtime session (the
/// `WKBackgroundModes` entry in Info.plist) keeps the app running in the background for up to an
/// hour, so a nudge is posted the moment it arrives. Opening the app starts one, as it must:
/// watchOS only starts a session for an app that's open. Near the hour a notification asks for a
/// tap, which opens the app and starts the next; if the app is open when the hour ends, the next
/// starts straight away.
final class WristNudgeSession: NSObject, ObservableObject {

    static let shared = WristNudgeSession(
        makeRuntime: { owner in
            let session = WKExtendedRuntimeSession()
            session.delegate = owner
            return session
        },
        notifyRenewal: {
            UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: "wrist-renew-\(UUID().uuidString)",
                content: WristNudgeSession.renewalContent(), trigger: nil))
        },
        isAppActive: { WKApplication.shared().applicationState == .active })

    @Published private(set) var state: WristNudgeState = .off {
        didSet {
            let on: Bool
            if case .on = state { on = true } else { on = false }
            lock.withLock { running = on }
        }
    }

    /// Whether the app is being kept running. Read from WatchConnectivity's queue, for the
    /// arrival report.
    var isOn: Bool { lock.withLock { running } }

    private let lock = NSLock()
    private var running = false
    private var runtime: ExtendedRuntime?
    private let makeRuntime: (WristNudgeSession) -> ExtendedRuntime
    private let notifyRenewal: () -> Void
    private let isAppActive: () -> Bool

    init(makeRuntime: @escaping (WristNudgeSession) -> ExtendedRuntime,
         notifyRenewal: @escaping () -> Void,
         isAppActive: @escaping () -> Bool) {
        self.makeRuntime = makeRuntime
        self.notifyRenewal = notifyRenewal
        self.isAppActive = isAppActive
    }

    // MARK: - Events

    /// The app came to the front: start an hour, unless one is running or starting.
    func appBecameActive() {
        switch state {
        case .starting, .on: return
        case .off, .unavailable: break
        }
        let runtime = makeRuntime(self)
        self.runtime = runtime
        state = .starting
        runtime.start()
    }

    func didStart(until end: Date) {
        state = .on(until: end)
    }

    /// Shortly before the hour ends.
    func willExpire() {
        notifyRenewal()
    }

    /// The session ended: `error` when watchOS refused or stopped it with one.
    func didEnd(error: String?) {
        runtime = nil
        if let error {
            state = .unavailable(error)
            return
        }
        state = .off
        if isAppActive() { appBecameActive() }
    }

    // MARK: - Copy

    static func statusLine(for state: WristNudgeState) -> String {
        switch state {
        case .on(let until):
            return "Nudges on time until \(until.formatted(date: .omitted, time: .shortened))"
        case .starting:
            return "Keeping nudges on time…"
        case .off:
            return "Nudges may arrive late while Aware is closed"
        case .unavailable(let reason):
            return "Can't keep nudges on time: \(reason)"
        }
    }

    static func renewalContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Aware"
        content.body = "Open Aware to keep nudges on time for another hour"
        content.sound = .default
        return content
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension WristNudgeSession: WKExtendedRuntimeSessionDelegate {

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        let end = extendedRuntimeSession.expirationDate ?? Date().addingTimeInterval(3600)
        DispatchQueue.main.async { self.didStart(until: end) }
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        DispatchQueue.main.async { self.willExpire() }
    }

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                error: Error?) {
        // Only the hour running out starts the next on its own; anything else is shown, so a
        // refusal can't loop.
        let message: String?
        switch reason {
        case .expired, .none: message = nil
        case .error: message = error?.localizedDescription ?? "an error"
        case .sessionInProgress: message = "another session is running"
        case .resignedFrontmost: message = "Aware was closed"
        case .suppressedBySystem: message = "watchOS paused it"
        @unknown default: message = "it ended"
        }
        DispatchQueue.main.async { self.didEnd(error: message) }
    }
}
