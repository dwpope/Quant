//
//  WatchSessionDelegate.swift
//  QuantWatch Watch App
//
//  Created for Ticket 4.4 — WatchConnectivity Setup
//
//  Receives nudge events from the iPhone and plays a haptic tap.
//

import WatchConnectivity
import WatchKit
import os.log

/// Receives nudge messages from the iPhone and delivers haptic feedback.
///
/// Activates the WCSession on init and listens for `["type": "nudge"]`
/// messages. When one arrives, plays a `.notification` haptic on the Watch.
final class WatchSessionDelegate: NSObject, ObservableObject {

    // MARK: - Published State

    /// Timestamp of the last nudge received, for debug display.
    @Published var lastNudgeTime: Date?

    /// Whether the WCSession is currently activated and reachable.
    @Published var isConnected: Bool = false

    // MARK: - Private Properties

    private let logger = Logger(subsystem: "com.quant.posture", category: "WatchSession")

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
        logger.info("WCSession activation requested on Watch")
    }

    // MARK: - Private Methods

    private func handleNudge() {
        WKInterfaceDevice.current().play(.notification)
        lastNudgeTime = Date()
        logger.info("⌚ Haptic nudge delivered")
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionDelegate: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isConnected = activationState == .activated
        }
        if let error {
            logger.error("WCSession activation failed: \(error.localizedDescription)")
        } else {
            logger.info("WCSession activated on Watch")
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message["type"] as? String == "nudge" else { return }
        DispatchQueue.main.async {
            self.handleNudge()
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard userInfo["type"] as? String == "nudge" else { return }
        DispatchQueue.main.async {
            self.handleNudge()
        }
    }
}
