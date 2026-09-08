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

Release CI runs on the self-hosted Mac Studio runner with labels
`[self-hosted, macOS, ARM64]`. Signing material is **not** stored in GitHub —
it is loaded from Vault and wiped after each run.

## Flow

```
Merge to main (ios/** changed)     or     push v1.2.3 tag     or     workflow_dispatch
                 │                                  │                         │
                 └──────────────────┬───────────────┴─────────────────────────┘
                                    ▼
                      Load Vault secrets (ASC API key)
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

### 1. App Store Connect

1. Create app **Fishers** with bundle id `com.fishers.app`
2. Generate an **App Store Connect API** key (App Manager role)
3. Note your **Apple Team ID**

### 2. Vault secret

Store at **`secret/fishers/ios`** (KV v2):

| Key | Description |
|-----|-------------|
| `ASC_KEY_ID` | API key id |
| `ASC_ISSUER_ID` | Issuer id |
| `ASC_PRIVATE_KEY_B64` | base64 of `AuthKey_*.p8` |
| `CERT_PRIVATE_KEY_B64` | (optional) base64 of distribution private key `.pem` |
| `APPLE_TEAM_ID` | 10-character team id |
| `APP_STORE_APP_ID` | (optional) numeric ASC app id |

See `ios/ci/ios.vault.env.example`.

### 3. Self-hosted runner

The Mac Studio runner needs:

- Xcode 16+, XcodeGen, Ruby + Bundler
- Vault token file (default `VAULT_TOKEN_FILE` in workflow)
- Labels: `self-hosted`, `macOS`, `ARM64`

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
export VAULT_TOKEN_FILE=$HOME/.secrets/acc-vault/login-token.json
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
