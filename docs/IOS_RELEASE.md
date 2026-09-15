# iOS Release Pipeline (GitHub Actions + fastlane + Vault)

Builds, signs, and ships the native **Fishers** iOS app from `ios/` — same
pattern as [KubePilot](https://github.com/bwalia/kubepilot).

| Stage | How | When |
|-------|-----|------|
| **PR / push CI** | `.github/workflows/ios.yml` | Simulator build + unit tests |
| **TestFlight (auto)** | Push to `main` that touches `ios/**` | Everyday QA after merge |
| **TestFlight (tag)** | Push `v*.*.*` (auto-tag or manual) | Formal version cuts |
| **TestFlight (manual)** | `workflow_dispatch` → **testflight** | Ad-hoc builds |
| **App Store review** | `workflow_dispatch` → **app_store** | After TestFlight sign-off |

Release CI runs on the self-hosted Mac Studio runner (`runs-on: self-hosted`).
Signing material is loaded at build time from **GitHub Actions secrets** (if set)
or from **WSLVault** at `https://vault.workstation.co.uk` path **`kv/fishers/ios`**,
then wiped after each run. Fishers does **not** use `vault.diytaxreturn.co.uk`.

## Flow

```
Merge to main (ios/** changed)     or     push v1.2.3 tag     or     workflow_dispatch
                 │                                  │                         │
                 └──────────────────┬───────────────┴─────────────────────────┘
                                    ▼
                 Load ASC secrets (GitHub secrets or Vault)
                                    │
                                    ▼
              Resolve version (tag → input → ios/project.yml MARKETING_VERSION)
              Build number = latest TestFlight build for version + 1
                                    │
                                    ▼
              fastlane prepare_signing  → persistent keychain + App Store profile
              fastlane build_ipa        → archive + export Fishers.ipa
                                    │
                    ┌───────────────┴────────────────┐
                    ▼                                ▼
            testflight (auto/manual/tag)      app_store (dispatch only)
            upload_to_testflight              upload + deliver(submit_for_review)
            (internal only)
```

Auto-tag (`.github/workflows/auto-tag.yml`) bumps `vMAJOR.MINOR.PATCH` on every
`main` push (skip with `[skip tag]`). Tag pushes with the default
`GITHUB_TOKEN` do **not** re-trigger workflows — add repo secret `RELEASE_PAT`
(contents: write) if you want tags to also fire iOS Release. Day-to-day
TestFlight does **not** need that: merges that touch `ios/` upload directly.

Skip an auto TestFlight with `[skip release]` or `[skip ios]` in the commit
message.

## One-time setup

### 1. App Store Connect — where the ASC values come from

You need an **App Store Connect API key**. Apple shows the key id and issuer id
once; the private key (`.p8`) is downloadable **only once**.

1. Create the app **Fishers** with bundle id `com.fishers.app` (if it does not exist yet).
2. Open [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
   (Account Holder or Admin).
3. Under **Team Keys**, click **Generate API Key** (or **+**):
   - Name: e.g. `Fishers CI`
   - Access: **App Manager** (enough for TestFlight + signing via fastlane)
4. After create, copy:
   - **Key ID** → this is `ASC_KEY_ID` (looks like `AB12CD34EF`)
   - **Issuer ID** at the top of the API keys page → this is `ASC_ISSUER_ID` (UUID)
5. Click **Download API Key** → saves `AuthKey_<KeyID>.p8`. Store it safely; Apple will not show it again.
6. Base64 the `.p8` for CI (one line, no wraps):

   ```bash
   # macOS
   base64 -i AuthKey_AB12CD34EF.p8 | tr -d '\n'
   # Linux
   base64 -w0 AuthKey_AB12CD34EF.p8
   ```

   That string is `ASC_PRIVATE_KEY_B64`.

7. **Apple Team ID** (`APPLE_TEAM_ID`) — 10 characters from
   [developer.apple.com/account](https://developer.apple.com/account) → Membership details,
   or Xcode → Settings → Accounts → your team.
8. **App Store Connect app id** (`APP_STORE_APP_ID`, optional) — numeric id in the
   browser URL when you open the Fishers app in App Store Connect
   (`…/apps/1234567890/…`).

| Secret | Where you get it |
|--------|------------------|
| `ASC_KEY_ID` | API key **Key ID** on the Integrations → App Store Connect API page |
| `ASC_ISSUER_ID` | **Issuer ID** at the top of that same page |
| `ASC_PRIVATE_KEY_B64` | `base64` of the downloaded `AuthKey_*.p8` |
| `APPLE_TEAM_ID` | Apple Developer membership / Xcode team |
| `APP_STORE_APP_ID` | Optional; ASC app URL numeric id |

Never commit the `.p8` or base64 string to git.

### 2. Signing secrets (Vault or GitHub Actions)

Store the values from §1 under these names (same in either place):

| Key | Description |
|-----|-------------|
| `ASC_KEY_ID` | API key id |
| `ASC_ISSUER_ID` | Issuer id |
| `ASC_PRIVATE_KEY_B64` | base64 of `AuthKey_*.p8` |
| `APPLE_TEAM_ID` | 10-character team id |
| `CERT_PRIVATE_KEY_B64` | (optional) base64 of distribution private key `.pem` |
| `APP_STORE_APP_ID` | (optional) numeric ASC app id |

**Option A — WSLVault** (`https://vault.workstation.co.uk`, same vault as ring deploys):

```bash
export VAULT_ADDR=https://vault.workstation.co.uk
export VAULT_TOKEN=...    # or: export VAULT_TOKEN_FILE=$HOME/.secrets/wslvault/token.json
export ASC_KEY_ID=...          # Key ID from App Store Connect
export ASC_ISSUER_ID=...       # Issuer ID from App Store Connect
export ASC_P8_PATH=$HOME/AuthKey_XXXXXX.p8
export APPLE_TEAM_ID=...
./ios/ci/seed-ios-vault.sh
```

Writes **`kv/fishers/ios`** (KV v2 mount `kv`, same family as `kv/fishers/<ring>/config`).
See `ios/ci/ios.vault.env.example`.

Do **not** point iOS CI at `vault.diytaxreturn.co.uk` / `acc-vault` — those are not used.

**Option B — GitHub Actions secrets** (recommended if you are not using Vault for iOS):

1. Repo → **Settings** → **Secrets and variables** → **Actions**
2. **New repository secret** for `ASC_KEY_ID`, `ASC_ISSUER_ID`, `APPLE_TEAM_ID`
   (and optionally `ASC_PRIVATE_KEY_B64`)
3. On the **Mac Studio** runner, also place the downloaded key at
   `$HOME/AuthKey_<KEY_ID>.p8` (e.g. `$HOME/AuthKey_6KVVV27G4Q.p8`). The release
   workflow prefers that local file over a base64 secret when both exist.
4. Re-run **iOS Release** (or merge any `ios/**` change to `main`)

The workflow prefers GitHub secrets for IDs; the `.p8` comes from `$HOME` on the
runner when present, otherwise from `ASC_PRIVATE_KEY_B64` / Vault.

**If iOS Release fails with “Authentication credentials are missing or invalid”:**

1. Confirm all three of `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_PRIVATE_KEY_B64` were
   updated **together** from the same API key (Key ID must match `AuthKey_<KeyID>.p8`).
2. Issuer ID is the UUID at the **top** of the API keys page — not the Key ID and not
   the Team ID.
3. Re-encode the `.p8` as a single line:
   `base64 -i AuthKey_XXXXXX.p8 | tr -d '\n'`
   You may also paste the PEM itself into `ASC_PRIVATE_KEY_B64`; the loader accepts either.
4. Key access must be at least **App Manager**. Revoked keys fail the same way.
5. The workflow’s **Verify App Store Connect API key** step probes
   `GET /v1/apps` before build numbering — read that log for the precise mismatch.

**TestFlight invites** go to the external group **Fishers** (override with
`TESTFLIGHT_GROUP`). Default emails:

- `balindersinghwalia@icloud.com`
- `harchran001@gmail.com`

Override with repo variable/secret `TESTFLIGHT_TESTERS` (comma-separated). The
`beta` lane creates/updates the group, invites those emails, uploads the IPA,
and sets `notify_external_testers: true`. First-time external distribution may
need a short Beta App Review in App Store Connect (contact name/email/phone —
override phone with `TESTFLIGHT_CONTACT_PHONE` in E.164, e.g. `+447911123456`).

**Why you can see an invite but cannot install:** external email invites are accepted
in TestFlight immediately, but the build stays unavailable until Apple finishes
Beta App Review (often a few hours). Only one build per version can be in that
review at a time — later uploads stay on App Store Connect and are attached to
**Internal Testing** so App Store Connect users (Account Holder / Admin /
Developer) can install right away. Email-only testers wait for the in-review
build to be approved. Use `workflow_dispatch` target **`testflight_ready`**
(`fastlane ios ready_testers`) to re-attach the latest processed build without
rebuilding.

If someone already has a build but no invite email: App Store Connect → My Apps
→ Fishers → TestFlight → the **Fishers** group → add/resend invite, or run
`bundle exec fastlane ios invite_testers` on the Mac Studio with ASC secrets
loaded.

### 3. Self-hosted runner

The Mac Studio runner needs:

- Xcode 16+, XcodeGen, Ruby + Bundler
- Label: `self-hosted`
- WSLVault token (`VAULT_TOKEN` or `~/.secrets/wslvault/token.json`) unless GitHub secrets are set
- Reachable `https://vault.workstation.co.uk`

### 4. GitHub workflows

| Workflow | Purpose |
|----------|---------|
| **iOS** (`ios.yml`) | Simulator build + `FishersTests` on `macos-latest` |
| **iOS Release** (`ios_release.yml`) | Sign + TestFlight / App Store |
| **Auto Tag** (`auto-tag.yml`) | Patch-bump `v*` on each `main` push |

**TestFlight (automatic):**

1. Merge a PR that changes `ios/**` into `main`
2. Actions → **iOS Release** runs on the Mac Studio → internal TestFlight

**TestFlight (manual):**

1. Actions → **iOS Release (TestFlight & App Store)**
2. Run workflow → target **testflight**
3. Version blank = `MARKETING_VERSION` from `ios/project.yml`

**App Store (after QA):**

1. Same workflow → target **app_store**

## Local dry run (on the Mac Studio)

```bash
cd ios
export VAULT_ADDR=https://vault.workstation.co.uk
export VAULT_TOKEN_FILE=$HOME/.secrets/wslvault/token.json
eval "$(./ci/load-ios-vault-secrets.sh)"
export BUILD_KEYCHAIN_PATH=$HOME/Library/Keychains/fishers-signing.keychain-db
export BUILD_KEYCHAIN_PASSWORD=$(cat $HOME/.secrets/fishers/keychain-password)
export EXPORT_OPTIONS_PLIST=/tmp/ExportOptions.plist
export VERSION_NAME=1.0.0
bundle install
bundle exec fastlane ios ci_build_number
export BUILD_NUMBER=<from output>
bundle exec fastlane ios prepare_signing
bundle exec fastlane ios build_ipa
bundle exec fastlane ios beta
```

## Files

| Path | Purpose |
|------|---------|
| `.github/workflows/ios.yml` | Simulator CI |
| `.github/workflows/ios_release.yml` | Signed release → TestFlight / App Store |
| `.github/workflows/auto-tag.yml` | Patch tags on `main` |
| `ios/fastlane/Fastfile` | Lanes: test, ci_build_number, prepare_signing, build_ipa, beta, release |
| `ios/fastlane/Appfile` | Bundle id |
| `ios/ci/load-ios-vault-secrets.sh` | Vault → env |
| `ios/ci/ios.vault.env.example` | Secret field reference |
| `ios/project.yml` | `MARKETING_VERSION` source of truth |
