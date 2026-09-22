# Code status

**As of 2026-09-22 · `63aa23e` on `main`, plus the uncommitted test fixes noted below.**

A verified snapshot of where the codebase stands: what passes, what is known broken,
and what is environment rather than code. Every figure here was reproduced on this
machine on the date given, with the command shown, so it can be re-checked rather
than trusted.

## Build & test

| Suite | Command | Result |
|---|---|---|
| `PostureLogic` package | `cd PostureLogic && swift test` | **571 / 571 pass** (2026-09-22) |
| App + app tests | `xcodebuild test -project Quant.xcodeproj -scheme QuantNoWatchTests -destination 'platform=iOS Simulator,name=iPhone 17'` | **396 / 396 pass**, `** TEST SUCCEEDED **` (2026-09-22) |
| App launch | `xcrun simctl install` + `launch` on iPhone 17 | launches, renders, survives a live dark-mode reload (2026-09-21) |

Take counts from the result bundle, not stdout:
`xcrun xcresulttool get test-results summary --path <…>.xcresult`. xcodebuild's
concurrent stdout writes interleave and mangle occasional `Test case '…'` lines —
grepping stdout undercounted this suite by one.

## Changed in this pass (2026-09-22)

- **Removed** `.github/workflows/testflight.yml` and `.github/ExportOptions.plist`
  from disk. `a7195e8` (2026-09-09) dropped them from the index but left the blobs
  behind as untracked files, so any `git add -A` would have silently re-committed a
  pipeline that was deliberately retired. `.github/` now matches `origin/main`.
  `TESTFLIGHT_SETUP.md:19` already asserted their absence and records the
  `git show 31fe577:` recovery path, so docs and tree now agree.
- **`63aa23e`** — tracked `Quant.xcodeproj/xcshareddata/xcodecloud/manifest.json`
  (maps the Xcode Cloud product to the `Quant` target; shared project data, not
  per-machine state) and committed the two redundant `BlueprintName` attributes
  Xcode dropped from the watch scheme.
- **Fixed the two red tests** in `QuantTests/PostureVisualizationBindingTests.swift`.
  Both were stale assertions, not product bugs. **Currently uncommitted.**

### Why those two tests were stale

1. `test_debugChannels_defaultsMatchProduction` asserted `hideGhost == false`. The
   shipped default is `true` — a 2026-06-14 product decision, since the
   calibration-baseline clone obstructs the read with the stylized USDZ figure. The
   doc comment on `PostureVisualizationBinding.debug` made it worse by instructing
   "reset every flag to its default before shipping (all `true`, `hideShoulderDisc`
   false)", which is wrong twice over: `hideHeadBand` is also false, and following it
   literally would have reintroduced the ghost *with the stale test agreeing*. Both
   corrected, and the comment now points at the test that pins the defaults.
2. `test_resolveFromViewModel_endToEnd` seeded `lateralLean` / `twist` — the unsigned,
   scoring-only fields. `PostureVisualizationViewModel.ingest` reads
   `lateralLeanSigned` / `twistSigned` (the viz needs the sense, not the magnitude),
   and those are **defaulted `= 0` parameters** on `RawMetrics.init`. The old fixture
   therefore compiled cleanly and fed the visualization zeros, so the test asserted
   0.3° of disc yaw against an actual 0.0. Fixture now seeds the signed channels.

   *Watch for this pattern.* Widening an initializer with defaulted parameters keeps
   every call site compiling, so the compiler produces no migration list — other
   fixtures built with `RawMetrics(…)` before the signed split may be equally inert
   without failing.

## Open issues

Ranked by what would reach a user first.

### 1. The developer HUD ships in Release builds
`Quant/ContentView.swift` contains no `#if DEBUG` anywhere (0 occurrences across 246
lines) and `DebugOverlayView` has neither a compile gate nor a runtime toggle — it is
rendered unconditionally in `body`. A TestFlight or App Store build shows camera
mode, FPS, pose confidence, sip thresholds and the raw metric table over the main
screen, plus a haptic-type picker and a "Test Nudge" button. Only the four
`Views/Visualization/*` files use `#if DEBUG`.

### 2. The bottom debug control row overflows
In `ContentView.swift` the bottom `HStack` holds a menu `Picker` + two text buttons +
five icon buttons. The inflexible `Image` buttons win the layout negotiation and the
text controls compress to roughly one character wide — the haptic picker renders
`f-a-i-l-u-r-e` vertically, one letter per line, and "Test Nudge" / "Recalibrate"
collapse into unreadable pills. Visible in the launch screenshot. `.layoutPriority`,
`.fixedSize()`, or a second row would each fix it.

### 3. Swift 6 language mode is a wall, not a slope
`SWIFT_VERSION = 5.0`. A **full** build emits 77 warnings, of which **44** say
"this is an error in the Swift 6 language mode" — concentrated in
`QuantTests/SwitchablePoseProviderTests.swift` (12, main-actor isolation),
`AppModel.swift` (4, non-Sendable `Timer` capture in `@Sendable` closures), and
several `@MainActor`-isolated `Equatable` conformances used from nonisolated test
contexts. Incremental builds do not recompile unchanged files and so report only a
handful; use a clean build before judging progress.

### 4. CI app-target coverage — added and green 2026-09-22
Until today `.github/workflows/tests.yml` was the only workflow, path-filtered to
`PostureLogic/**`, so CI ran `swift test` on the package and nothing else: commits
touching only app code triggered no runs at all, and a green badge said nothing
about the app. `app-tests.yml` now runs the full `QuantNoWatchTests` suite on a
simulator, filtered on `Quant/**`, `QuantTests/**`, `Quant.xcodeproj/**` and
`PostureLogic/**`.

**Green.** `396 passed, 0 failed, 0 skipped, of 396` on `macos-26` in 9m11s — the
same count as local. Three runs were needed, each of which taught something worth
keeping:

1. `macos-15` failed in 2m10s at compile — see *Toolchain floor* below. Moved to
   `macos-26` (Xcode 26.6, Swift 6.3.3).
2. `macos-26` built everything (app, watch app, test bundle) and then **sat silent
   for 43m46s with zero test output** before its own timeout cancelled it. Last build
   line `Touch …/Quant.app` at 11:39:25, cancellation at 12:23:11, and not one
   `Test Suite` or `Test case` line between: the harness never started, so it was a
   destination problem rather than a slow or hanging test.
3. Booting the device explicitly fixed it.

The workflow now boots the simulator itself rather than letting `xcodebuild` do it
implicitly:

```bash
xcrun simctl boot "$udid" || true     # already-booted is not an error
xcrun simctl bootstatus "$udid" -b    # wait for a terminal boot state
```

On the green run that boot took about 2.5 minutes from `(Shutdown)` to `(Booted)` —
long enough that whatever `xcodebuild` does implicitly was evidently not waiting for
it correctly. The same commit also passed `-parallel-testing-enabled NO`, and the
green run created **no clones** (locally xcodebuild runs on "Clone 1 of iPhone 17").
Both changes shipped together, so which one was strictly necessary is not
established — only that the pair works.

Also worth keeping: the artifact step was `if: failure()`, and a job cancelled by its
own timeout is **not** a failure, so the result bundle went unsaved from exactly the
run that most needed it. It is `if: always()` now. Per-step timeouts (10m boot, 25m
test) mean a future hang names the step it hung in.

The Metal guard's download branch has still never been exercised: the `macos-26`
image already carries the toolchain (`MetalToolchain-v17.6.109.0`), so the step takes
the "present" path. The `sudo` fallback is untested.

## Toolchain floor: Xcode 26 / Swift 6.2

Ten classes declare `nonisolated deinit` — `AppModel`, `ARSessionService`,
`ARFaceTrackingService`, `FrontCameraSessionService`, `WatchConnectivityService`,
`LivePostureDataSource`, `PostureVisualizationViewModel`, `SipStore`,
`SipLabelQueue`, `SipTrainingStore`. It is a deliberate workaround, documented at
each site: teardown touches no main-actor state, and marking it `nonisolated` keeps
Swift's MainActor isolated-deinit back-deploy shim out of XCTest's
NSInvocation-driven dealloc path, which otherwise corrupts the heap and aborts under
Xcode 26 / iOS 26.

That syntax is part of SE-0371 and needs **Swift 6.2**. On Xcode 16.4 the build stops
immediately:

```
LivePostureDataSource.swift:11:5: error: 'isolated' deinit requires frontend flag
  -enable-experimental-feature IsolatedDeinit to enable the usage of this feature
```

`IPHONEOS_DEPLOYMENT_TARGET = 18.0` is therefore misleading as a proxy for the build
toolchain: the constraint is a *language feature*, not an SDK or an API, so grepping
for `#available(iOS 19+)` will not find it. The README said "Xcode 16+" until
2026-09-22; corrected.

## Environment hazards

- **Stray `Icon\r` files break the build.** On 2026-09-21 a 0-byte macOS
  custom-folder-icon file (`Icon` + carriage return) appeared in every directory —
  2,957 of them. The `Quant` target uses Xcode 16 **synced folders**, so every file
  on disk becomes a resource; the duplicates all resolved to `Quant.app/Icon` and
  the build failed with `error: Multiple commands produce '…/Quant.app/Icon'`
  before any test ran. One had also landed in `.git/refs/heads/`, producing
  `warning: ignoring ref with broken name refs/heads/Icon?`. All removed; none were
  ever tracked, so `origin/main` and CI were unaffected. **`.gitignore` still has no
  rule for them**, so they will reappear as status noise if it happens again.
- **ARKit does not exist in the simulator.** `session.run()` fails with
  `Unsupported configuration` / `ARError 100`. The simulator can verify the app
  shell, layout, persistence, audio and watch plumbing, but the posture pipeline can
  only be exercised on a device or through `MockPostureDataSource`. This is the
  structural reason the detection logic lives in the platform-free `PostureLogic`
  package.
- **Xcode 27.0 has no `Simulator.app` on this machine** — not under
  `Contents/Developer/Applications` (that directory does not exist), nor in
  `/Applications` or `/System/Applications`. Devices still boot, install, launch and
  screenshot headlessly through `xcrun simctl`, but the GUI window may not be
  openable from the CLI. There is also no tap automation available (`idb` is not
  installed), so UI interaction needs an XCUITest target.
- **SourceKit diagnostics are unreliable in this repo** — in-editor "missing
  module/type" errors are routinely false. `xcodebuild` is authoritative.
