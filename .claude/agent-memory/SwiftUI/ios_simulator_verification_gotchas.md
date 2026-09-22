# iOS Simulator manual end-to-end verification gotchas

Found doing Task 6 (composition root) manual verification in
`~/Developer/Remember the moment` (2026-07-15), a SwiftUI/AppCore app whose
task briefs script `xcrun simctl` commands by device NAME. Generally
applicable to any repo doing scripted simulator verification.

## 1. Duplicate simulator names across runtimes
`xcrun simctl list devices` creates one "iPhone 17" (or any model) PER
installed iOS runtime — e.g. iOS 26.0, 26.1, 26.2, 26.4, 26.5 each get their
own "iPhone 17" with a different UDID, all sharing the identical display
name. Name-based commands (`simctl boot "iPhone 17"`, `simctl install
"iPhone 17" ...`, `simctl launch "iPhone 17" ...`) do NOT error on this
ambiguity — they silently resolve to one (observed: it picked the newest/
default-paired runtime, which happened to match the SDK the build used).
Don't assume a task brief's literal `"iPhone 17"` commands are hitting the
device you think — after boot, cross-check with
`xcrun simctl list devices booted` to confirm which UDID/runtime actually
came up, especially if deploymentTarget in project.yml differs from the
newest installed runtime.

## 2. `find DerivedData -name 'X.app' | head -1` is not "the build I just did"
Multiple `RememberTheMoment-<hash>/` DerivedData folders can coexist from
different Xcode/CLI sessions over time. `find | head -1` sorts by path
(alphabetical hash prefix), NOT recency — it can select a stale build from
days/weeks earlier and you'll be testing old code while believing you
tested the fresh commit. Always disambiguate by mtime
(`stat -f "%Sm" .../RememberTheMoment.app/RememberTheMoment`) before
installing, or `xcodebuild clean` first so only one product exists.

## 3. SpeechAnalyzer/SpeechTranscriber (iOS 26) locale resolution on Simulator
`SpeechTranscriber.supportedLocale(equivalentTo:)` was observed to never
resolve to a supported locale on iOS 26.5 Simulator for `en_GB`, even
though the host Mac's own AppleLocale/keyboard was already en_GB (ruling out
a language-mismatch cause). Symptom in `xcrun simctl spawn <device> log show
--predicate 'process == "<AppName>"'`: every retry logs only
`SFSpeechAssetManager supportedLanguagesForTaskHint:completion:` ("Fetching
languages of supported Assistant assets") via a quick XPC round-trip to
`com.apple.speech.localspeechrecognition`, then nothing further — no
`AssetInventory` install progress, no transcription result, ever. The
retries keep firing on a clean, undelayed interval (e.g. matching your own
poll/scan loop's timer) — that clean cadence is itself diagnostic: if the
code were blocked awaiting `AssetInventory.assetInstallationRequest(...)
.downloadAndInstall()`, a loop that `await`s each cycle before repeating
would stall after the FIRST attempt, not keep cycling forever. A clean
repeating cadence means each call fails FAST (immediately throws / returns
nil), not that a download is hanging.
- Treat this as a known Apple Simulator platform limitation for on-device
  Speech assets, not a bug in your composition/wiring code. Verifying the
  full transcription leg needs a physical device (or a Simulator/device
  where the locale asset was already provisioned in a prior run — some
  spike notes in this repo mention "installed-asset behavior only" was ever
  observed, i.e. nobody has confirmed a true cold first-run download actually
  completing on Simulator).
- Useful confirmation technique: check that the RELEVANT ring-buffer/window
  guard before the transcribe call is passing each cycle (i.e. real audio is
  reaching that point) to isolate "mic capture works, only on-device STT
  resolution fails" from "nothing is being captured at all".

## 4. No tap/UI-automation in this sandbox — `osascript`/System Events times out
Found doing Task 7 (Shelf UI) manual design-review screenshots in the same
repo (2026-07-15). There is no way to synthesize a tap on Simulator content
from this CLI environment: `osascript -e 'tell application "System Events"
to tell process "Simulator" to get {position, size} of window 1'` (the
standard first step before clicking a screen coordinate) hangs and fails with
`AppleEvent timed out (-1712)` — both run inline and backgrounded, and even
after `tell application "Simulator" to activate` first. No `idb`,
`idb_companion`, or `cliclick` binary is installed as a fallback tap
mechanism either. This points to no real interactive WindowServer/GUI session
being available for UI-scripting automation in this sandbox, not a transient
timing issue — don't retry it expecting a different result.
- **Workaround for design-review screenshots of a view that's normally only
  reachable via a tap** (e.g. a `NavigationLink` push): temporarily edit the
  `App`'s root (e.g. swap `WindowGroup { ContentView() }` for
  `WindowGroup { NavigationStack { TargetView() } }`) to render the real view
  directly, build, install, screenshot, then revert the edit byte-for-byte
  (confirm with `git diff` showing zero changes) before staging/committing
  anything. Same spirit as seeding a fixture JSON file into the app
  container: real code, real render, fully reverted scaffolding — never
  committed.
- `xcrun simctl io <udid> screenshot <path>` itself works fine (it just grabs
  the device framebuffer, no WindowServer/AX interaction needed) — only
  *synthesizing input* is the blocked half.

## 5. No PIL/ImageMagick/ffmpeg preinstalled — for pixel-level screenshot analysis
Found doing Task 8 (erosion capture UI) in the same repo (2026-07-15), needing
to measure exact bar heights/alpha in a Canvas-drawn waveform to distinguish "is
this dim because of low alpha" vs "is this dim because the bar is genuinely
short" (the Read tool's rendered preview isn't enough for pixel-exact claims).
`sips` is preinstalled but its `--cropOffset`/`-c` (cropToHeightWidth) combo is
confusing (crops appear centered by default; offset math didn't behave as
documented and repeatedly produced blank output) — don't burn time on it.
`convert`/`magick`/`ffmpeg` are NOT installed either. Fastest reliable path:
`python3 -m venv /tmp/imgvenv && /tmp/imgvenv/bin/pip install --quiet pillow`
(system `pip3 install pillow` fails with PEP 668 "externally managed
environment" — use a venv, don't pass `--break-system-packages`), then a short
inline Python script with `PIL.Image.crop()` + `.load()` pixel access to scan
exact rows/columns. This is also how to verify "did the audio-reactive height
actually change" vs "does it just look different due to alpha" in any future
Canvas/erosion-style rendering: scan a column for the y-range where pixel value
< 255 (not < 250 — a faint-but-tall bar can sit at ~245-254 and get missed by a
too-strict threshold).

## 6. CaptureCoordinator.UIState.kept has an associated value — `case .kept:` still works
`AppCore/Sources/AppCore/Coordinator/CaptureCoordinator.swift`'s `UIState` enum
is `case kept(momentID: String)`, not a bare `case kept`. A `switch` arm written
as `case .kept:` (no binding) still compiles and matches correctly — Swift lets
you ignore an enum case's associated value in a switch pattern. Don't assume a
brief's verbatim `case .kept:` code is a typo/mismatch against the real enum
just because the source declares an associated value.

## 7. ErosionView's alpha (erosion) and height (amplitude) are independent channels
`App/Views/CaptureView.swift`'s `ErosionView` (Task 8): per-bar **alpha** is a
pure function of array position (`pos = i/(n-1)`) plus a deterministic
index-based jitter — it has nothing to do with the actual audio `level` for
that bucket. Per-bar **height** is `max(2, level * size.height * 0.9)`. In
practice (verified via the pixel-scan technique in note 5, at both 25% and
100% Mac output volume during a `say`-into-mic Simulator test), height stays
pinned near the 2pt floor — RMS of normal/loud speech rarely exceeds ~0.1-0.2 of
full scale — so the ONLY visibly-reactive signal in a screenshot is the alpha
fade (which reads clearly as "old edge dissolving"), not bar height ("soft
waveform" silhouette is nearly flat in this test method). This is not a bug in
`EnvelopeReducer`/`PhoneMicSource` (both are correct, unit-tested Float→Int16→
RMS pipelines) — plausibly it's inherent to real speech RMS scale, possibly
compounded by the speaker-to-mic acoustic round-trip this test method requires.
Don't assume flat-looking bars in a Simulator screenshot mean broken audio
capture; check alpha vs. height as separate channels before concluding
anything is wrong, and flag amplitude-legibility as a real-device follow-up
rather than silently patching the height formula against a verbatim brief.

## 8. Chaining scaffolded auto-actions to drive a multi-screen flow (no taps at all)
Found doing Task 9 (Caught + Review, pending→saved UI) in the same repo
(2026-07-15): when a flow spans several tap-gated screens (list row tap →
sheet opens → button tap → sheet dismisses → list refreshes → repeat), one
`onAppear` scaffold isn't enough — chain a small temp `Task.sleep` timer at
**each** tap point so the same code path a real tap would take fires on its
own: (a) list view's refresh function temporarily also sets its
"open detail" `@State` to the first item after a delay; (b) the detail
sheet's temporary `.onAppear` calls the **exact same methods the real
action buttons call** (not a synthetic tap event — literally invoke
`env.someService.save(id)` / `.forget(id)`, then the same `finish()`/`dismiss()`
helper the button uses) after its own delay. Because the list's refresh gets
re-invoked via the real `onDone`/dismiss callback chain, this self-chains:
open → act → dismiss → refresh → open next → ... until the data source is
empty, at which point the empty state renders on its own with no further
scaffolding needed. This is a strictly stronger verification than calling
the service layer directly in a script, because it also proves the actual
SwiftUI wiring (the sheet's `item:` binding, the `onDone` closure, the
dismiss-then-refresh sequencing) round-trips correctly, not just that the
underlying service method works (which unit tests already cover).
Timing is fragile against real tool round-trip latency — a screenshot taken
"immediately after launch" can easily land several seconds late and already
show the *next* screen in the chain (observed: a 2s open-delay + a 3s
act-delay meant a screenshot fired ~15s post-launch showed the sheet already
closed). Fix by generously over-provisioning delays (6–8s per step) and,
if you need a screenshot of a specific intermediate state, re-running the
whole seed→build→install→launch cycle with fresh distinctly-named seed data
each time rather than trying to hit one exact timing window — cheap on this
kind of app (a few seconds per rebuild) and removes the race entirely. Revert
proof for this pattern: extract each brief-mandated file's fenced code block
into a temp file (e.g. via a small Python regex over the `.md` brief, not by
eye) and `diff` it against the working-tree file — this is exactly what
Task 8 did too via `awk`, just generalized to multiple files at once.

## 9. `grep` is `ugrep` in this shell (no `./` prefix) + verify SF Symbol names against the local catalog, not by eye
Found doing Task 12 (visual router/glasses toggle) in `~/Developer/Remember the moment`
(2026-07-15). Two small but easy-to-misjudge findings:
- `grep` on this machine resolves to `ugrep` (`grep --version` shows
  `ugrep 7.5.0 ...`), which — unlike GNU grep — does NOT prefix matches with
  `./` when searching `.` (e.g. `grep -rln "pattern" .` prints
  `GlassesKit/Sources/...` not `./GlassesKit/Sources/...`). A task brief that
  hardcodes expected grep output with a `./` prefix will look "wrong" even
  when the actual file set is an exact match — diff the file *set*, not the
  literal string, before flagging a discrepancy.
- A device log line like `[Invalid Configuration] No symbol named 'camera.slash'
  found in system symbol set` is real, verifiable evidence a brief's verbatim
  `Image(systemName:)` string doesn't exist — don't dismiss it as Simulator
  noise. Confirm independently via the local catalog:
  `plutil -p "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources/name_availability.plist" | grep -oE '"camera[a-zA-Z._]*"' | sort -u`
  — zero matches for `camera.slash` confirmed it doesn't exist (nearest real
  names: `camera.macro.slash[.circle[.fill]]`). When a brief is "verbatim,
  implement exactly as written" AND contains a demonstrably-invalid symbol
  name, implement it as specified (don't silently correct requirements) but
  flag the verified defect explicitly in the report/concerns section.
- Best-effort phone-camera-path check on a Mac with no camera passthrough
  configured for the Simulator: the `AVCaptureSession` genuinely reaches
  `.running` (visible in `xcrun simctl spawn <UDID> log show --predicate
  'process == "AppName"' | grep -i cameracapture`: `startRunning` →
  `DidStartRunningNotification`, ~9s apart — camera bring-up on Simulator is
  slow, budget ≥12s after enabling the visual path before triggering a keep),
  but the `AVCaptureVideoDataOutput` delegate never fires (no frames), so a
  keep resolves audio-only. This is a legitimate, reportable "camera
  unavailable on this sim" outcome, not a bug in the app's graceful-fidelity
  fallback — don't chase it further; inspect the on-disk moment-store JSON
  (`xcrun simctl get_app_container <UDID> <bundle-id> data`) for a
  photo/clip field to confirm either way rather than guessing from logs alone.
