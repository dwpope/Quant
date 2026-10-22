import PostureLogic
import SwiftUI

/// The calm view (2026-10-20): the screen you glance at while you work, beside the debug one.
///
/// The phone stands below your screen, 50–80 cm away, on for hours, in the corner of your eye;
/// the Watch does the nudging. So the view answers four things at a glance and is otherwise
/// still: how you're sitting (a word, and a figure of you as the camera sees you), whether the
/// camera is watching, how long until a nudge, and how today has gone. Always dark: OLED black
/// is off, which saves power and heat, and keeps glare out of the corner of your eye. Design
/// notes in docs/superpowers/specs/2026-10-20-calm-view-design.md.
struct CalmScreen: View {
    @ObservedObject var appModel: AppModel
    let onSettings: () -> Void
    let onSwitch: () -> Void

    @StateObject private var today = PostureTimelineLoader()
    @State private var showDay = false
    @State private var showSips = false

    /// What fills the screen below the top line: the existing screens while the camera or the
    /// calibration needs you, the calm view itself otherwise. The debug screen's order.
    private enum Phase { case cameraBlocked, rearProblem, calibrating, monitoring }

    private var phase: Phase {
        if (appModel.cameraMode == .front2D && appModel.frontCameraBlocked)
            || (appModel.cameraMode == .frontFace && appModel.faceCameraBlocked) { return .cameraBlocked }
        if appModel.cameraMode == .rearDepth && appModel.rearCameraStatus != .ok { return .rearProblem }
        if appModel.needsCalibration { return .calibrating }
        return .monitoring
    }

    var body: some View {
        // Ticks each second, for the countdown's "due" and the minute's burn-in shift. The
        // glance itself is the app model's, steadied and taken each second.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let glance = appModel.calmGlance
            let look = CalmLook(glance: glance, thermalLevel: appModel.thermalLevel,
                                cameraStarted: appModel.cameraStarted)
            switch phase {
            case .monitoring:
                // Equatable, so the AppModel's ten updates a second redraw it only when what it
                // shows has changed.
                CalmScreenContent(
                    look: look,
                    pose: CalmFigurePose(look: look, metrics: appModel.latestMetrics,
                                         thresholds: appModel.postureThresholds,
                                         headTurnDegrees: headTurnDegrees),
                    neckLength: CalmFigurePose.neckLength(baselineNeckHeight: appModel.baseline?.neckHeight),
                    status: CalmStatus(glance: glance, thermalLevel: appModel.thermalLevel,
                                       tracking: appModel.trackingQuality,
                                       cameraStarted: appModel.cameraStarted),
                    silencedUntil: appModel.nudgesSilencedUntil.flatMap { $0 > context.date ? $0 : nil },
                    timeline: today.timeline,
                    sipCount: appModel.sipStore.sipCount,
                    lastSipTimestamp: appModel.sipStore.lastSipTimestamp,
                    showsCamera: appModel.showCameraPreview,
                    recording: appModel.isRecording,
                    now: context.date,
                    actions: actions,
                    mirror: { cameraPreview })
                    .equatable()
                    // Here, not round every phase: in debug it waits until calibration is done.
                    .sipLabelSheet(appModel: appModel)
            case .cameraBlocked:
                CalmFrame(status: .paused, onSwitch: onSwitch, onSettings: onSettings) {
                    CameraPermissionView { Task { await appModel.retryFrontCamera() } }
                }
            case .rearProblem:
                CalmFrame(status: .paused, onSwitch: onSwitch, onSettings: onSettings) {
                    RearCameraProblemView(status: appModel.rearCameraStatus) {
                        Task { await appModel.retryRearCamera() }
                    }
                }
            case .calibrating:
                // The camera's view above the calibration screen, whatever the Camera control
                // says: "Position yourself in frame" is when you need to see the frame.
                CalmFrame(status: .calibrating(tracking: appModel.trackingQuality),
                          onSwitch: onSwitch, onSettings: onSettings) {
                    VStack(spacing: 0) {
                        CalmMirror(cornerRadius: 24) { cameraPreview }
                            .aspectRatio(3 / 4, contentMode: .fit)
                            .frame(maxHeight: 220)
                            .padding(.top, 12)
                        CalibrationView(appModel: appModel)
                    }
                }
            }
        }
        // The system's dark status bar text would be black on black in light mode, and a
        // screen like StandBy has none.
        .statusBarHidden(true)
        .task { await today.keepLoadingToday() }
        .sheet(isPresented: $showDay) { PostureTimelineView() }
        .sheet(isPresented: $showSips) {
            SipTimelineView(appModel: appModel, sipStore: appModel.sipStore)
        }
    }

    /// The head's yaw from where it was at calibration, + towards your right.
    private var headTurnDegrees: Float? {
        appModel.latestSample.map { $0.headYaw - (appModel.baseline?.headYaw ?? 0) }
    }

    private var actions: CalmActions {
        CalmActions(
            silence: { appModel.silenceNudges(forMinutes: $0) },
            resume: { appModel.resumeNudges() },
            recalibrate: { appModel.recalibrate() },
            toggleCamera: { appModel.showCameraPreview.toggle() },
            settings: onSettings,
            showDay: { showDay = true },
            showSips: { showSips = true },
            switchView: onSwitch)
    }

    @ViewBuilder
    private var cameraPreview: some View {
        switch appModel.cameraMode {
        case .rearDepth: CameraPreviewView(session: appModel.arService.session)
        case .front2D: FrontCameraPreviewView(session: appModel.frontService.captureSession)
        case .frontFace: CameraPreviewView(session: appModel.arFaceService.session)
        }
    }
}

/// What the calm view's controls do.
struct CalmActions {
    var silence: (_ minutes: Int) -> Void = { _ in }
    var resume: () -> Void = {}
    var recalibrate: () -> Void = {}
    var toggleCamera: () -> Void = {}
    var settings: () -> Void = {}
    var showDay: () -> Void = {}
    var showSips: () -> Void = {}
    var switchView: () -> Void = {}
}

// MARK: - The frame

/// The calm view's dark ground and top line round the screens it borrows (calibration, the
/// camera's problems), with Settings below, where those screens say it is.
struct CalmFrame<Content: View>: View {
    let status: CalmStatus
    let onSwitch: () -> Void
    let onSettings: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            CalmTopBar(status: status, onSwitch: onSwitch)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(action: onSettings) {
                CalmControlLabel(title: "Settings", symbol: "gearshape", isOn: false)
                    .frame(width: 96)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
}

/// Whether the camera is watching, on the left; the way back to debug, on the right. The
/// switch is in the same corner as the debug screen's.
struct CalmTopBar: View {
    let status: CalmStatus
    var recording = false
    let onSwitch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                Text(status.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Camera: \(status.label)")

            // A recording for Jev runs on whichever screen shows; this says it's still going.
            if recording {
                Text("REC")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().strokeBorder(.red.opacity(0.7), lineWidth: 1))
                    .accessibilityLabel("Recording")
            }

            Spacer(minLength: 8)

            Button(action: onSwitch) {
                Label("Debug", systemImage: "ladybug")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.white.opacity(0.08)))
                    // A 44 pt target round the smaller capsule.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MainScreenStyle.calm.switchLabel)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.top, 2)
    }
}

extension CalmStatus {
    var color: Color {
        switch self {
        case .live: return Color(PosturePalette.good)
        case .warm, .coolingDown, .unclear, .waitingForClearView: return .orange
        case .paused, .starting: return .gray
        case .calibrating: return .blue
        }
    }
}

/// The camera's view, framed: in the figure's place when the Camera control is on, and above
/// the calibration screen.
struct CalmMirror<Preview: View>: View {
    var cornerRadius: CGFloat = 30
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        preview()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .accessibilityElement()
            .accessibilityLabel("Camera view")
    }
}

// MARK: - The content

/// The calm view itself, from plain values, so it can be drawn without a camera.
struct CalmScreenContent<Mirror: View>: View {
    let look: CalmLook
    var pose: CalmFigurePose = .neutral
    var neckLength: Double = 1
    let status: CalmStatus
    let silencedUntil: Date?
    let timeline: PostureTimeline?
    let sipCount: Int
    let lastSipTimestamp: TimeInterval?
    let showsCamera: Bool
    var recording = false
    let now: Date
    let actions: CalmActions
    @ViewBuilder let mirror: () -> Mirror

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                Group {
                    if verticalSizeClass == .compact {
                        landscape(height: geo.size.height)
                    } else {
                        portrait(height: geo.size.height)
                    }
                }
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            CalmTopBar(status: status, recording: recording, onSwitch: actions.switchView)
                .padding(.horizontal, 20)
        }
        // Eased over two seconds, a point round the circle: too slow and small to catch the eye.
        .animation(reduceMotion ? nil : .easeInOut(duration: 2)) {
            $0.offset(CalmLayout.burnInShift(minute: Int((now.timeIntervalSince1970 / 60).rounded(.down))))
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private func portrait(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            hero(height: CalmLayout.heroHeight(available: height))
            Spacer(minLength: 20)
            VStack(spacing: 10) {
                todayCard
                sipRow
            }
            CalmControls(silencedUntil: silencedUntil, showsCamera: showsCamera, actions: actions)
                .padding(.top, 16)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
    }

    private func landscape(height: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 32) {
            hero(height: min(220, max(120, height * 0.5)))
                .frame(maxWidth: .infinity)
            VStack(spacing: 10) {
                todayCard
                sipRow
                CalmControls(silencedUntil: silencedUntil, showsCamera: showsCamera, actions: actions)
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func hero(height: CGFloat) -> some View {
        CalmHero(look: look, pose: pose, neckLength: neckLength, silencedUntil: silencedUntil,
                 showsCamera: showsCamera, holdsPosture: status.holdsPosture, height: height, now: now,
                 mirror: mirror)
            // From outside, so the hero's scaled sizes are read under the cap.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // MARK: Today

    private var todayCard: some View {
        Button(action: actions.showDay) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Today")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                todayBody
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.07)))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today")
        .accessibilityValue(timeline?.summary ?? "Nothing yet")
        .accessibilityHint("Shows the whole day")
    }

    @ViewBuilder
    private var todayBody: some View {
        if let timeline, !timeline.segments.isEmpty {
            // Dimmed as the figure is, so the slouches stand out on a quiet green.
            PostureTimelineChart(timeline: timeline, brightness: CalmPalette.intensity(of:))
                .frame(height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            todayStats(timeline)
        } else {
            Text("Your posture today will show here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Three across, or one under another when they don't fit (the largest text sizes).
    private func todayStats(_ timeline: PostureTimeline) -> some View {
        let nudges = timeline.nudges.count
        let stats = Group {
            stat(CalmLayout.percent(timeline.goodShare), "sat well")
            stat(CalmLayout.duration(timeline.slouched), "slouched")
            stat("\(nudges)", nudges == 1 ? "nudge" : "nudges")
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) { stats }
            VStack(alignment: .leading, spacing: 10) { stats }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sipCountText: some View {
        Text(HydrationCard.countLabel(sipCount))
            .font(.subheadline.weight(.medium))
    }

    private var lastSipText: some View {
        Text(HydrationCard.lastSipLabel(lastSipTimestamp, now: now))
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var sipRow: some View {
        Button(action: actions.showSips) {
            HStack(spacing: 12) {
                Image(systemName: "drop.fill")
                    .foregroundStyle(.blue)
                // Side by side, or the time under the count when they don't fit.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        sipCountText.fixedSize()
                        Spacer(minLength: 8)
                        lastSipText.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        sipCountText
                        lastSipText
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.07)))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows today's sips")
    }
}

/// Redrawn only when what it shows changes; what the controls do and the camera's view are
/// left out, as they're the same each time.
extension CalmScreenContent: Equatable {
    static func == (a: Self, b: Self) -> Bool {
        a.look == b.look && a.pose == b.pose && a.neckLength == b.neckLength && a.status == b.status && a.silencedUntil == b.silencedUntil
            && a.timeline == b.timeline && a.sipCount == b.sipCount
            && a.lastSipTimestamp == b.lastSipTimestamp && a.showsCamera == b.showsCamera
            && a.recording == b.recording && a.now == b.now
    }
}

// MARK: - The hero

/// The figure (or the camera's view) and the word under it, with what's being counted.
struct CalmHero<Mirror: View>: View {
    let look: CalmLook
    let pose: CalmFigurePose
    let neckLength: Double
    let silencedUntil: Date?
    let showsCamera: Bool
    /// The camera can't see you clearly: the posture shown is the last one judged.
    let holdsPosture: Bool
    let height: CGFloat
    let now: Date
    @ViewBuilder let mirror: () -> Mirror

    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 44
    /// Room for the two lines under the word, kept whether they show or not, so the figure and
    /// the word don't jump each time a slouch starts or ends.
    @ScaledMetric(relativeTo: .title3) private var detailsHeight: CGFloat = 60

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if showsCamera {
                    CalmMirror(preview: mirror)
                        .frame(width: height * 0.75, height: height)
                        .transition(.opacity)
                } else {
                    CalmModelFigure(band: look.band, pose: pose, neckLength: neckLength,
                                    symbol: look.figureSymbol)
                        .frame(width: height * 0.82, height: height)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showsCamera)

            VStack(spacing: 8) {
                Text(look.headline)
                    .font(.system(size: headlineSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: look.headline)
                VStack(spacing: 4) { details }
                    .frame(minHeight: detailsHeight, alignment: .top)
            }
            .accessibilityElement(children: .combine)
        }
        // Held, not judged: faded, so it doesn't read as now.
        .opacity(holdsPosture ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.6), value: holdsPosture)
    }

    /// What's being counted, and what's coming: shown only while there's something to say, so
    /// the screen is still while you sit well.
    @ViewBuilder
    private var details: some View {
        let detailFont = Font.system(.title3, design: .rounded)
        if holdsPosture {
            // Nothing is counted, and no nudge fires, without a clear view.
            note("Held until the camera sees you clearly")
        } else {
            if let since = look.since {
                Text("for \(Text(since, style: .timer))")
                    .font(detailFont)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            switch look.countdown(now: now) {
            case .until(let nudgeAt):
                Text("nudge in \(Text(timerInterval: now...nudgeAt, countsDown: true))")
                    .font(detailFont.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(look.attentionColor)
            case .due:
                Text("nudge due")
                    .font(detailFont.weight(.medium))
                    .foregroundStyle(look.attentionColor)
            case nil:
                if let silencedUntil, look.isPosture {
                    Label("Nudges silenced until \(silencedUntil.formatted(date: .omitted, time: .shortened))",
                          systemImage: "bell.slash.fill")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.secondary)
                } else if let text = look.note {
                    note(text)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(.callout, design: .rounded))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

// MARK: - The figure

/// You, as the phone sees you: head, neck and shoulders from the front, standing in a faint
/// outline of how you sat at calibration. Sitting well, you fill the outline; slouching, you
/// leave it, the way you moved: bigger leaning in, a shorter neck with the head dropped, lower
/// sunk in the chair, tilted leaning sideways. Morphs between poses, slowly.
///
/// Brightness says how much it matters (`CalmPalette`): a dim green sitting well, the quietest
/// the screen gets, and a bright yellow, then red, with a glow, while slouching.
struct PostureFigure: View {
    let band: PostureTimeline.Band?
    let pose: CalmFigurePose
    /// The outline's neck, from calibration (`CalmFigurePose.neckLength`).
    var neckLength: Double = 1
    var symbol: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Away there's no one to draw: the outline stands empty.
            if let band, band != .away {
                let colour = band.color.opacity(CalmPalette.intensity(of: band))
                let slouched = band == .drifting || band == .bad
                // On black first, so the dimmed fill doesn't show the outline through it.
                FigureShape(pose: pose, neckLength: neckLength)
                    .fill(.black)
                    .overlay(FigureShape(pose: pose, neckLength: neckLength)
                        .fill(LinearGradient(colors: [colour, colour.opacity(0.75)],
                                             startPoint: .top, endPoint: .bottom)))
                    .shadow(color: slouched ? band.color.opacity(0.4) : .clear, radius: 30)
                if pose.turn != 0 {
                    FigureFaceLine(pose: pose, neckLength: neckLength)
                        .stroke(.black.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            // How you sat at calibration: the line to come back to.
            FigureShape(pose: .neutral, neckLength: neckLength)
                .stroke(.white.opacity(band == nil || band == .away ? 0.28 : 0.22),
                        style: StrokeStyle(lineWidth: 1.5, dash: band == nil || band == .away ? [5, 5] : []))
            if let symbol {
                GeometryReader { geo in
                    Image(systemName: symbol)
                        .font(.system(size: geo.size.width * 0.16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.8)
                }
            }
        }
        // Cut flat along the bottom, like a bust, so sinking goes down out of the frame rather
        // than onto the words below; open above and to the sides for leaning in and the glow.
        .mask(Rectangle().padding(.top, -400).padding(.horizontal, -400))
        .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: pose)
        .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: band)
        .accessibilityHidden(true)
    }
}

/// Where the figure's parts sit in its box, posed. Shared by the outline and the face's line.
private struct FigureGeometry {
    let head: CGRect
    let neck: CGRect
    let torso: CGRect
    /// Sink, lean (scale) and tilt, about the bottom centre: the chair.
    let transform: CGAffineTransform

    init(rect: CGRect, pose: CalmFigurePose, neckLength: Double) {
        let w = rect.width, h = rect.height
        let shoulderY = rect.minY + h * 0.6
        // Runs on below the frame, which cuts it, so a tilt or a sink never shows its end.
        torso = CGRect(x: rect.midX - w * 0.44, y: shoulderY, width: w * 0.88, height: h * 0.8)
        // The ears' height above the shoulders: yours from calibration, shorter with the head
        // dropped, until it sinks into the shoulders.
        let earLift = w * 0.3 * neckLength * (1 - 0.5 * pose.drop)
        let headW = w * 0.38 * (1 - 0.12 * abs(pose.turn)), headH = w * 0.46
        let headCentre = CGPoint(x: rect.midX + w * 0.04 * pose.turn, y: shoulderY - earLift)
        head = CGRect(x: headCentre.x - headW / 2, y: headCentre.y - headH / 2, width: headW, height: headH)
        let neckW = w * 0.2
        neck = CGRect(x: rect.midX - neckW / 2, y: headCentre.y, width: neckW,
                      height: max(0, shoulderY + h * 0.04 - headCentre.y))

        // Bigger leaning in, about the bottom edge; tilted about the hips, below the frame, so
        // the shoulders swing and the cut edge stays flat; lower when sunk.
        let scale = pose.lean >= 0 ? 1 + 0.18 * pose.lean : 1 + 0.14 * pose.lean
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)
        let hips = CGPoint(x: rect.midX, y: rect.maxY + h * 0.35)
        let lean = CGAffineTransform(translationX: bottom.x, y: bottom.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bottom.x, y: -bottom.y)
        let tilt = CGAffineTransform(translationX: hips.x, y: hips.y)
            .rotated(by: pose.tilt * 9 * .pi / 180)
            .translatedBy(x: -hips.x, y: -hips.y)
        transform = lean.concatenating(tilt)
            .concatenating(CGAffineTransform(translationX: 0, y: h * 0.16 * pose.sink))
    }
}

/// Head, neck and shoulders as one outline, posed.
struct FigureShape: Shape {
    var pose: CalmFigurePose
    var neckLength: Double

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>,
                                       AnimatablePair<AnimatablePair<Double, Double>, Double>> {
        get { .init(.init(pose.lean, pose.drop), .init(.init(pose.sink, pose.tilt), pose.turn)) }
        set {
            pose.lean = newValue.first.first
            pose.drop = newValue.first.second
            pose.sink = newValue.second.first.first
            pose.tilt = newValue.second.first.second
            pose.turn = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let g = FigureGeometry(rect: rect, pose: pose, neckLength: neckLength)
        let shoulders = UnevenRoundedRectangle(topLeadingRadius: rect.width * 0.3,
                                               topTrailingRadius: rect.width * 0.3,
                                               style: .continuous).path(in: g.torso)
        let neck = RoundedRectangle(cornerRadius: g.neck.width * 0.3, style: .continuous).path(in: g.neck)
        return shoulders.union(neck).union(Path(ellipseIn: g.head)).applying(g.transform)
    }
}

/// The line down the middle of the face, which shows which way a turned head faces.
struct FigureFaceLine: Shape {
    var pose: CalmFigurePose
    var neckLength: Double

    var animatableData: Double {
        get { pose.turn }
        set { pose.turn = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let head = FigureGeometry(rect: rect, pose: pose, neckLength: neckLength)
        let h = head.head
        let x = h.midX + h.width * 0.36 * pose.turn
        var path = Path()
        path.move(to: CGPoint(x: h.midX + h.width * 0.12 * pose.turn, y: h.minY + h.height * 0.32))
        path.addQuadCurve(to: CGPoint(x: h.midX + h.width * 0.12 * pose.turn, y: h.maxY - h.height * 0.12),
                          control: CGPoint(x: x + h.width * 0.1 * pose.turn, y: h.midY + h.height * 0.1))
        return path.applying(head.transform)
    }
}

extension CalmLook {
    /// Drawn in the empty outline when there's no posture to show.
    var figureSymbol: String? {
        switch self {
        case .away: return "person.slash"
        case .calibrating: return "scope"
        case .cameraPaused: return "video.slash"
        case .startingCamera: return "camera"
        case .coolingDown: return "thermometer.medium"
        case .sittingWell, .slouching, .headTurned: return nil
        }
    }

    /// A line under the word when there's no timer to show.
    var note: String? {
        switch self {
        case .away: return "Not in the camera's view"
        case .cameraPaused: return "No frames from the camera"
        case .coolingDown: return "Detection resumes when the phone cools"
        case .sittingWell, .slouching, .headTurned, .calibrating, .startingCamera: return nil
        }
    }

    /// Sitting, slouching or with the head turned: a posture nudges are counted from.
    var isPosture: Bool {
        switch self {
        case .sittingWell, .slouching, .headTurned: return true
        case .away, .calibrating, .cameraPaused, .startingCamera, .coolingDown: return false
        }
    }

    /// The countdown's colour: still slouching is red, anything else coming is yellow.
    var attentionColor: Color {
        if case .slouching(_, true, _) = self { return Color(PosturePalette.stillSlouching) }
        return Color(PosturePalette.slouching)
    }
}

// MARK: - Controls

/// Four labelled controls. Toggles look toggled, filled while on, as in Control Center.
struct CalmControls: View {
    let silencedUntil: Date?
    let showsCamera: Bool
    let actions: CalmActions

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Menu {
                if let silencedUntil {
                    Text("Silenced until \(silencedUntil.formatted(date: .omitted, time: .shortened))")
                    Button("Resume nudges", systemImage: "bell", action: actions.resume)
                }
                ForEach(AppModel.silenceOptionsMinutes, id: \.self) { minutes in
                    Button(Self.silenceLabel(minutes: minutes)) { actions.silence(minutes) }
                }
            } label: {
                CalmControlLabel(title: silencedUntil == nil ? "Silence" : "Silenced",
                                 symbol: silencedUntil == nil ? "bell" : "bell.slash.fill",
                                 isOn: silencedUntil != nil)
            }
            .accessibilityLabel(silencedUntil == nil ? "Silence nudges" : "Nudges silenced")

            // "Calibrate", as on the Watch: "Recalibrate" didn't fit a quarter of an SE at
            // larger text sizes.
            Button(action: actions.recalibrate) {
                CalmControlLabel(title: "Calibrate", symbol: "scope", isOn: false)
            }
            .accessibilityLabel("Recalibrate")

            Button(action: actions.toggleCamera) {
                CalmControlLabel(title: "Camera", symbol: showsCamera ? "eye.fill" : "eye", isOn: showsCamera)
            }
            .accessibilityLabel(showsCamera ? "Hide camera view" : "Show camera view")

            Button(action: actions.settings) {
                CalmControlLabel(title: "Settings", symbol: "gearshape", isOn: false)
            }
            .accessibilityLabel("Settings")
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    static func silenceLabel(minutes: Int) -> String {
        minutes < 60 ? "Silence for \(minutes) min"
            : minutes == 60 ? "Silence for 1 hour" : "Silence for \(minutes / 60) hours"
    }
}

struct CalmControlLabel: View {
    let title: String
    let symbol: String
    let isOn: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(isOn ? Color.black : Color.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(isOn ? Color.white.opacity(0.92) : Color.white.opacity(0.11)))
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityShowsLargeContentViewer {
            Label(title, systemImage: symbol)
        }
    }
}
