# How Aware ships to TestFlight

**Aware ships via Xcode Cloud, not GitHub Actions.** Push to `main` and the build
happens on Apple's infrastructure — nothing runs on your Mac.

## The pipeline

| Stage | Mechanism | Automatic |
|---|---|---|
| Push to `main` | git | ✅ |
| PostureLogic package tests | GitHub Actions (`tests.yml`, macos-15) | ✅ |
| Archive iOS app | **Xcode Cloud** workflow "TestFlight" → action `Archive - iOS` | ✅ ~5 min |
| Upload to App Store Connect | Xcode Cloud | ✅ |
| Processing | Apple | ✅ minutes–1h |
| Distribute to internal testers | Xcode Cloud **post-action** (see below) | ⚠️ see below |
| Install | TestFlight app | ✅ |

The Xcode Cloud workflow is configured **server-side in App Store Connect** and is
**not in this repo** — there is no `ci_scripts/`, no `ExportOptions.plist`, no
workflow YAML for it. To inspect or change it:

> App Store Connect → Aware → **Xcode Cloud → Manage Workflows → "TestFlight"**

Verify it ran for a given commit with:

```bash
gh api repos/dwpope/Quant/commits/<sha>/check-runs \
  --jq '.check_runs[] | "\(.app.slug) | \(.name) | \(.conclusion)"'
# xcode-cloud | Quant | TestFlight | Archive - iOS | success
```

Note `gh run list` will **not** show Xcode Cloud — it only lists GitHub's own
workflows. Xcode Cloud reports in as a check-run from a different app.

## App Store Connect identity

- App: **Aware - Desk Health** (App Apple ID `6768216991`)
- iOS bundle ID: `net.davepope.Quant`
- Watch bundle ID: `net.davepope.Quant.watchkitapp`
- Team: `FHC8TY7TG6`

## Export compliance — handled in the project

`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` is set on the Quant and watch
targets (Debug + Release). Without it every uploaded build sits in TestFlight at
**"Missing Compliance"** and can't be distributed to anyone until someone answers
the questionnaire by hand — every build, forever.

`NO` is still the truthful answer, but **the original reasoning for it expired on
2026-09-23** and is recorded here so nobody "corrects" the key on stale grounds.

It used to say the app has no `URLSession` usage and no `http(s)://` endpoint in
any Swift source. Both are now false: `URLSessionJevTransport`
(`PostureLogic/Sources/PostureLogic/Services/JevClient.swift`) uses `URLSession`,
and `Quant/AppModel.swift` contains the Jev proxy's `https://` endpoint. The app
makes real network requests when the opt-in Jev classifier is enabled.

`NO` remains correct for a different reason: the app performs **no encryption of
its own**. It calls no `CryptoKit`, `CommonCrypto` or `SecKey` API, and ships no
cryptographic implementation. Its only encryption is the TLS that `URLSession`
and `WatchConnectivity` provide, which is Apple-supplied and exempt under
category 5, part 2 — exactly what `ITSAppUsesNonExemptEncryption = NO` asserts.
Using HTTPS does not make an app's encryption non-exempt.

**Do not change this key to `YES` on the grounds that the app now uses the
network.** Doing so parks every subsequent build at "Missing Compliance" until
someone answers the questionnaire by hand, every build, forever.

If that key is ever removed, the manual workaround is
TestFlight → build row → **Manage** beside "Missing Compliance".

## ⚠️ Distributing to internal testers automatically

The group-level **"Enable automatic distribution"** checkbox does **not** apply to
Xcode Cloud builds. Apple's documentation is explicit:

> "To enable Xcode to automatically deliver builds to all group members, select the
> 'Enable automatic distribution' checkbox… **You must always manually add builds
> created by Xcode Cloud to groups in App Store Connect.**"

The only automatic path for an Xcode Cloud build is a **post-action on the
workflow**:

> App Store Connect → Aware → Xcode Cloud → Manage Workflows → "TestFlight" →
> **Post-Actions** → add **"TestFlight (Internal Testing Only)"** → select the
> internal tester group.

Post-actions emit no GitHub check-runs, so their presence can only be confirmed in
the App Store Connect UI. If builds are archiving successfully but never reaching
testers' phones, this is the first thing to check.

## ⚠️ Do not add a second uploader

A GitHub Actions TestFlight workflow previously lived at
`.github/workflows/testflight.yml` (with `.github/ExportOptions.plist`). It never
ran — the three App Store Connect secrets it guarded on were never set — and it was
**removed deliberately**, not abandoned.

Do not resurrect it alongside Xcode Cloud. Both trigger on push to `main`, and the
build numbers are incompatible:

- GitHub Actions numbered builds `git rev-list --count HEAD` (**284** and climbing)
- Xcode Cloud uses its own counter (**~22–25**)
- `MARKETING_VERSION` is `1.0` in every config and neither pipeline bumps it

App Store Connect requires each new `CFBundleVersion` for a version to exceed the
last uploaded. So the moment GitHub Actions uploads 284, every subsequent Xcode
Cloud upload is rejected — silently killing the pipeline that works.

If you ever want to migrate to GitHub Actions, disable the Xcode Cloud workflow's
start condition **first**, then add the secrets. `284 > 25`, so that direction is
safe; the reverse is not.

Recovering the deleted workflow, should you ever need it as a starting point:

```bash
git show 31fe577:.github/workflows/testflight.yml
git show 31fe577:.github/ExportOptions.plist
```

## Known gaps

- **Xcode Cloud has no test action.** Its only action is `Archive - iOS`, so the
  shipping path is ungated. The `swift test` gate lives in `tests.yml`, which does
  not block the archive. Neither pipeline runs `QuantTests`/`QuantUITests` — only
  the PostureLogic SwiftPM package. Consider adding a `Test - iOS` action.
- **`main` is not branch-protected**, so anything pushed ships with no required
  checks.
- **`MARKETING_VERSION` is pinned at `1.0`** and never bumped. Fine for TestFlight;
  once 1.0 is released to the App Store, every later 1.0 build is rejected.

## Expectations after a push

Archive ~5 min → processing (minutes, occasionally ~an hour) → appears in
TestFlight. Internal testers need no Beta App Review; up to 100 testers, each an
App Store Connect user on team `FHC8TY7TG6`; builds stay installable for 90 days.
App Privacy answers aren't required for internal testing but will gate external
testers later.
