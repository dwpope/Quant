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
import Combine
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

    // Teardown only releases stored properties; it touches no main-actor state.
    // Marking it `nonisolated` keeps Swift's MainActor isolated-deinit
    // back-deploy shim out of XCTest's NSInvocation-driven dealloc path, which
    // otherwise corrupts the heap and aborts under Xcode 26 / iOS 26.
    nonisolated deinit {}

    // MARK: - Debug State

    /// Whether a Watch is paired with this iPhone.
    private(set) var isPaired: Bool = false

    /// Whether the paired Watch is currently reachable for real-time messaging.
    private(set) var isReachable: Bool = false

    /// Timestamp of the last successful nudge send.
    private(set) var lastSentTime: Date?

    /// Total number of nudges sent this session.
    private(set) var totalSent: Int = 0

    // MARK: - Publishers

    /// Fires when the Watch requests a recalibration.
    let calibrationRequested = PassthroughSubject<Void, Never>()

    /// Fires when the Watch sends updated calibration settings.
    let settingsReceived = PassthroughSubject<[String: Any], Never>()

    /// Fires when the Watch, used as a remote for Jev captures, asks for something.
    let jevRemoteCommand = PassthroughSubject<JevRemote.Command, Never>()

    /// Fires when the Watch asks to silence nudges, with the minutes, 0 to resume.
    let silenceRequested = PassthroughSubject<Int, Never>()

    /// Fires when the Watch reports a nudge arrived, for the posture log.
    let nudgeArrived = PassthroughSubject<NudgeArrival, Never>()

    /// Fires with the new value whenever the Watch app becomes reachable or stops being so.
    let reachabilityChanged = PassthroughSubject<Bool, Never>()

    // MARK: - Private Properties

    private let logger = Logger(subsystem: "com.quant.posture", category: "WatchConnectivity")

    // MARK: - Settings Keys

    static let settingsKeys: [String] = [
        "com.quant.cal.maxPositionVariance",
        "com.quant.cal.maxAngleVariance",
        "com.quant.cal.samplingDuration",
        "com.quant.cal.countdownDuration",
        "com.quant.posture.forwardCreep.v2",
        "com.quant.posture.twist",
        "com.quant.posture.sideLean",
        "com.quant.posture.driftingToBad"
    ]

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
    ///
    /// The app always sends the default haptic. The on-screen haptic picker was
    /// removed on 2026-09-26; the parameter stays so the message format, and the
    /// Watch's `parseHapticType`, are unchanged.
    ///
    /// `body` is the line the Watch shows: the nudge reason's coaching line. Every nudge used to
    /// say "Straighten up!", the wrong advice for a head held turned (2026-10-04).
    ///
    /// Returns how it left, for the posture log; `onQueuedAfterFailedSend` runs if a straight
    /// send fails and the nudge is queued instead.
    @discardableResult
    func sendNudge(hapticType: String = "failure", body: String? = nil,
                   onQueuedAfterFailedSend: (@MainActor () -> Void)? = nil) -> NudgeDelivery {
        let supported = WCSession.isSupported()
        let session: WCSession? = supported ? WCSession.default : nil
        let route = Self.nudgeRoute(isSupported: supported, isPaired: session?.isPaired ?? false,
                                    isReachable: session?.isReachable ?? false)
        guard let session, route != .noWatch else {
            logger.debug("No Watch paired — skipping nudge send")
            return .noWatch
        }
        let message = Self.nudgeMessage(hapticType: hapticType, body: body, sentAt: Date())

        if route == .sent {
            session.sendMessage(message, replyHandler: nil) { [weak self] error in
                // The app closed between the check and the send: queue it, so the Watch app is
                // woken to show it, rather than lose it (2026-10-08).
                session.transferUserInfo(message)
                Task { @MainActor in
                    self?.logger.error("sendMessage failed, nudge queued: \(error.localizedDescription)")
                    onQueuedAfterFailedSend?()
                }
            }
            logger.info("⌚ Nudge sent via sendMessage (total: \(self.totalSent + 1))")
        } else {
            session.transferUserInfo(message)
            logger.info("⌚ Nudge queued via transferUserInfo (total: \(self.totalSent + 1))")
        }
        lastSentTime = Date()
        totalSent += 1
        return route
    }

    /// How a nudge leaves for the Watch: straight to its app when open, queued when closed (the
    /// Watch app is woken to show it), or not at all without a paired Watch.
    static func nudgeRoute(isSupported: Bool, isPaired: Bool, isReachable: Bool) -> NudgeDelivery {
        guard isSupported, isPaired else { return .noWatch }
        return isReachable ? .sent : .queued
    }

    /// How many minutes the Watch asked to silence nudges for, 0 to resume, or nil when the
    /// message isn't a well-formed request. The Watch's `NudgeSilence.request` writes it.
    static func silenceMinutes(from message: [String: Any]) -> Int? {
        guard message["type"] as? String == "silenceNudges",
              let minutes = (message["minutes"] as? NSNumber)?.intValue, minutes >= 0
        else { return nil }
        return minutes
    }

    /// Tells the Watch when the silence ends, 0 when nudges aren't silenced. Calendar seconds.
    static func nudgeSilenceMessage(until: Date?) -> [String: Any] {
        ["type": "nudgeSilence", "until": until?.timeIntervalSince1970 ?? 0]
    }

    /// Send the silence to the Watch while its app is open. Like the Jev status, no queued
    /// fallback: the Watch asks again when it next connects.
    func sendNudgeSilence(until: Date?) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.isPaired, session.isReachable else { return }
        session.sendMessage(Self.nudgeSilenceMessage(until: until), replyHandler: nil) { [weak self] error in
            Task { @MainActor in
                self?.logger.error("Nudge silence send failed: \(error.localizedDescription)")
            }
        }
    }

    /// The nudge message, `body` only when there is one. The Watch's `NudgeMessage` reads it.
    /// `sentAt` lets the Watch report how late it arrived (2026-10-10).
    static func nudgeMessage(hapticType: String, body: String?, sentAt: Date? = nil) -> [String: Any] {
        var message: [String: Any] = ["type": "nudge", "haptic": hapticType]
        if let body, !body.isEmpty { message["body"] = body }
        if let sentAt { message["sentAt"] = sentAt.timeIntervalSince1970 }
        return message
    }

    /// The Watch's report of when a nudge arrived (its `NudgeMessage.arrivalReport`), or nil.
    nonisolated static func nudgeArrival(from message: [String: Any]) -> NudgeArrival? {
        guard message["type"] as? String == "nudgeArrived",
              let sentAt = (message["sentAt"] as? NSNumber)?.doubleValue,
              let arrivedAt = (message["arrivedAt"] as? NSNumber)?.doubleValue,
              let via = message["via"] as? String
        else { return nil }
        return NudgeArrival(sentAt: Date(timeIntervalSince1970: sentAt),
                            arrivedAt: Date(timeIntervalSince1970: arrivedAt), via: via,
                            wristSession: message["wristSession"] as? Bool ?? false)
    }

    /// Send the Jev remote's status to the Watch.
    ///
    /// Only while the Watch app is open. Unlike a nudge there is no queued fallback: a status
    /// is only worth anything while someone is looking at it, and the Watch asks for a fresh
    /// one when its screen opens.
    func sendJevStatus(_ status: JevRemote.Status) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(status.message, replyHandler: nil) { [weak self] error in
            Task { @MainActor in
                self?.logger.error("Jev status send failed: \(error.localizedDescription)")
            }
        }
    }

    /// Push calibration settings to the Watch via applicationContext.
    func sendSettings(_ settings: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.isPaired else {
            logger.debug("No Watch paired — skipping settings sync")
            return
        }

        var context = (try? session.applicationContext) ?? [:]
        context["type"] = "settings"
        for (key, value) in settings {
            context[key] = value
        }

        do {
            try session.updateApplicationContext(context)
            logger.info("⌚ Settings sent to Watch via applicationContext")
        } catch {
            logger.error("Failed to update applicationContext: \(error.localizedDescription)")
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
            reachabilityChanged.send(isReachable)
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            isPaired = session.isPaired
            isReachable = session.isReachable
            logger.info("WCSession watch state changed — paired: \(self.isPaired)")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handleReceivedMessage(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            handleReceivedMessage(message)
            replyHandler(["status": "ok"])
        }
    }

    /// Queued from the Watch: its report of a nudge's arrival, when the phone couldn't take a
    /// message.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let arrival = Self.nudgeArrival(from: userInfo) else { return }
        Task { @MainActor in
            nudgeArrived.send(arrival)
        }
    }

    // MARK: - Message Handling

    private func handleReceivedMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }

        switch type {
        case "nudgeArrived":
            if let arrival = Self.nudgeArrival(from: message) { nudgeArrived.send(arrival) }
        case "calibrate":
            logger.info("⌚ Calibration request received from Watch")
            calibrationRequested.send()
        case "settings":
            logger.info("⌚ Settings received from Watch")
            settingsReceived.send(message)
        case "silenceNudges":
            if let minutes = Self.silenceMinutes(from: message) {
                silenceRequested.send(minutes)
            }
        default:
            if let command = JevRemote.Command(message: message) {
                jevRemoteCommand.send(command)
            } else {
                logger.debug("Unknown message type: \(type)")
            }
        }
    }
}

/// How a nudge left for the Watch, for the posture log (2026-10-08). In Dave's second real-use
/// hour the phone fired twice and he felt one buzz, and nothing recorded which way each went.
enum NudgeDelivery: String {
    /// Straight to the Watch app, which was open.
    case sent
    /// Queued: the Watch app was closed, and is woken to show it.
    case queued
    /// Sent straight, but the Watch app had closed, so it was queued.
    case queuedAfterFailedSend
    /// No paired Watch.
    case noWatch
}

/// When a nudge reached the Watch, as the Watch reported it (2026-10-10).
struct NudgeArrival: Equatable {
    let sentAt: Date
    let arrivedAt: Date
    /// "message" (straight to the running app) or "queued".
    let via: String
    /// Whether the Watch app was being kept running (`WristNudgeSession`).
    let wristSession: Bool
}
