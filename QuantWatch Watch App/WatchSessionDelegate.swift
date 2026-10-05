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

    // MARK: - Jev capture remote

    /// The phone's latest report. Nil until the phone answers.
    @Published var jevStatus: JevRemoteStatus?

    /// True from a Classify tap until the phone's answer to it arrives.
    @Published var jevBusy = false

    /// When the pending tap was made, for the countdown to the phone's capture.
    @Published var jevTapDate: Date?

    /// Whether the phone app can take a message right now. Taps need this; nudges do not.
    @Published var isPhoneReachable = false

    /// The phone's attempt count and newest record when the pending tap was sent.
    private var pendingTap: (attempts: Int, recordID: UUID?, token: UUID)?

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

    // MARK: - Jev capture remote

    /// Ask the phone to classify the posture you are holding right now.
    ///
    /// This is the point of the remote: tapping the phone meant leaning toward it, and the
    /// capture recorded the lean. The haptic says how it went, so you needn't look.
    func sendJevClassify() {
        guard !jevBusy else { return }
        beginJevTap()
        if !sendToPhone(JevRemoteMessage.classify(), what: "classify") {
            cancelJevTap()
        }
    }

    /// Judge the capture the Watch is showing. Names the record, so a capture that lands in
    /// between can't take the judgement meant for this one.
    func sendJevJudge(recordID: UUID, verdict: JevRemoteVerdict, trueClass: String? = nil) {
        sendToPhone(JevRemoteMessage.judge(recordID: recordID, verdict: verdict, trueClass: trueClass),
                    what: "judge")
    }

    /// Flag the capture as a mistake. It stays on the phone, marked, and the analysis skips it.
    func sendJevDiscard(recordID: UUID) {
        sendToPhone(JevRemoteMessage.discard(recordID: recordID), what: "discard")
    }

    /// Ask the phone for a fresh status, as when the capture screen opens.
    func requestJevStatus() {
        sendToPhone(JevRemoteMessage.statusRequest(), what: "status request")
    }

    /// Marks a tap as waiting for its answer. Split out of ``sendJevClassify()`` so tests can
    /// drive it without a paired phone.
    func beginJevTap() {
        let token = UUID()
        pendingTap = (jevStatus?.attempts ?? -1, jevStatus?.lastRecord?.id, token)
        jevBusy = true
        jevTapDate = Date()
        // The phone waits `captureDelay`, then answers well within a second. If nothing comes
        // back after that, don't stay stuck.
        let timeout = 10 + (jevStatus?.captureDelay ?? 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.pendingTap?.token == token else { return }
            self.cancelJevTap()
            WKInterfaceDevice.current().play(.failure)
        }
    }

    private func cancelJevTap() {
        pendingTap = nil
        jevBusy = false
        jevTapDate = nil
    }

    /// Takes in a status from the phone, and settles a pending tap if this is its answer.
    func receiveJevStatus(_ status: JevRemoteStatus) {
        jevStatus = status
        guard let pending = pendingTap,
              let outcome = JevRemoteStatus.outcome(of: status, previousRecordID: pending.recordID,
                                                    attemptsWhenSent: pending.attempts)
        else { return }
        cancelJevTap()
        WKInterfaceDevice.current().play(outcome == .captured ? .success : .failure)
    }

    @discardableResult
    private func sendToPhone(_ message: [String: Any], what: String) -> Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            logger.warning("iPhone not reachable — cannot send \(what)")
            return false
        }
        session.sendMessage(message, replyHandler: nil) { [weak self] error in
            self?.logger.error("Failed to send \(what): \(error.localizedDescription)")
        }
        return true
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

    private func handleNudge(_ hapticType: WKHapticType = .notification, body: String) {
        WKInterfaceDevice.current().play(hapticType)
        scheduleNudgeNotification(body: body)
        lastNudgeTime = Date()
        logger.info("⌚ Haptic nudge delivered")
    }

    private func scheduleNudgeNotification(body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Posture Check"
        content.body = body
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
            self.isPhoneReachable = session.isReachable
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
            let body = NudgeMessage.body(from: message)
            DispatchQueue.main.async {
                self.handleNudge(haptic, body: body)
            }
        case "jevStatus":
            guard let status = JevRemoteStatus(message: message) else {
                logger.error("Malformed jevStatus from iPhone")
                return
            }
            DispatchQueue.main.async {
                self.receiveJevStatus(status)
            }
        default:
            break
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isPhoneReachable = reachable
            if reachable { self.requestJevStatus() }
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard userInfo["type"] as? String == "nudge" else { return }
        let haptic = parseHapticType(from: userInfo)
        let body = NudgeMessage.body(from: userInfo)
        DispatchQueue.main.async {
            self.handleNudge(haptic, body: body)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.applySettings(from: applicationContext)
        }
    }
}
