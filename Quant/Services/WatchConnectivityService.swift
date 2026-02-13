//
//  WatchConnectivityService.swift
//  Quant
//
//  Created for Ticket 4.4 — WatchConnectivity Setup
//
//  Sends nudge events to the paired Apple Watch so it can deliver
//  a haptic tap when the NudgeEngine fires.
//
//  Uses `WCSession.sendMessage` for real-time delivery (<2s), with
//  `transferUserInfo` as a fallback when the Watch is not reachable.
//

import WatchConnectivity
import os.log

/// Sends nudge events to the paired Apple Watch for haptic delivery.
///
/// Usage:
/// ```swift
/// let watchService = WatchConnectivityService()
/// watchService.sendNudge()  // Sends nudge to Watch
/// ```
///
/// The service is designed to be created once (in AppModel) and reused.
/// If no Watch is paired the service is a graceful no-op.
@MainActor
final class WatchConnectivityService: NSObject {

    // MARK: - Debug State

    /// Whether a Watch is paired with this iPhone.
    private(set) var isPaired: Bool = false

    /// Whether the paired Watch is currently reachable for real-time messaging.
    private(set) var isReachable: Bool = false

    /// Timestamp of the last successful nudge send.
    private(set) var lastSentTime: Date?

    /// Total number of nudges sent this session.
    private(set) var totalSent: Int = 0

    // MARK: - Private Properties

    private let logger = Logger(subsystem: "com.quant.posture", category: "WatchConnectivity")

    // MARK: - Initialization

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            logger.info("WCSession not supported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        logger.info("WCSession activation requested")
    }

    // MARK: - Public Methods

    /// Send a nudge event to the paired Apple Watch.
    ///
    /// Uses `sendMessage` for real-time delivery. If the Watch is not
    /// reachable, falls back to `transferUserInfo` which will be delivered
    /// when the Watch wakes up.
    ///
    /// Safe to call at any time — if no Watch is paired or WCSession
    /// is not supported, this is a no-op.
    func sendNudge() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        let message: [String: Any] = ["type": "nudge"]

        guard session.isPaired else {
            logger.debug("No Watch paired — skipping nudge send")
            return
        }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] error in
                Task { @MainActor in
                    self?.logger.error("sendMessage failed: \(error.localizedDescription)")
                }
            }
            lastSentTime = Date()
            totalSent += 1
            logger.info("⌚ Nudge sent via sendMessage (total: \(self.totalSent))")
        } else {
            session.transferUserInfo(message)
            lastSentTime = Date()
            totalSent += 1
            logger.info("⌚ Nudge queued via transferUserInfo (total: \(self.totalSent))")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isPaired = session.isPaired
            isReachable = session.isReachable
            if let error {
                logger.error("WCSession activation failed: \(error.localizedDescription)")
            } else {
                logger.info("WCSession activated — paired: \(self.isPaired), reachable: \(self.isReachable)")
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            logger.info("WCSession became inactive")
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            logger.info("WCSession deactivated — reactivating")
        }
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
            logger.info("WCSession reachability changed: \(self.isReachable)")
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            isPaired = session.isPaired
            isReachable = session.isReachable
            logger.info("WCSession watch state changed — paired: \(self.isPaired)")
        }
    }
}
