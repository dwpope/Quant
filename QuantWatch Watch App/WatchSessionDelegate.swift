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
import UserNotifications
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

    // MARK: - Calibration Settings (synced from iPhone)

    @Published var maxPositionVariance: Float = 0.06
    @Published var maxAngleVariance: Float = 6.0
    @Published var samplingDuration: Double = 5.0
    @Published var countdownDuration: Int = 3

    // MARK: - Posture Threshold Settings (synced from iPhone)
    // Defaults must match PostureThresholds() in PostureLogic

    @Published var forwardCreepThreshold: Float = 0.03
    @Published var twistThreshold: Float = 15.0
    @Published var sideLeanThreshold: Float = 0.08
    @Published var driftingToBadThreshold: Double = 60.0

    // MARK: - Settings Keys

    private enum Keys {
        static let maxPositionVariance = "com.quant.cal.maxPositionVariance"
        static let maxAngleVariance = "com.quant.cal.maxAngleVariance"
        static let samplingDuration = "com.quant.cal.samplingDuration"
        static let countdownDuration = "com.quant.cal.countdownDuration"
        static let forwardCreepThreshold = "com.quant.posture.forwardCreep"
        static let twistThreshold = "com.quant.posture.twist"
        static let sideLeanThreshold = "com.quant.posture.sideLean"
        static let driftingToBadThreshold = "com.quant.posture.driftingToBad"
    }

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

    // MARK: - Public Methods

    /// Request notification permission so nudges can appear as visible alerts.
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                self.logger.error("Notification permission error: \(error.localizedDescription)")
            } else {
                self.logger.info("Notification permission granted: \(granted)")
            }
        }
    }

    /// Send a calibration request to the iPhone.
    func sendCalibrateRequest() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            logger.warning("WCSession not activated — cannot send calibrate request")
            return
        }

        let message: [String: Any] = ["type": "calibrate"]
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] error in
                self?.logger.error("Failed to send calibrate request: \(error.localizedDescription)")
            }
            logger.info("⌚ Calibrate request sent to iPhone")
        } else {
            logger.warning("iPhone not reachable — cannot send calibrate request")
        }
    }

    /// Reset posture thresholds to defaults and sync to iPhone.
    func resetPostureSettings() {
        forwardCreepThreshold = 0.03
        twistThreshold = 15.0
        sideLeanThreshold = 0.08
        driftingToBadThreshold = 60.0
        sendSettings()
    }

    /// Send updated calibration settings to the iPhone.
    func sendSettings() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            logger.warning("WCSession not activated — cannot send settings")
            return
        }

        let message: [String: Any] = [
            "type": "settings",
            Keys.maxPositionVariance: maxPositionVariance,
            Keys.maxAngleVariance: maxAngleVariance,
            Keys.samplingDuration: samplingDuration,
            Keys.countdownDuration: countdownDuration,
            Keys.forwardCreepThreshold: forwardCreepThreshold,
            Keys.twistThreshold: twistThreshold,
            Keys.sideLeanThreshold: sideLeanThreshold,
            Keys.driftingToBadThreshold: driftingToBadThreshold
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] error in
                self?.logger.error("Failed to send settings: \(error.localizedDescription)")
            }
            logger.info("⌚ Settings sent to iPhone")
        } else {
            logger.warning("iPhone not reachable — cannot send settings")
        }
    }

    // MARK: - Private Methods

    private func handleNudge(_ hapticType: WKHapticType = .notification) {
        WKInterfaceDevice.current().play(hapticType)
        scheduleNudgeNotification()
        lastNudgeTime = Date()
        logger.info("⌚ Haptic nudge delivered")
    }

    private func scheduleNudgeNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Posture Check"
        content.body = "Straighten up!"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "nudge-\(UUID().uuidString)",
            content: content,
            trigger: nil  // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                self.logger.error("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
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

    private func applySettings(from context: [String: Any]) {
        if let val = context[Keys.maxPositionVariance] as? Float {
            maxPositionVariance = val
        }
        if let val = context[Keys.maxAngleVariance] as? Float {
            maxAngleVariance = val
        }
        if let val = context[Keys.samplingDuration] as? Double {
            samplingDuration = val
        }
        if let val = context[Keys.countdownDuration] as? Int {
            countdownDuration = val
        }
        if let val = context[Keys.forwardCreepThreshold] as? Float {
            forwardCreepThreshold = val
        }
        if let val = context[Keys.twistThreshold] as? Float {
            twistThreshold = val
        }
        if let val = context[Keys.sideLeanThreshold] as? Float {
            sideLeanThreshold = val
        }
        if let val = context[Keys.driftingToBadThreshold] as? Double {
            driftingToBadThreshold = val
        }
        logger.info("⌚ Settings updated from iPhone")
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
            // Apply any settings that arrived before activation
            if !session.receivedApplicationContext.isEmpty {
                DispatchQueue.main.async {
                    self.applySettings(from: session.receivedApplicationContext)
                }
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        switch type {
        case "nudge":
            let haptic = parseHapticType(from: message)
            DispatchQueue.main.async {
                self.handleNudge(haptic)
            }
        default:
            break
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard userInfo["type"] as? String == "nudge" else { return }
        let haptic = parseHapticType(from: userInfo)
        DispatchQueue.main.async {
            self.handleNudge(haptic)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.applySettings(from: applicationContext)
        }
    }
}
