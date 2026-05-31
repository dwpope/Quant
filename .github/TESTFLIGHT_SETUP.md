# TestFlight auto-upload — setup

The `TestFlight` workflow (`.github/workflows/testflight.yml`) builds the iOS
app and uploads it to App Store Connect / TestFlight on every push to `main`
(and on manual "Run workflow"). It needs **three repository secrets** and a
runner with **Xcode 26.5**. Until the secrets exist the job runs green but
skips the build, so this file being present won't spam you with red failures.

## 1. Create an App Store Connect API key

1. App Store Connect → **Users and Access** → **Integrations** → **App Store
   Connect API** (Team Keys).
2. **Generate API Key**. Give it the **App Manager** role (needed so Xcode can
   create/download cloud-managed signing during the build, and upload).
3. Note the **Key ID** and the **Issuer ID** (shown above the key list).
4. **Download the `.p8`** — you can only download it once. Keep it safe.

## 2. Add the three repository secrets

GitHub repo → **Settings → Secrets and variables → Actions → New repository
secret**:

| Secret name | Value |
|---|---|
| `ASC_KEY_ID` | the Key ID (e.g. `ABC123XYZ9`) |
| `ASC_ISSUER_ID` | the Issuer ID (a UUID) |
| `ASC_KEY_P8` | **base64 of the `.p8` file** (see below) |

Base64-encode the key and copy it to the clipboard:

```bash
base64 -i AuthKey_ABC123XYZ9.p8 | pbcopy
```

Paste that as the value of `ASC_KEY_P8`. (The workflow decodes it back to a
`.p8` at build time and deletes it afterward.)

## 3. Runner / Xcode

The workflow uses `runs-on: macos-26` and selects `/Applications/Xcode_26.5.app`
to match this project (Xcode 26.5). If your available runner image names Xcode
differently — or you don't have a macos-26 image — replace the **Select Xcode**
step with:

```yaml
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '26.5'
```

## How it works

- **Build number** is set to the git **commit count** (`git rev-list --count
  HEAD`) — currently ~222, always increasing, so uploads never collide. This
  overrides the `CURRENT_PROJECT_VERSION` in the project at archive time. The
  marketing version (`1.0`) is unchanged; bump that in Xcode when you want a
  new user-facing version.
- **Signing** is cloud-managed automatic signing via the API key
  (`-allowProvisioningUpdates`), so no certificates or provisioning profiles
  need to be stored in the repo.
- **Upload** happens via `xcodebuild -exportArchive` with
  `destination = upload` in `ExportOptions.plist` — one step, no `altool`.

## First run & caveats

- This pipeline was scaffolded but **not run end-to-end** from the authoring
  environment — CI code signing usually needs a tweak on the first real run
  (Xcode path, API-key role, or a one-time export-compliance answer in App
  Store Connect). Watch the first run's logs.
- After a successful upload the build still **processes** in App Store Connect
  (a few minutes up to ~an hour) before it appears in TestFlight, and you may
  need to answer export compliance and assign it to a tester group once.
- **Don't manually upload a lower build number after CI has uploaded a higher
  one** — App Store Connect requires each new build number to exceed the last.
  (Your current manual build is `3`; CI builds start at ~222, so you're fine.)

## Trigger it

Push to `main`, or **Actions → TestFlight → Run workflow** (manual dispatch).
