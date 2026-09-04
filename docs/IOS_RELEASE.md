# iOS Release Pipeline (GitHub Actions + fastlane + Vault)

Builds, signs, and ships the native **Fishers** iOS app from `ios/`.

| Stage | How | When |
|-------|-----|------|
| **PR / push CI** | `.github/workflows/ios.yml` | Simulator build + unit tests |
| **TestFlight (internal)** | `workflow_dispatch` → target **testflight** (default) | Everyday QA builds |
| **App Store review** | `workflow_dispatch` → target **app_store** | After TestFlight sign-off |
| **Tag release** | Push `v*.*.*` tag | Formal version cuts (TestFlight only) |

Release CI runs on the self-hosted Mac Studio runner with labels `[self-hosted, macOS, ARM64]`. Signing material is **not** stored in GitHub — it is loaded from Vault and wiped after each run.

## Flow

```
Run workflow (or push v1.2.3 tag)
        │
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
        ├── testflight → upload_to_testflight (internal only)
        └── app_store  → upload + deliver(submit_for_review: true)
```

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

**TestFlight:**

1. Actions → **iOS Release (TestFlight & App Store)**
2. Run workflow → target **testflight**
3. Version blank = `MARKETING_VERSION` from `ios/project.yml`

**App Store (after QA):**

1. Same workflow → target **app_store**
2. Submits for review (`automatic_release: false` — release manually in ASC when approved)

## Local dry run (on the Mac Studio)

```bash
cd ios
export VAULT_TOKEN_FILE=$HOME/.secrets/acc-vault/login-token.json
eval "$(./ci/load-ios-vault-secrets.sh)"
export BUILD_KEYCHAIN_PATH=/tmp/fishers-ios.keychain-db
export BUILD_KEYCHAIN_PASSWORD=$(openssl rand -base64 24)
export EXPORT_OPTIONS_PLIST=/tmp/ExportOptions.plist
export VERSION_NAME=1.0.0
bundle install
bundle exec fastlane ios ci_build_number   # note build number
export BUILD_NUMBER=<from output>
bundle exec fastlane ios prepare_signing
bundle exec fastlane ios build_ipa
bundle exec fastlane ios beta
```

## Local CI test (no signing)

```bash
cd ios
xcodegen generate
bundle exec fastlane ios test
# or:
xcodebuild test -project Fishers.xcodeproj -scheme Fishers \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Files

| Path | Purpose |
|------|---------|
| `.github/workflows/ios.yml` | PR CI (simulator build + test) |
| `.github/workflows/ios_release.yml` | Release workflow |
| `ios/fastlane/Fastfile` | Lanes: `test`, `ci_build_number`, `prepare_signing`, `build_ipa`, `beta`, `release` |
| `ios/ci/load-ios-vault-secrets.sh` | Vault → env + key files |
| `ios/Gemfile` | fastlane dependency |

## Versioning

- **Marketing version** — `MARKETING_VERSION` in `ios/project.yml`, overridable in workflow dispatch
- **Build number** — auto-incremented per marketing version from TestFlight (`latest + 1`)

Bump `MARKETING_VERSION` in `project.yml` before a new App Store version line.
