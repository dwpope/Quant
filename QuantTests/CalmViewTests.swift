import CoreGraphics
import simd
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

    /// Brightness says how much it matters: sitting well is the dimmest the figure gets, and a
    /// slouch is brighter the longer it goes on.
    func test_theFigure_isQuietest_whileSittingWell() {
        let good = CalmPalette.intensity(of: .good)
        let slouching = CalmPalette.intensity(of: .drifting)
        let still = CalmPalette.intensity(of: .bad)
        XCTAssertLessThan(good, 0.6)
        XCTAssertLessThan(good, slouching)
        XCTAssertLessThanOrEqual(slouching, still)
    }

    /// The figure takes what the rest leaves: everything fits on an iPhone SE at the usual text
    /// size, and it stops growing on the biggest phones.
    func test_theFigure_fitsTheSE_andStopsGrowing() {
        let se = CalmLayout.heroHeight(available: 603)        // 667 less the status bar and top line
        let pro = CalmLayout.heroHeight(available: 734)       // iPhone 17 Pro
        let proMax = CalmLayout.heroHeight(available: 816)    // iPhone 17 Pro Max
        XCTAssertLessThanOrEqual(se + CalmLayout.portraitFixedHeight, 603)
        XCTAssertGreaterThan(pro, se)
        XCTAssertEqual(proMax, CalmLayout.heroHeight(available: 2000), "stops growing")
        XCTAssertGreaterThanOrEqual(CalmLayout.heroHeight(available: 300), 100, "never vanishes")
    }

    // MARK: - The figure

    private func metrics(creep: Float = 0, headDrop: Float = 0, sink: Float = 0,
                         sideLean: Float = 0) -> RawMetrics {
        RawMetrics(timestamp: 0, forwardCreep: creep, headDrop: headDrop, shoulderRounding: 0,
                   lateralLean: abs(sideLean), twist: 0, movementLevel: 0, headMovementPattern: .still,
                   lateralLeanSigned: sideLean, shoulderSink: sink)
    }

    private let thresholds = PostureThresholds()
    private var slouching: CalmLook { .slouching(since: nil, sustained: false, nudgeAt: nil) }

    /// Sitting well, the figure stands in its calibrated outline and doesn't move: the metrics'
    /// small wanderings below the lines aren't drawn, so the screen stays still.
    func test_sittingWell_standsInTheOutline() {
        let pose = CalmFigurePose(look: .sittingWell, metrics: metrics(creep: 0.04, headDrop: -0.01, sink: 0.03),
                                  thresholds: thresholds, headTurnDegrees: 10)
        XCTAssertEqual(pose, .neutral)
    }

    /// At a line, each signal shows clearly: about two thirds of its full change.
    func test_atEachLine_theFigureShowsIt() {
        let t = thresholds
        let pose = CalmFigurePose(look: slouching,
                                  metrics: metrics(creep: t.forwardCreepThreshold, headDrop: -t.headDropThreshold,
                                                   sink: t.shoulderSinkThreshold, sideLean: t.sideLeanThreshold),
                                  thresholds: t, headTurnDegrees: nil)
        for (name, value) in [("lean", pose.lean), ("drop", pose.drop), ("sink", pose.sink), ("tilt", pose.tilt)] {
            XCTAssertEqual(value, 0.65, accuracy: 0.001, name)
        }
        XCTAssertEqual(pose.turn, 0)
    }

    /// Far past a line it stops growing: the figure never turns grotesque.
    func test_farPastALine_theFigureStopsGrowing() {
        let pose = CalmFigurePose(look: slouching, metrics: metrics(creep: 0.5, headDrop: -0.3, sink: 0.4),
                                  thresholds: thresholds, headTurnDegrees: nil)
        XCTAssertEqual(pose.lean, 1)
        XCTAssertEqual(pose.drop, 1)
        XCTAssertEqual(pose.sink, 1)
    }

    /// Leaning back draws smaller, measured against the recline line.
    func test_leaningBack_drawsSmaller() {
        let pose = CalmFigurePose(look: slouching, metrics: metrics(creep: thresholds.reclineMaxForwardCreep),
                                  thresholds: thresholds, headTurnDegrees: nil)
        XCTAssertEqual(pose.lean, -0.65, accuracy: 0.001)
    }

    /// As in a mirror: a lean to your right, and a head turned to your right, show on the right.
    func test_sideways_readsAsInAMirror() {
        let right = CalmFigurePose(look: slouching, metrics: metrics(sideLean: 0.08),
                                   thresholds: thresholds, headTurnDegrees: nil)
        let left = CalmFigurePose(look: slouching, metrics: metrics(sideLean: -0.08),
                                  thresholds: thresholds, headTurnDegrees: nil)
        XCTAssertGreaterThan(right.tilt, 0)
        XCTAssertLessThan(left.tilt, 0)
        let turned = CalmFigurePose(look: .headTurned(since: now, nudgeAt: nil), metrics: metrics(),
                                    thresholds: thresholds, headTurnDegrees: 45)
        XCTAssertEqual(turned.turn, 0.65, accuracy: 0.001)
        XCTAssertEqual(CalmFigurePose(look: .headTurned(since: now, nudgeAt: nil), metrics: metrics(),
                                      thresholds: thresholds, headTurnDegrees: -45).turn, -0.65, accuracy: 0.001)
    }

    /// A head turn while sitting well turns only the head.
    func test_aHeadTurn_turnsOnlyTheHead() {
        let pose = CalmFigurePose(look: .headTurned(since: now, nudgeAt: nil),
                                  metrics: metrics(creep: 0.2, headDrop: -0.1),
                                  thresholds: thresholds, headTurnDegrees: 45)
        XCTAssertEqual(pose.lean, 0)
        XCTAssertEqual(pose.drop, 0)
        XCTAssertNotEqual(pose.turn, 0)
    }

    /// With no posture to show, the outline stands empty.
    func test_withNoPosture_theOutlineStandsEmpty() {
        for look in [CalmLook.away, .cameraPaused, .startingCamera, .coolingDown, .calibrating] {
            XCTAssertEqual(CalmFigurePose(look: look, metrics: metrics(creep: 0.2), thresholds: thresholds,
                                          headTurnDegrees: 40), .neutral, "\(look)")
        }
    }

    /// In steps of 0.05, so a frame's jitter doesn't redraw the screen ten times a second.
    func test_thePose_movesInSteps() {
        let a = CalmFigurePose(look: slouching, metrics: metrics(creep: 0.0601), thresholds: thresholds,
                               headTurnDegrees: nil)
        let b = CalmFigurePose(look: slouching, metrics: metrics(creep: 0.0606), thresholds: thresholds,
                               headTurnDegrees: nil)
        XCTAssertEqual(a, b)
        XCTAssertEqual((a.lean * 20).rounded(), a.lean * 20)
    }

    /// The outline's neck is your own, as calibration measured it, within reason.
    func test_theOutline_hasYourNeck() {
        XCTAssertEqual(CalmFigurePose.neckLength(baselineNeckHeight: -0.3), 1, accuracy: 0.001)
        XCTAssertEqual(CalmFigurePose.neckLength(baselineNeckHeight: -0.36), 1.2, accuracy: 0.001)
        XCTAssertEqual(CalmFigurePose.neckLength(baselineNeckHeight: nil), 1)
        XCTAssertEqual(CalmFigurePose.neckLength(baselineNeckHeight: -2), CalmFigurePose.neckLength(baselineNeckHeight: -0.5))
        XCTAssertEqual(CalmFigurePose.neckLength(baselineNeckHeight: 0), CalmFigurePose.neckLength(baselineNeckHeight: -0.15))
    }

    // MARK: - Your model

    /// Sitting well, your model stands as you made it.
    func test_theModel_atRest_isAsMade() {
        let m = CalmModelPose(.neutral)
        XCTAssertEqual(m.torso.angle, 0, accuracy: 1e-6)
        XCTAssertEqual(m.head.angle, 0, accuracy: 1e-6)
        XCTAssertEqual(m.scale, 1)
        XCTAssertEqual(m.headLowered, 0)
        XCTAssertEqual(m.sunk, 0)
    }

    /// The model's own frame is Z-up, its front at −Y: a nod and leaning in are about +X, a side
    /// lean about +Y, a turn about +Z (checked in renders, 2026-10-22).
    func test_eachPart_movesTheModelItsOwnWay() {
        var pose = CalmFigurePose()
        pose.drop = 1
        let dropped = CalmModelPose(pose)
        XCTAssertGreaterThan(dropped.head.angle, 0)
        XCTAssertEqual(dropped.head.axis.x, 1, accuracy: 1e-5, "a nod")
        XCTAssertGreaterThan(dropped.headLowered, 0, "into the shoulders")

        pose = CalmFigurePose(); pose.lean = 1
        let leaning = CalmModelPose(pose)
        XCTAssertEqual(leaning.torso.axis.x, 1, accuracy: 1e-5)
        XCTAssertGreaterThan(leaning.torso.angle, 0, "towards the camera")
        XCTAssertGreaterThan(leaning.scale, 1)
        XCTAssertLessThan(leaning.torso.act(SIMD3<Float>(0, 0, 1)).y, 0, "top tipped to the front, −Y")

        pose = CalmFigurePose(); pose.lean = -1
        let back = CalmModelPose(pose)
        XCTAssertLessThan(back.scale, 1)
        XCTAssertGreaterThan(back.torso.act(SIMD3<Float>(0, 0, 1)).y, 0, "top tipped back, away from the camera")

        pose = CalmFigurePose(); pose.tilt = 1
        XCTAssertGreaterThan(CalmModelPose(pose).torso.act(SIMD3<Float>(0, 0, 1)).x, 0, "top to the right")
        pose.tilt = -1
        XCTAssertLessThan(CalmModelPose(pose).torso.act(SIMD3<Float>(0, 0, 1)).x, 0)

        pose = CalmFigurePose(); pose.turn = 1
        XCTAssertGreaterThan(CalmModelPose(pose).head.act(SIMD3<Float>(0, -1, 0)).x, 0, "face to the right")

        pose = CalmFigurePose(); pose.sink = 1
        XCTAssertGreaterThan(CalmModelPose(pose).sunk, 0)
    }

    /// The model renders offscreen, on its own: your figure in the middle, nothing round it.
    func test_theModel_renders() async throws {
        let renderer = try await XCTUnwrapAsync(await CalmModelRenderer.make())
        let image = try await XCTUnwrapAsync(await renderer.render(.neutral, colour: .green))
        let pixels = try AlphaMap(image)
        XCTAssertGreaterThan(pixels.alpha(x: 0.5, y: 0.6), 0.9, "the figure")
        XCTAssertEqual(pixels.alpha(x: 0.02, y: 0.02), 0, "nothing round it")
    }

    /// A head drop lowers the top of the figure; leaning in widens it.
    func test_theRenderedModel_movesAsYouDo() async throws {
        let renderer = try await XCTUnwrapAsync(await CalmModelRenderer.make())
        let rest = try AlphaMap(try await XCTUnwrapAsync(await renderer.render(.neutral, colour: .green)))
        var pose = CalmFigurePose(); pose.drop = 1
        let dropped = try AlphaMap(try await XCTUnwrapAsync(await renderer.render(pose, colour: .green)))
        XCTAssertGreaterThan(dropped.topRow, rest.topRow + 5)
        pose = CalmFigurePose(); pose.lean = 1
        let leaning = try AlphaMap(try await XCTUnwrapAsync(await renderer.render(pose, colour: .green)))
        XCTAssertGreaterThan(leaning.width(atY: 0.7), rest.width(atY: 0.7) + 5)
    }

    /// The outline of how you sat: a ring, empty inside.
    func test_theOutline_isARing() async throws {
        let renderer = try await XCTUnwrapAsync(await CalmModelRenderer.make())
        let outline = try AlphaMap(try await XCTUnwrapAsync(await renderer.outline()))
        XCTAssertEqual(outline.alpha(x: 0.5, y: 0.7), 0, accuracy: 0.05, "empty inside")
        XCTAssertGreaterThan(outline.opaqueCount, 100, "but there")
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

/// Unwraps an optional from an async call, failing the test when it's nil.
private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}

/// A rendered image's alpha, to test where the figure is.
private struct AlphaMap {
    let width: Int, height: Int
    private let alphas: [UInt8]

    init(_ image: CGImage) throws {
        width = image.width; height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        alphas = stride(from: 3, to: data.count, by: 4).map { data[$0] }
    }

    /// 0…1, at a point given as fractions of the width and height from the top left.
    func alpha(x: Double, y: Double) -> Double {
        let col = min(width - 1, Int(x * Double(width))), row = min(height - 1, Int(y * Double(height)))
        return Double(alphas[row * width + col]) / 255
    }

    /// The first row from the top with anything drawn.
    var topRow: Int {
        (0..<height).first { row in (0..<width).contains { alphas[row * width + $0] > 128 } } ?? height
    }

    func width(atY y: Double) -> Int {
        let row = min(height - 1, Int(y * Double(height)))
        return (0..<width).filter { alphas[row * width + $0] > 128 }.count
    }

    var opaqueCount: Int { alphas.filter { $0 > 128 }.count }
}

