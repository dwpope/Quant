import PostureLogic
import SwiftUI

/// The calm view (2026-10-20): the screen you glance at while you work, beside the debug one.
///
/// The phone stands below your screen, 50–80 cm away, on for hours, in the corner of your eye;
/// the Watch does the nudging. So the view answers four things at a glance and is otherwise
/// still: how you're sitting (a word, and a column as tall as you sit), whether the camera is
/// watching, how long until a nudge, and how today has gone. Always dark: OLED black is off,
/// which saves power and heat, and keeps glare out of the corner of your eye. Design notes in
/// docs/superpowers/specs/2026-10-20-calm-view-design.md.
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
            switch phase {
            case .monitoring:
                // Equatable, so the AppModel's ten updates a second redraw it only when what it
                // shows has changed.
                CalmScreenContent(
                    look: CalmLook(glance: glance, thermalLevel: appModel.thermalLevel,
                                   cameraStarted: appModel.cameraStarted),
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

/// The camera's view, framed: in the column's place when the Camera control is on, and above
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
            hero(columnHeight: CalmLayout.columnHeight(available: height))
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
            hero(columnHeight: min(220, max(120, height * 0.5)))
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

    private func hero(columnHeight: CGFloat) -> some View {
        CalmHero(look: look, silencedUntil: silencedUntil, showsCamera: showsCamera,
                 holdsPosture: status.holdsPosture, columnHeight: columnHeight, now: now,
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
            // Dimmed as the column is, so the slouches stand out on a quiet green.
            PostureTimelineChart(timeline: timeline, brightness: PostureColumn.intensity(of:))
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
        a.look == b.look && a.status == b.status && a.silencedUntil == b.silencedUntil
            && a.timeline == b.timeline && a.sipCount == b.sipCount
            && a.lastSipTimestamp == b.lastSipTimestamp && a.showsCamera == b.showsCamera
            && a.recording == b.recording && a.now == b.now
    }
}

// MARK: - The hero

/// The column (or the camera's view) and the word under it, with what's being counted.
struct CalmHero<Mirror: View>: View {
    let look: CalmLook
    let silencedUntil: Date?
    let showsCamera: Bool
    /// The camera can't see you clearly: the posture shown is the last one judged.
    let holdsPosture: Bool
    let columnHeight: CGFloat
    let now: Date
    @ViewBuilder let mirror: () -> Mirror

    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 44
    /// Room for the two lines under the word, kept whether they show or not, so the column and
    /// the word don't jump each time a slouch starts or ends.
    @ScaledMetric(relativeTo: .title3) private var detailsHeight: CGFloat = 60

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if showsCamera {
                    CalmMirror(preview: mirror)
                        .frame(width: columnHeight * 0.75, height: columnHeight)
                        .transition(.opacity)
                } else {
                    PostureColumn(band: look.band, symbol: look.columnSymbol)
                        .frame(width: columnHeight * 0.36, height: columnHeight)
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

// MARK: - The column

/// Your posture as a column: full when you sit well, lower while you slouch, a sliver away.
/// The timeline's band, live and large.
///
/// Brightness says how much it matters: sitting well is a dim green, the quietest the screen
/// gets, and a slouch lights up in yellow, then red. The eye's edge notices a change in
/// brightness before a change in colour, so a slouch is seen without looking, and sitting well
/// isn't a lit panel in the corner of your eye for hours. Eases between heights, slowly.
struct PostureColumn: View {
    let band: PostureTimeline.Band?
    var symbol: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How bright the fill is, of the band's own colour.
    static func intensity(of band: PostureTimeline.Band) -> Double {
        switch band {
        case .good: return 0.45
        case .drifting: return 0.95
        case .bad: return 1
        case .away: return 0.8
        }
    }

    var body: some View {
        GeometryReader { geo in
            // A capsule as tall as the band: a pill standing, a round one sunk, a flat one away.
            let fillHeight = band.map { geo.size.height * CGFloat($0.height) } ?? 0
            ZStack(alignment: .bottom) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.07))
                if let band {
                    let colour = band.color.opacity(Self.intensity(of: band))
                    // On black first, so the dimmed fill doesn't show the track through it.
                    Capsule(style: .continuous)
                        .fill(.black)
                        .overlay(Capsule(style: .continuous)
                            .fill(LinearGradient(colors: [colour, colour.opacity(0.75)],
                                                 startPoint: .top, endPoint: .bottom)))
                        .frame(height: fillHeight)
                        .shadow(color: band == .drifting || band == .bad ? band.color.opacity(0.4) : .clear,
                                radius: 30)
                }
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: geo.size.width * 0.32, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxHeight: .infinity)
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: band)
        }
        .accessibilityHidden(true)
    }
}

extension CalmLook {
    /// Drawn in the empty column when there's no posture to stand at.
    var columnSymbol: String? {
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
