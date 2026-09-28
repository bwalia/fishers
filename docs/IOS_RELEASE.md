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
or from **WSLVault** at `https://vault.workstation.co.uk` path
**`kv/<brand>/ios`**, then wiped after each run. This repo does **not** use
`vault.diytaxreturn.co.uk`.

> **The GitHub-secrets path is single-brand.** `ASC_KEY_ID` and friends are one
> set of repository secrets, and they win over Vault when present — so with two
> brands they would sign both with Fishers' Apple account. Use Vault
> (`kv/<brand>/ios`) for anything past the first brand, or the second brand's
> builds will be rejected by App Store Connect as the wrong app.

## One app per brand

Every brand in `brands/` is its own App Store app: its own bundle id, its own
listing, its own TestFlight group. They share one Xcode project and one scheme
(`Fishers`) — the brand is configuration, not a target.

| brand | bundle id |
|---|---|
| `fishers` | `com.fishers.app` |
| `gullycricket` | `app.gullycricket` |

`node tools/brand/index.mjs mobile <id>` prints it. That comes from
`brands/<id>.yaml`, which is the source of truth rather than this table.

A push to main releases **every** brand. A dispatch releases the one you ask
for. The matrix runs one at a time: there is one Mac, one signing keychain and
one Ruby bundle, and two brands building at once would fight over all three.

> **Only Fishers has ever shipped.** GullyCricket has no App Store Connect app
> and no `kv/gullycricket/ios` in Vault, so its first run will fail until both
> exist. The pipeline is ready for it; Apple's side is not.

## Flow

```
Merge to main (ios/** changed)     or     push v1.2.3 tag     or     workflow_dispatch
                 │                                  │                         │
                 └──────────────────┬───────────────┴─────────────────────────┘
                                    ▼
                    For each brand in brands/ (one at a time)
                                    │
                                    ▼
      Generate the brand → brand.xcconfig, Brand.generated.swift, artwork
      BRAND_APP_ID / BRAND_NAME into the environment for fastlane
                                    │
                                    ▼
              Load ASC secrets (GitHub secrets or Vault kv/<brand>/ios)
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

### Why the generate step matters

`project.yml` names `Fishers/Brand/Generated/brand.xcconfig`, which is
gitignored and does not exist until the generator runs. On the self-hosted Mac
that file survives between runs, so before this step existed the workflow
signed whatever branding the **previous** build had left on disk. With two
brands that is not a cosmetic bug: it is one brand's build uploaded to the
other's listing, which App Store Connect accepts.

The same step exports `BRAND_APP_ID`, which `fastlane/Appfile` and the
`APP_ID` constant in `fastlane/Fastfile` both read. Every use of the bundle id
in the Fastfile goes through that one constant, so a brand is an environment
variable rather than thirteen edits.

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
| `GOOGLE_IOS_CLIENT_ID` | Optional; Google Cloud iOS OAuth client id |
| `GOOGLE_REVERSED_CLIENT_ID` | Optional; reversed client id (URL scheme) |

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
| `GOOGLE_IOS_CLIENT_ID` | (optional) Google Cloud iOS OAuth client id |
| `GOOGLE_REVERSED_CLIENT_ID` | (optional) reversed client id used as the Google URL scheme |

`GOOGLE_IOS_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID` are loaded from Vault or
GitHub secrets at build time and written into `project.yml` just before
xcodegen — they are **not** committed to git. The ring vault config already
holds `GOOGLE_IOS_CLIENT_ID` / `APPLE_CLIENT_ID` for the API; keep the same
iOS client id (plus its reversed form) under `kv/fishers/ios` for the app
build.

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
For another brand, seed `kv/<brand>/ios` with that brand's own ASC key, issuer,
team and certificate — the workflow reads `kv/${{ matrix.brand }}/ios`.
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

**TestFlight on every `main` merge:**

1. Upload the IPA, attach it to internal **Fishers Team** (ASC team members
   install in the TestFlight app — **no invite email**) and external **Fishers**.
2. Cancel any stuck **Waiting for Review**, then submit the latest build for
   Beta App Review. Apple **refuses** TestFlight install invite emails with
   “tester has no installable build” until Fishers has a distributed build.
3. **Delete + re-add** `balindersinghwalia@icloud.com` and `harchran001@gmail.com`,
   then call `betaTesterInvitations` for the real invite
   (`You're invited to test Fishers Sport` — **not** processing-complete).
4. If no email: open **https://testflight.apple.com/join/YXCcSAPj** on iPhone.
5. Resend without a new IPA: **Actions → iOS Release → `invite_testers`**.

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
2. Run workflow → **brand** (default `fishers`), target **testflight**
3. Version blank = `MARKETING_VERSION` from `ios/project.yml`

A brand id that is not in `brands/` fails in the first job, in seconds, rather
than after the Mac has spent forty minutes discovering the same thing.

**App Store (after QA):**

1. Same workflow → target **app_store**

## Local dry run (on the Mac Studio)

```bash
# Which brand — this is what the workflow's first step does. Without it
# fastlane signs whatever brand.xcconfig was left on disk by the last build.
BRAND=fishers
node tools/brand/index.mjs generate "$BRAND" --ios
eval "$(node tools/brand/index.mjs mobile "$BRAND" | sed 's/^/export /')"

cd ios
export VAULT_ADDR=https://vault.workstation.co.uk
export VAULT_TOKEN_FILE=$HOME/.secrets/wslvault/token.json
export FISHERS_IOS_VAULT_PATH="kv/$BRAND/ios"
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
| `ios/fastlane/Appfile` | Bundle id, from `BRAND_APP_ID` |
| `brands/<id>.yaml` | The brand: bundle id, display name, palette |
| `tools/brand/index.mjs` | `generate <id> --ios`, and `mobile <id>` for the env |
| `ios/ci/load-ios-vault-secrets.sh` | Vault → env |
| `ios/ci/ios.vault.env.example` | Secret field reference |
| `ios/project.yml` | `MARKETING_VERSION` source of truth |
