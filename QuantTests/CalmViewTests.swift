import CoreGraphics
import XCTest
import PostureLogic
@testable import Quant

/// The calm view (2026-10-20): your posture in a word and a column, from the glance the Watch is
/// sent, and a switch between it and the debug screen.
@MainActor
final class CalmViewTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func glance(_ state: PostureState, since: Date? = nil, headTurnedSince: Date? = nil,
                        nudgeAt: Date? = nil) -> PostureGlance {
        PostureGlance(state: state, since: since, headTurnedSince: headTurnedSince, nudgeAt: nudgeAt)
    }

    // MARK: - The switch

    /// Dave is still tuning the measurements: the debug screen comes first.
    func test_theMainScreen_startsInDebug() {
        XCTAssertEqual(MainScreenStyle.initial, .debug)
    }

    func test_theSwitch_goesToTheOtherView() {
        XCTAssertEqual(MainScreenStyle.debug.other, .calm)
        XCTAssertEqual(MainScreenStyle.calm.other, .debug)
    }

    /// The choice is kept under this key; renaming it would put everyone back in debug.
    func test_theChoice_isKeptUnderAStableKey() {
        XCTAssertEqual(MainScreenStyle.storageKey, "mainScreen.style")
        XCTAssertEqual(MainScreenStyle(rawValue: "calm"), .calm)
        XCTAssertEqual(MainScreenStyle(rawValue: "debug"), .debug)
    }

    /// Each side names where it goes, for VoiceOver.
    func test_theSwitch_namesWhereItGoes() {
        XCTAssertEqual(MainScreenStyle.debug.switchLabel, "Switch to calm view")
        XCTAssertEqual(MainScreenStyle.calm.switchLabel, "Switch to debug view")
    }

    // MARK: - The look

    func test_sittingWell_standsFull() {
        let look = CalmLook(glance: glance(.good), thermalLevel: .nominal)
        XCTAssertEqual(look, .sittingWell)
        XCTAssertEqual(look.band, .good)
        XCTAssertEqual(look.headline, "Sitting well")
    }

    func test_slouching_countsFromItsStart_towardsTheNudge() {
        let started = now.addingTimeInterval(-20), due = now.addingTimeInterval(40)
        let look = CalmLook(glance: glance(.drifting(since: 0), since: started, nudgeAt: due),
                            thermalLevel: .nominal)
        XCTAssertEqual(look, .slouching(since: started, sustained: false, nudgeAt: due))
        XCTAssertEqual(look.band, .drifting)
        XCTAssertEqual(look.headline, "Slouching")
        XCTAssertEqual(look.since, started)
        XCTAssertEqual(look.countdown(now: now), .until(due))
    }

    func test_stillSlouching_isTheBadBand() {
        let look = CalmLook(glance: glance(.bad(since: 0), since: now), thermalLevel: .nominal)
        XCTAssertEqual(look.band, .bad)
        XCTAssertEqual(look.headline, "Still slouching")
    }

    /// The posture is fine with the head turned, and the timeline beside the column draws that
    /// time green, so the column stays full; the word and the countdown say what's coming.
    func test_aHeadTurn_whileSittingWell_keepsTheColumnFull() {
        let turned = now.addingTimeInterval(-90), due = now.addingTimeInterval(210)
        let look = CalmLook(glance: glance(.good, headTurnedSince: turned, nudgeAt: due),
                            thermalLevel: .nominal)
        XCTAssertEqual(look, .headTurned(since: turned, nudgeAt: due))
        XCTAssertEqual(look.band, .good)
        XCTAssertEqual(look.headline, "Head turned")
        XCTAssertEqual(look.since, turned)
        XCTAssertEqual(look.countdown(now: now), .until(due))
    }

    func test_away_isTheSliver() {
        let look = CalmLook(glance: glance(.absent), thermalLevel: .nominal)
        XCTAssertEqual(look, .away)
        XCTAssertEqual(look.band, .away)
        XCTAssertEqual(look.headline, "Away")
        XCTAssertNil(look.countdown(now: now))
    }

    /// A stopped camera never shows the last posture as now.
    func test_aStoppedCamera_saysSo_withNoColumn() {
        let look = CalmLook(glance: .paused, thermalLevel: .nominal)
        XCTAssertEqual(look, .cameraPaused)
        XCTAssertNil(look.band)
        XCTAssertEqual(look.headline, "Camera paused")
    }

    /// At critical heat the camera stops to cool, which is the reason worth showing.
    func test_criticalHeat_saysCoolingDown_overAnyPosture() {
        for g in [glance(.good), .paused, glance(.drifting(since: 0), since: now)] {
            let look = CalmLook(glance: g, thermalLevel: .critical)
            XCTAssertEqual(look, .coolingDown)
            XCTAssertNil(look.band)
            XCTAssertEqual(look.headline, "Cooling down")
        }
    }

    /// The posture words are the timeline's, which are the card's and the Watch's.
    func test_theWords_areTheTimelines() {
        XCTAssertEqual(CalmLook.sittingWell.headline, PostureTimeline.Band.good.label)
        XCTAssertEqual(CalmLook.slouching(since: nil, sustained: false, nudgeAt: nil).headline,
                       PostureTimeline.Band.drifting.label)
        XCTAssertEqual(CalmLook.slouching(since: nil, sustained: true, nudgeAt: nil).headline,
                       PostureTimeline.Band.bad.label)
        XCTAssertEqual(CalmLook.away.headline, PostureTimeline.Band.away.label)
    }

    func test_theCountdown_isDue_onceItsTimeHasCome() {
        let look = CalmLook.slouching(since: now, sustained: true, nudgeAt: now.addingTimeInterval(-1))
        XCTAssertEqual(look.countdown(now: now), .due)
    }

    /// Silenced, stretching or over the hourly cap, the pipeline has no due time: no countdown.
    func test_noCountdown_withNoNudgeComing() {
        XCTAssertNil(CalmLook.slouching(since: now, sustained: false, nudgeAt: nil).countdown(now: now))
        XCTAssertNil(CalmLook.sittingWell.countdown(now: now))
    }

    /// The view reads the pipeline's own glance: before any frame, the camera hasn't started.
    func test_theAppsGlance_beforeAnyFrame_isPaused() {
        XCTAssertEqual(AppModel().livePostureGlance(), .paused)
    }

    /// The calm view's glance is steadied as the Watch's is: each frame works the starts out
    /// again, and their rounding can flip between neighbouring seconds, which made the Watch's
    /// timers jump back and forth (2026-10-11).
    func test_theCalmGlance_holdsItsTimes_throughASecondsJitter() {
        let model = AppModel()
        model.updateCalmGlance(glance(.drifting(since: 0), since: now, nudgeAt: now.addingTimeInterval(60)))
        model.updateCalmGlance(glance(.drifting(since: 0), since: now.addingTimeInterval(1),
                                      nudgeAt: now.addingTimeInterval(59)))
        XCTAssertEqual(model.calmGlance.since, now.timeIntervalSince1970)
        XCTAssertEqual(model.calmGlance.nudgeAt, now.addingTimeInterval(60).timeIntervalSince1970)
    }

    func test_theCalmGlance_followsAChange() {
        let model = AppModel()
        XCTAssertEqual(model.calmGlance, .paused, "nothing judged yet")
        model.updateCalmGlance(glance(.good))
        model.updateCalmGlance(glance(.drifting(since: 0), since: now))
        XCTAssertEqual(model.calmGlance.state, "drifting")
        XCTAssertEqual(model.calmGlance.since, now.timeIntervalSince1970)
    }

    /// A stopped recording's file stays offered for sharing, whichever screen shows: the
    /// debug panel's own state went with it on a switch to the calm view.
    func test_aStoppedRecording_staysOfferedForSharing() throws {
        let model = AppModel()
        model.startRecording()
        let url = try XCTUnwrap(model.stopRecording())
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(model.lastRecordingExport, url)
        model.startRecording()
        XCTAssertNil(model.lastRecordingExport, "a new recording replaces it")
        if let next = model.stopRecording() { try? FileManager.default.removeItem(at: next) }
    }

    /// The calm view's sip line uses the hydration card's words.
    func test_theSipWords_areTheCards() {
        XCTAssertEqual(HydrationCard.countLabel(0), "No sips yet")
        XCTAssertEqual(HydrationCard.countLabel(1), "1 sip today")
        XCTAssertEqual(HydrationCard.countLabel(4), "4 sips today")
        let t = now.timeIntervalSince1970
        XCTAssertEqual(HydrationCard.lastSipLabel(nil, now: now), "No recent sip")
        XCTAssertEqual(HydrationCard.lastSipLabel(t - 20, now: now), "Just now")
        XCTAssertEqual(HydrationCard.lastSipLabel(t - 12 * 60, now: now), "Last sip 12 min ago")
        XCTAssertEqual(HydrationCard.lastSipLabel(t - 2 * 3600, now: now), "Last sip 2h ago")
    }

    // MARK: - The top line

    func test_theTopLine_saysLive_whileFramesArrive() {
        XCTAssertEqual(CalmStatus(glance: glance(.good), thermalLevel: .nominal), .live)
        XCTAssertEqual(CalmStatus(glance: glance(.absent), thermalLevel: .fair), .live)
        XCTAssertEqual(CalmStatus.live.label, "Live")
    }

    /// With a shoulder hidden the posture is held, not judged: the top line says the camera
    /// can't see you, rather than "Live" over a posture that has stopped changing.
    func test_theTopLine_saysSo_whenTheCameraCantSeeYouClearly() {
        XCTAssertEqual(CalmStatus(glance: glance(.good), thermalLevel: .nominal, tracking: .degraded), .unclear)
        XCTAssertEqual(CalmStatus(glance: glance(.drifting(since: 0), since: now), thermalLevel: .serious,
                                  tracking: .degraded), .unclear, "before the heat warning")
        XCTAssertEqual(CalmStatus.unclear.label, "Can't see you clearly")
        XCTAssertTrue(CalmStatus.unclear.holdsPosture)
        XCTAssertFalse(CalmStatus.live.holdsPosture)
    }

    /// Away is the camera seeing nobody, which is what it should say: not a weak signal.
    func test_away_withTrackingLost_isStillLive() {
        XCTAssertEqual(CalmStatus(glance: glance(.absent), thermalLevel: .nominal, tracking: .lost), .live)
    }

    /// Before the first frame the camera is starting, not paused.
    func test_beforeTheFirstFrame_theCameraIsStarting() {
        let look = CalmLook(glance: .paused, thermalLevel: .nominal, cameraStarted: false)
        XCTAssertEqual(look, .startingCamera)
        XCTAssertNil(look.band)
        XCTAssertEqual(look.headline, "Starting camera")
        XCTAssertEqual(CalmStatus(glance: .paused, thermalLevel: .nominal, cameraStarted: false), .starting)
        XCTAssertEqual(CalmStatus.starting.label, "Starting")
        XCTAssertEqual(CalmLook(glance: .paused, thermalLevel: .nominal, cameraStarted: true), .cameraPaused)
    }

    /// Calibration waits for a clear view, which the calibration screen doesn't say.
    func test_whileCalibrating_theTopLine_saysWhatItsWaitingFor() {
        XCTAssertEqual(CalmStatus.calibrating(tracking: .good), .calibrating)
        XCTAssertEqual(CalmStatus.calibrating(tracking: .degraded), .waitingForClearView)
        XCTAssertEqual(CalmStatus.calibrating(tracking: .lost), .waitingForClearView)
        XCTAssertEqual(CalmStatus.calibrating.label, "Calibrating")
        XCTAssertEqual(CalmStatus.waitingForClearView.label, "Waiting for a clear view")
    }

    func test_theTopLine_warns_whenThePhoneIsWarm() {
        XCTAssertEqual(CalmStatus(glance: glance(.good), thermalLevel: .serious), .warm)
        XCTAssertEqual(CalmStatus.warm.label, "Warm · less accurate")
    }

    func test_theTopLine_saysPaused_withNoFrames() {
        XCTAssertEqual(CalmStatus(glance: .paused, thermalLevel: .nominal), .paused)
        XCTAssertEqual(CalmStatus(glance: .paused, thermalLevel: .critical), .coolingDown)
    }

    /// Brightness says how much it matters: sitting well is the dimmest the column gets, and a
    /// slouch is brighter the longer it goes on.
    func test_theColumn_isQuietest_whileSittingWell() {
        let good = PostureColumn.intensity(of: .good)
        let slouching = PostureColumn.intensity(of: .drifting)
        let still = PostureColumn.intensity(of: .bad)
        XCTAssertLessThan(good, 0.6)
        XCTAssertLessThan(good, slouching)
        XCTAssertLessThanOrEqual(slouching, still)
    }

    /// The column takes what the rest leaves: everything fits on an iPhone SE at the usual text
    /// size, and it stops growing on the biggest phones.
    func test_theColumn_fitsTheSE_andStopsGrowing() {
        let se = CalmLayout.columnHeight(available: 603)        // 667 less the status bar and top line
        let pro = CalmLayout.columnHeight(available: 734)       // iPhone 17 Pro
        let proMax = CalmLayout.columnHeight(available: 816)    // iPhone 17 Pro Max
        XCTAssertLessThanOrEqual(se + CalmLayout.portraitFixedHeight, 603)
        XCTAssertGreaterThan(pro, se)
        XCTAssertEqual(proMax, CalmLayout.columnHeight(available: 2000), "stops growing")
        XCTAssertGreaterThanOrEqual(CalmLayout.columnHeight(available: 300), 100, "never vanishes")
    }

    // MARK: - Today

    /// The time slouched, under the day's strip: minutes, then hours and minutes.
    func test_theSlouchedTime_readsInMinutes_thenHours() {
        XCTAssertEqual(CalmLayout.duration(0), "0 min")
        XCTAssertEqual(CalmLayout.duration(29), "0 min")
        XCTAssertEqual(CalmLayout.duration(7 * 60 + 20), "7 min")
        XCTAssertEqual(CalmLayout.duration(59 * 60 + 40), "1 h 0 min")
        XCTAssertEqual(CalmLayout.duration(65 * 60), "1 h 5 min")
    }

    /// The share of the judged time sat well, or a dash with none judged.
    func test_theShareSatWell_isAWholePercent() {
        XCTAssertEqual(CalmLayout.percent(0.876), "88%")
        XCTAssertEqual(CalmLayout.percent(1), "100%")
        XCTAssertEqual(CalmLayout.percent(nil), "–")
    }

    // MARK: - Burn-in

    /// The view shifts a little each minute so hours of the same pixels don't burn in.
    func test_theShift_staysWithinThreePoints_andMovesEachMinute() {
        var previous: CGSize?
        for minute in 0..<40 {
            let shift = CalmLayout.burnInShift(minute: minute)
            XCTAssertLessThanOrEqual((shift.width * shift.width + shift.height * shift.height).squareRoot(),
                                     3.0001, "minute \(minute)")
            if let previous { XCTAssertNotEqual(shift, previous, "minute \(minute)") }
            previous = shift
        }
    }

    /// Each minute's move is to the next point round the circle, so it's too small to notice.
    func test_eachMinutesShift_isShort() {
        for minute in 0..<16 {
            let a = CalmLayout.burnInShift(minute: minute), b = CalmLayout.burnInShift(minute: minute + 1)
            let step = ((a.width - b.width) * (a.width - b.width) + (a.height - b.height) * (a.height - b.height))
                .squareRoot()
            XCTAssertLessThanOrEqual(step, 2.4, "minute \(minute)")
        }
    }

    func test_theShift_coversBothAxes() {
        let shifts = (0..<CalmLayout.burnInSteps).map { CalmLayout.burnInShift(minute: $0) }
        XCTAssertGreaterThan(shifts.map(\.width).max() ?? 0, 1)
        XCTAssertLessThan(shifts.map(\.width).min() ?? 0, -1)
        XCTAssertGreaterThan(shifts.map(\.height).max() ?? 0, 1)
        XCTAssertLessThan(shifts.map(\.height).min() ?? 0, -1)
    }

    /// A negative minute (a clock set back) still lands on the cycle.
    func test_theShift_handlesANegativeMinute() {
        XCTAssertEqual(CalmLayout.burnInShift(minute: -1),
                       CalmLayout.burnInShift(minute: CalmLayout.burnInSteps - 1))
    }
}
