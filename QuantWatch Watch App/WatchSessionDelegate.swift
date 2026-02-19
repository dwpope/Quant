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

    private func handleNudge(_ hapticType: WKHapticType = .notification) {
        WKInterfaceDevice.current().play(hapticType)
        lastNudgeTime = Date()
        logger.info("⌚ Haptic nudge delivered")
    }

    private func parseHapticType(from message: [String: Any]) -> WKHapticType {
        guard let name = message["haptic"] as? String else { return .notification }
        switch name {
        case "notification": return .notification
        case "directionUp": return .directionUp
        case "directionDown": return .directionDown
        case "success": return .success
        case "failure": return .failure
        case "retry": return .retry
        case "start": return .start
        case "stop": return .stop
        case "click": return .click
        default: return .notification
        }
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
        let haptic = parseHapticType(from: message)
        DispatchQueue.main.async {
            self.handleNudge(haptic)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard userInfo["type"] as? String == "nudge" else { return }
        let haptic = parseHapticType(from: userInfo)
        DispatchQueue.main.async {
            self.handleNudge(haptic)
        }
    }
}
