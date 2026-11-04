# Android release (Google Play)

One app per brand in `brands/`. Each has its own `applicationId`, its own Play
listing, and its own upload keystore — they are separate products that share a
codebase, not one product with a skin.

| Workflow | Trigger | Does |
|---|---|---|
| `android-kotlin.yml` | any change to `android/**` | build the engine, run the tests, build a debug APK for every brand |
| `android_release.yml` | merge to main, a `v*.*.*` tag, or dispatch | build a signed AAB per brand and upload it to Play |

A push releases **every** brand to `internal`. A dispatch releases the one you
pick, to the track you pick. Skip an automatic release with `[skip release]` or
`[skip android]` in the commit message.

> **Nothing has shipped from Android yet.** The pipeline is written and the
> build is proven locally, but it has never run against Play — no brand has a
> listing and no secret is set. The first release of each brand is manual (see
> below), and the first automated run after that is the real test.

## Before the first release of a brand

**Play's API cannot create an app.** The first bundle has to be uploaded by
hand in the Play Console and the listing filled in, before the workflow can
push anything. Trying the API first fails with a package-not-found that reads
like a credentials problem and is not one.

Per brand, in order:

1. Create the app in the Play Console under its own `applicationId`:

   | brand | applicationId |
   |---|---|
   | `fishers` | `com.fishers.app` |
   | `gullycricket` | `app.gullycricket` |

   `node tools/brand/index.mjs mobile <id>` prints it, and it comes from
   `brands/<id>.yaml` — that file is the source of truth, not this table.

2. Get a signed AAB and upload it manually to **internal testing**. Build it
   locally (below), or — easier, since CI holds the upload keystore and your
   laptop may not — dispatch this workflow with **upload** off:

   ```
   gh workflow run android_release.yml -f brand=<id> -f track=internal -f upload=false
   ```

   That builds and signs the bundle, skips Play entirely, and leaves the AAB
   as the run's `<brand>-aab` artifact for you to download and upload by hand.
3. Complete the store listing and content rating. The listing text is already
   written, per brand, in `android/fastlane/metadata/<brand>/en-GB/` —
   `title.txt`, `short_description.txt`, `full_description.txt`. Nothing
   publishes those files: `r0adkll/upload-google-play` uploads a bundle and
   nothing else, so they are copy-and-paste sources, not a deployment. Keep
   them in step with what is live, or delete them rather than let them drift.
4. Then the workflow takes over.

## Signing

Play App Signing holds the real app signing key; what CI holds is the **upload
key**, which only proves a bundle came from us. If it leaks it can be rotated
in the Play Console without republishing the app — that is the whole point of
the split, and the reason CI never touches the app signing key.

Each brand needs its own upload keystore, because each is a separate Play app:

```bash
keytool -genkey -v \
  -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

Base64 it for the secret:

```bash
base64 -i upload-keystore.jks | pbcopy   # macOS
```

### How the build picks a key

`android/app/build.gradle.kts` reads `android/key.properties` if it is there
and signs with that; if it is not, it falls back to the **debug** key so
`assembleRelease` works on a machine with no keystore. The release workflow
writes `key.properties` from secrets, or fails by name before Gradle runs —
so a debug-signed bundle can never reach Play.

To sign locally, create `android/key.properties` (gitignored):

```properties
storeFile=upload-keystore.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

with the `.jks` beside it in `android/`.

## Continue with Google

The button is in the app and needs **nothing from the server** — it asks
`GET /auth/google` whether to appear, gets a Google ID token for the *web*
client id, and posts it to the same `POST /auth/google` the website and the
iPhone use. What it does need is something no build can check: Google only
hands a token to an app it has been told about.

Per brand, in that brand's own Google Cloud project (`brands/<id>.yaml` →
`googleIosClientId` names the project by its number):

1. **APIs & Services → Credentials → Create credentials → OAuth client ID →
   Android.**
2. **Package name:** the brand's `applicationId` (`node tools/brand/index.mjs
   mobile <id>` prints it).
3. **SHA-1 certificate fingerprint:** one client per fingerprint, same package.
   An app can be signed three ways, and each is a different key:

   | Where the APK comes from | Whose key | Where to read its SHA-1 |
   |---|---|---|
   | Play (internal testing onwards) | **Play App Signing** key | Play Console → *Test and release* → *App integrity* → *App signing key certificate* |
   | A bundle uploaded by hand, or CI's APK | the **upload** key | the same page → *Upload key certificate* |
   | Built and installed on a developer's machine | that machine's **debug** key | `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android` |

   The Play App Signing one is the one that matters for users: the app they
   install from the store is re-signed with it, whatever signed the upload.

Missing or mismatched, Google does not say so. It answers "no credential
available", which the app can only report as *there is no Google account on
this phone* — the same words as genuinely having none. If the button opens
Google's chooser and then fails, check the fingerprint before anything else.

The server side needs no change: it verifies the token's audience against the
web client id (`GOOGLE_CLIENT_ID`), which is what the app asks Google to mint it
for. `GET /auth/google` returning `"enabled": false` hides the button.

## Repository secrets

| Secret | What |
|---|---|
| `ANDROID_KEYSTORE_B64` | base64 of `upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | its store password |
| `ANDROID_KEY_ALIAS` | the alias (`upload` above) |
| `ANDROID_KEY_PASSWORD` | that key's password |
| `PLAY_SERVICE_ACCOUNT_JSON` | the whole service-account JSON, pasted |

> **These are single-brand today.** One set of `ANDROID_*` secrets signs
> whichever brand is building, which is only correct while one brand has a
> listing. Before the second brand ships, split them — per-brand secret names,
> or move them to WSLVault under `kv/<brand>/android` the way iOS does. Signing
> two Play apps with one upload key is not a security hole, but it couples two
> products' release keys, and rotating one then forces the other.

### The Play service account

1. Play Console → **Setup → API access** → link or create a Google Cloud project.
2. Create a service account, grant it **Release manager** (or narrower: release
   to testing tracks only).
3. Create a JSON key for it and paste the file's contents into
   `PLAY_SERVICE_ACCOUNT_JSON`.

Permissions can take a few hours to propagate. A `403` on the first run usually
means "not yet", not "wrong".

## Versioning

`versionName` comes from the tag (`v1.4.0` ships as `1.4.0`), or the dispatch
input, or `versionName` in `android/app/build.gradle.kts`.

`versionCode` is **`github.run_number`**. Play refuses a versionCode it has
already seen, and a counter kept in a file two people edit is a merge conflict
that surfaces as a failed release. The run number only goes up.

Both reach Gradle as properties:

```bash
./gradlew :app:bundleFishersRelease -PappVersionName=1.4.0 -PappVersionCode=57
```

They are named `app*` so neither can collide with a Gradle property of its own.
Without them the build uses the defaults in `build.gradle.kts`, which is what a
local build wants.

## Tracks

`internal` → `alpha` → `beta` → `production`. Automatic releases always go to
`internal`; production is a deliberate dispatch after QA, the same way the App
Store is on iOS.

## Building locally

```bash
cd android
./gradlew :app:bundleFishersRelease        # or :app:bundleGullycricketRelease
```

There is one task per brand. `:app:bundleRelease` builds **every** brand, which
is rarely what you want for a release.

It needs a Rust toolchain and the NDK, like every Android build here: the
cricket engine is Rust, cross-compiled in. There is no fallback that skips it,
because an app with no scoring rules is worse than no app.

On a Mac with no JDK on `PATH`, Android Studio's bundled one works:

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/27.0.12077973"
export PATH="$HOME/.cargo/bin:$JAVA_HOME/bin:$PATH"
```

## What the release build does

`isMinifyEnabled` and `isShrinkResources` are on, so the bundle ships an R8
mapping file and native debug symbols, both uploaded to Play. Without them a
release stack trace is unreadable.

`android/app/proguard-rules.pro` keeps only what R8 cannot work out for itself:
kotlinx.serialization finds its serializers by annotation, and without the keep
rules a release build decodes every API response into nothing. Nothing
speculative goes in there — a rule added just in case is a rule nobody can
safely remove later.

R8's mapping file travels **inside** the bundle, at
`BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map`, and Play
reads it from there — so the workflow does not upload it separately.

`scripts/check-android-flavours.py` runs in CI and again before a release. The
flavour's `applicationId` and the brand file's bundle id are typed out in two
places, and disagreeing silently would put one brand's code on the other's Play
listing, which Play would accept.

### No native crash symbols, yet

The cricket engine is Rust and its `.so` ships **stripped**, so a native stack
trace in Play is addresses and nothing else. `ndk { debugSymbolLevel }` does not
help: there is nothing in the binary for it to extract, and setting it produces
an empty directory.

Fixing it means keeping the symbol table in the Rust build — `strip =
"debuginfo"` rather than the default in the release profile, which keeps names
and drops the bulky debug info. That inflates the download, so it is a decision
to take deliberately rather than a default to flip. Kotlin stack traces are
unaffected: those come from the mapping file above, which is already there.
