# jev-proxy

A Cloudflare Worker that holds the TypeSafe Jev API key so the Aware app never does.

The app POSTs posture features; the Worker adds `Authorization: Bearer $TYPESAFE_KEY` and
forwards to `https://api.typesafe.ai/v1/systemone`. The key exists only in the Worker's
environment — never in the app bundle, never in `strings`, never in this repo.

That matters because the alternative was tried and failed. Reading the key from a gitignored
xcconfig required a delivery channel into the app, and the chosen channel
(`INFOPLIST_KEY_JevBearerToken`) turned out to be silently discarded by Xcode — while the
verification script for it, which grepped `xcodebuild -showBuildSettings` rather than the built
plist, reported 11/11 green over a dead pipe. Removing the key from the app entirely makes the
guarantee structural: there is no channel to get wrong.

## Finish the setup

Two commands, both yours to run — I cannot authenticate on your behalf.

```bash
cd jev-proxy
npx wrangler login                  # opens a browser
npx wrangler secret put TYPESAFE_KEY   # paste the key from console.typesafe.ai; it is not echoed
npx wrangler deploy
```

For local development, create `.dev.vars` with one line and run `npm run dev`:

```
TYPESAFE_KEY=<the key>
```

`.dev.vars` is gitignored — it is this project's equivalent of the old `Secrets.xcconfig`, and the
one file here that must never be committed. There is deliberately no `.dev.vars.example`: the
root `.gitignore` denies `.dev.vars*` as a class, and re-admitting a template would need a
negation rule. Every negation is a way back in, and one line of documentation is cheaper.

Then point the app's `useJevClassifier` client at the deployed URL (step 3b in
`~/Documents/Claude/jev-integration-plan.md`).

## The endpoint

`POST /classify` — everything else is 404, and anything but POST is 405.

```jsonc
// request
{
  "head_yaw_degrees": 3.2,
  "head_pitch_degrees": -8.1,
  "head_roll_degrees": 1.0,
  "forward_creep_fraction_of_baseline_shoulder_width": 0.12,
  "head_drop_in_shoulder_widths": 0.04,
  "torso_lean_delta_degrees": 6.0,
  "lateral_lean_in_shoulder_widths": 0.08,
  "shoulder_tilt_signed_degrees": 12.0,
  "torso_angle_degrees": 4.0,
  "tracking_quality": "good"      // good | degraded | lost
}

// 200
{
  "posture": "chair_swivel",      // good_posture | slouch | lean | chair_swivel | ambiguous
  "confidence": 0.81,
  "probabilities": { "chair_swivel": 0.81, "lean": 0.12, "...": 0.07 },
  "model": "jev-1.13.0"
}
```

Status codes: `400` invalid payload · `405` wrong method · `413` body over 8 KB · `429`/`529`
passed through from upstream so the client backs off · `502` upstream failed or returned
something unmappable · `503` the Worker has no key configured.

## Deliberate properties

- **Fail closed.** No key means `503` and **no upstream call** — never a request with empty
  credentials.
- **The key is never echoed.** Upstream error bodies and thrown network errors are not passed
  through, because either can quote the request that produced them, and the request carries the
  key. Tested explicitly: no response in any failure path contains the key.
- **No payload logging.** Posture features are personal data; only status codes and the upstream
  request id are logged.
- **Bounded input.** Unknown keys are dropped rather than forwarded and bodies over 8 KB are
  rejected, because this endpoint is unauthenticated and its URL is extractable from the app
  binary.
- **The rubric lives here**, in `src/classify.ts`, not in the app. That is the point: the
  `criteria` prose can be revised and re-measured without rebuilding and reinstalling. The
  `chair_swivel` description is the load-bearing one — it is the case the threshold engine is
  known to get wrong (`PostureVisualizationDevNotes.swift:37`).
- **The baseline frame of reference is stated in the payload.** Every metric is a delta from a
  calibration snapshot in units that mean nothing alone, so a prose rubric would have nothing to
  bind to without it.

## Open items

- **The Worker is unauthenticated, and its URL now ships.** As of 2026-09-24 the Jev path is no
  longer `#if DEBUG`, so `https://jev-proxy.quantaware.workers.dev/classify` is present in every
  TestFlight binary and recoverable with `strings`. This bullet previously said "will be
  extractable" and deferred rate limiting until "unexplained traffic appears" — that ordering was
  written while the URL was Debug-only and no longer holds. **Add Cloudflare rate limiting now.**
  The cost of abuse is still small (input $0.042/MTok, output free, and the Worker can be deleted
  instantly), but the endpoint is now discoverable by anyone with a build.
- **Latency.** Jev is 130 ms p50 near-provider and 475 ms p50 / 715 ms p99 from Europe via a
  gateway; this adds one edge hop. Do **not** classify per frame — interval or state change only.
- **Privacy — the README was corrected on 2026-09-24.** This bullet used to say Aware's README
  "line 5" still claimed fully on-device processing (it was line 6 — two badge lines had shifted
  it). `README.md` now states that all detection, scoring and nudging run on-device while naming
  this experiment as an opt-in exception, and carries a **Privacy and network** section describing
  exactly what is sent: nine derived numbers plus tracking quality and camera mode, **no
  imagery**. The remaining obligation is Apple-side: App Privacy answers in App Store Connect
  gate external TestFlight testers, and "Data Not Collected" stops being true the moment a tester
  enables the toggle.

## Development

```bash
npm install     # needs --cache <dir> if the shared npm cache is unwritable
npm test        # typechecks, then runs 24 unit tests
npm run check   # bundles without deploying
```

Pure logic lives in `src/classify.ts` with no Worker APIs, so it is unit-testable directly;
`src/index.ts` is a thin shell over it.
