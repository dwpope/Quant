# Phase 2: 3D Depth Fusion & Recording Pipeline (Steps 29–35)

Add depth fusion for better accuracy and recording/replay for regression testing. See `.agents/planning/2026-03-08-posture-detection/implementation/plan.md` for full context.

## Step 29: 3D Position Calculation

- Implement `unproject(point:depth:intrinsics:)` function
- Use camera intrinsics: `fx = intrinsics[0,0]`, `cx = intrinsics[2,0]`, etc.
- Formula: `x = (px - cx) * depth / fx`, `y = (py - cy) * depth / fy`, `z = depth`
- Watch for column-major ordering in `simd_float3x3`

## Step 30: Depth Fusion in PoseSample Builder

- When depth confidence >= `.medium`: use `unproject()` to convert keypoints + depth to 3D world coords
- When confidence < `.medium`: use existing 2D path (no regression)
- Compute derived angles using 3D geometry when available
- Ignore depth values within 5% of frame edges (unreliable)

## Step 31: RecorderService (Timestamped Samples)

- Create `PostureLogic/Sources/PostureLogic/Services/RecorderService.swift`
- `startRecording()` / `stopRecording()` lifecycle
- `record(sample:)` appends to in-memory array
- `stopRecording()` returns `RecordedSession` with all samples, tags, metadata
- JSON export target: <5MB for 5 minutes at 10 FPS

## Step 32: Tagging During Record

- `addTag(_ tag: Tag)` on RecorderService
- Button-based manual tagging (good posture, slouching, reading, typing, etc.)
- Tags stored with timestamp and source (manual vs automatic)

## Step 33: ReplayService (Simulator-Friendly)

- Create `PostureLogic/Sources/PostureLogic/Services/ReplayService.swift`
- `load(session:)` / `play()` / `stop()` lifecycle
- `play()` returns `AsyncStream<PoseSample>` with timing based on inter-sample timestamps
- Configurable `playbackSpeed` (1x, 2x, 10x)

## Step 34: Golden Recordings

- Record and export at least 4 sessions:
  1. `good_posture_5min.json` — sustained good posture
  2. `gradual_slouch.json` — starts good, deteriorates
  3. `reading_vs_typing.json` — alternating tasks
  4. `depth_fallback_scenario.json` — includes depth loss moments
- Store in `GoldenRecordings/` directory
- Write replay-based regression test that verifies detection

## Step 35: Recording & Replay Pipeline Integration

- Pipeline → RecorderService: forward `latestSample` when recording active
- AppModel recording controls: `startRecording()` / `stopRecording()` with JSON export
- Replay as PoseProvider: `ReplayPoseProvider` wraps ReplayService output into InputFrames
- AppModel replay controls: `loadSession(_ url:)` / `startReplay()`
- Live camera and replay must share the same Pipeline code path

## Constraints

- Existing 2D path must not regress — all current tests must pass
- Recording.swift model already exists in PostureLogic — build on it
- TaskMode enum already exists — don't duplicate it
- Follow existing project conventions and patterns

## Success Criteria

- [ ] `test_unproject_withKnownValues_producesCorrectPosition` passes
- [ ] 3D positions used when depth available, 2D fallback when not
- [ ] RecorderService records and exports sessions to JSON (<5MB for 5 min)
- [ ] Tags can be added during recording with timestamps
- [ ] ReplayService plays back sessions at configurable speed
- [ ] Golden recordings committed and replay regression test passes
- [ ] Recording/replay integrated into Pipeline and AppModel
- [ ] All existing PostureLogic tests still pass (no regressions)
